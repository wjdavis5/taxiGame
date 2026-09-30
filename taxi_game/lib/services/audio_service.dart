import 'dart:async' show unawaited;

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Audio playback for the game (issue #4), on top of `flame_audio`.
///
/// Every asset lives under `assets/audio/` — which is exactly the prefix
/// [FlameAudio] already reads — so this service addresses files relative to
/// that folder. The full inventory is licensed in
/// `assets/licenses/LICENSES.txt`; nothing attribution-required ships.
///
/// **Every platform call is swallowed on failure.** The service must never
/// crash the game — under `flutter test` there is no audio plugin at all, and
/// on a device a failed play must cost nothing but the sound. Tests observe
/// the service through [attemptedPlays], which records the sounds playback was
/// *attempted* for after the enabled-gates have run.
class AudioService {
  /// Logical sound name → bundled file, relative to `assets/audio/`. Public
  /// so the license-inventory test can walk every mapped file.
  static const Map<String, String> soundFiles = {
    'crash': 'sfx/crash.wav',
    'scrape': 'sfx/scrape.wav',
    'pickup': 'sfx/pickup.wav',
    'dropoff': 'sfx/dropoff.wav',
    'coin': 'sfx/coin.wav',
    'brake': 'sfx/brake.wav',
    'button_click': 'sfx/ui_click.wav',
    'level_complete': 'music/jingle_complete.wav',
    'level_failed': 'music/jingle_wrecked.wav',
    'banked': 'music/jingle_banked.wav',
  };

  /// The one looping music track (issue #4): a mellow shift backing loop.
  static const String musicTrack = 'music/shift_loop.wav';

  /// The engine rumble loop, driven by [setEngineRunning] and
  /// [setEngineIntensity].
  static const String engineLoop = 'sfx/engine_loop.wav';

  /// Per-sound default volumes — one-shots mixed by ear: the crash and the
  /// jingles carry, the click and the coin tuck under them.
  static const Map<String, double> _defaultVolumes = {
    'crash': 0.9,
    'scrape': 0.7,
    'pickup': 0.8,
    'dropoff': 0.8,
    'coin': 0.6,
    'brake': 0.65,
    'button_click': 0.55,
    'level_complete': 0.75,
    'level_failed': 0.75,
    'banked': 0.75,
  };

  /// The iOS audio session context (issue #39): category `.ambient`.
  ///
  /// audioplayers_darwin's default session is `.playback` with no mixing
  /// options (AudioContext.swift, `AudioContext.init`), so on launch the game
  /// stops whatever the player was listening to and plays over the
  /// Ring/Silent switch. `.ambient` is the casual-game convention: it mixes
  /// with other apps' audio — music, podcasts — and is silenced by the
  /// Ring/Silent switch. The in-app sound and music toggles remain the
  /// explicit per-feature control on top of that.
  ///
  /// Why no explicit `.mixWithOthers` option, although it mixes: on iOS
  /// `.ambient` mixes with other audio *by definition* — the option exists
  /// for `.playback` — and the locked audioplayers_platform_interface
  /// asserts `mixWithOthers` is only legal with `playback`, `playAndRecord`
  /// or `multiRoute`, so setting it here would throw in debug builds.
  ///
  /// Off iOS this is null and everything below becomes a no-op: Android
  /// mixes by default and must keep doing exactly what it does today.
  static final AudioContext _ambientContext = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  /// The session context [initialize] claims, or null off iOS — which makes
  /// flame_audio's BGM apply its own default, preserving non-iOS behavior.
  AudioContext? get _platformContext =>
      defaultTargetPlatform == TargetPlatform.iOS ? _ambientContext : null;

  /// flame_audio's own per-player default: mix with others, never take
  /// audio focus.
  static final AudioContext _mixWithOthersContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  /// The context each new player gets, once, when it is created — off iOS
  /// only.
  ///
  /// On iOS a player-level context *is* the global session:
  /// audioplayers_darwin answers it with `setCategory` + `setActive` on the
  /// main thread. [initialize] already claimed that session as ambient, so
  /// re-applying it on every play (as this service used to) only burned
  /// main-thread time (issue #49). Off iOS it is the mix-with-others default
  /// flame_audio applied to every player it made, so Android keeps doing
  /// exactly what it did.
  AudioContext? get _playerContext =>
      defaultTargetPlatform == TargetPlatform.iOS ? null : _mixWithOthersContext;

  /// Completes once [initialize] has claimed the iOS session. New players
  /// wait for it, so nothing ever plays under the plugin's launch-time
  /// `.playback` default — the guarantee issue #39 used to buy by
  /// re-applying the context on every play.
  Future<void>? _sessionReady;

  bool _soundEnabled = true;
  bool _musicEnabled = true;

  /// Music state: the app wants one track playing whenever music is enabled
  /// ([playMusic] declares the want; the settings toggle gates it).
  bool _musicWanted = false;

  /// Engine loop state. The running *want* is re-asserted every frame by the
  /// game, so pause, crash stalls, and lifecycle changes only ever flip the
  /// want off — the next live frame brings the engine back.
  ///
  /// Issue #49: the loop has exactly **one** native player for the life of
  /// the service. It is created once, then only paused and resumed. On a
  /// device, creating a player takes longer than a frame. The old code
  /// started a fresh player on every frame of that wait and threw each one
  /// away, about 120 AVPlayers a second, until iOS ran out of threads and
  /// the watchdog killed the app.
  AudioPlayer? _enginePlayer;
  bool _engineWanted = false;
  double _engineIntensity = 0;
  bool _suspended = false;

  /// A start is in flight: no second one may begin until it lands.
  bool _engineStarting = false;

  /// What the adopted player was last told: playing (true) or paused. The
  /// per-frame re-assertion compares against this and, in the steady state,
  /// makes no platform call at all.
  bool _engineAudible = false;

  /// The engine volume last sent, in [_engineVolumeStep] units. Frame-rate
  /// intensity updates only reach the platform when this changes.
  int _engineSentStep = -1;

  /// Engine volume resolution. 0.02 is inaudible as a step, and it caps a
  /// full idle-to-redline sweep at 34 `setVolume` calls.
  static const double _engineVolumeStep = 0.02;

  /// After a failed start, no retry before this time. Consecutive failures
  /// double the wait (2 s up to 64 s), so a platform that keeps failing
  /// costs one attempt now and then, not one attempt per frame.
  DateTime? _engineRetryAfter;
  int _engineStartFailures = 0;

  /// Bumped by [dispose]: a player that finishes preparing after that is
  /// disposed rather than adopted.
  int _epoch = 0;

  /// One-shot voices, per sound name (issue #49). Each sound owns at most
  /// [_voicesPerSound] players, created on first use and replayed from then
  /// on. The old path made a new player for every play and never disposed
  /// it, one leaked AVPlayer per pickup, coin, click, and scrape.
  final Map<String, _Voices> _voices = <String, _Voices>{};

  /// Two voices let a sound overlap its own tail (coin after coin) without
  /// the pool ever growing past a fixed, small native footprint.
  static const int _voicesPerSound = 2;

  /// The sounds playback was attempted for, since construction (issue #4).
  /// Gated calls never register — tests assert against this to check the
  /// enabled-gates without a platform plugin.
  @visibleForTesting
  final Map<String, int> attemptedPlays = <String, int>{};

  /// Initializes the BGM lifecycle handler (auto pause/resume around app
  /// backgrounding), claims the iOS audio session (issue #39), and warms the
  /// sound cache. Safe to call twice; safe when no plugin exists (tests) —
  /// everything below swallows its failures.
  Future<void> initialize() async {
    final sessionReady = _sessionReady = _applyIosAudioContext();
    await sessionReady;
    // The music never reads its position, so it must not poll for it: the
    // default updater asks the platform every frame while playing (#49).
    FlameAudio.bgm.audioPlayer.positionUpdater = null;
    try {
      await FlameAudio.bgm.initialize(audioContext: _platformContext);
    } catch (_) {}
    try {
      // The engine loop is warmed with the rest (issue #49): an unwarmed
      // first start also has to copy the asset into the cache.
      await FlameAudio.audioCache.loadAll([...soundFiles.values, engineLoop]);
    } catch (_) {}
  }

  /// Applies the ambient session (issue #39) on iOS before any player
  /// exists, replacing the plugin's launch-time `.playback` default. Off iOS
  /// this is a no-op — Android mixes by default and gets no counterpart. A
  /// failure is swallowed: a session that will not configure must never
  /// crash or block startup.
  Future<void> _applyIosAudioContext() async {
    final context = _platformContext;
    if (context == null) return;
    try {
      await AudioPlayer.global.setAudioContext(context);
    } catch (_) {}
  }

  /// True when music should currently be audible.
  @visibleForTesting
  bool get isMusicWanted => _musicWanted && _musicEnabled && !_suspended;

  /// Whether the engine loop is running: its player exists and is not paused
  /// (test observability — there is nothing audible to assert against under
  /// flutter test).
  @visibleForTesting
  bool get isEngineLoopActive => _enginePlayer != null && _engineAudible;

  // --- players --------------------------------------------------------------

  /// Creates one native player with [file] loaded and ready to resume, or
  /// returns null if any step fails. A failed player is disposed here, so
  /// a half-made player can never leak (issue #49).
  Future<AudioPlayer?> _preparePlayer(
    String file, {
    required ReleaseMode releaseMode,
    required double volume,
    void Function(Object error)? onError,
  }) async {
    await _sessionReady;
    final player = AudioPlayer()
      ..audioCache = FlameAudio.audioCache
      // Nothing here reads playback position. The default updater would
      // ask the platform for it on every frame the player is playing.
      ..positionUpdater = null;
    try {
      final context = _playerContext;
      if (context != null) await player.setAudioContext(context);
      await player.setReleaseMode(releaseMode);
      await player.setVolume(volume);
      await player.setSource(AssetSource(file));
      return player;
    } catch (error) {
      onError?.call(error);
      unawaited(_disposeQuietly(player));
      return null;
    }
  }

  static Future<void> _disposeQuietly(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (_) {}
  }

  static Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {}
  }

  // --- one-shot sounds ------------------------------------------------------

  /// Plays the one-shot named [soundName] (see [soundFiles]). Unknown names
  /// are ignored rather than guessed at. Fire and forget.
  ///
  /// Plays through the sound's voice pool: an idle voice is replayed; if
  /// every voice is busy and the pool is not full, a new voice is made for
  /// this play; if the pool is full, the voice after the last one used is
  /// restarted. A play that arrives while the pool's only voices are still
  /// being created is dropped, which only happens in the sound's first few
  /// milliseconds.
  void playSound(String soundName, {double? volume}) {
    if (!_soundEnabled) return;
    final file = soundFiles[soundName];
    if (file == null) return;
    attemptedPlays.update(soundName, (n) => n + 1, ifAbsent: () => 1);
    final level = volume ?? _defaultVolumes[soundName] ?? 1.0;
    final voices = _voices.putIfAbsent(soundName, _Voices.new);

    AudioPlayer? idle;
    for (final voice in voices.ready) {
      if (voice.state != PlayerState.playing) {
        idle = voice;
        break;
      }
    }
    if (idle == null &&
        voices.ready.length + voices.creating < _voicesPerSound) {
      _addVoice(voices, file, level);
      return;
    }
    final voice = idle ??
        (voices.ready.isEmpty
            ? null
            : voices.ready[voices.next++ % voices.ready.length]);
    if (voice == null) return;
    unawaited(_quietly(() async {
      await voice.stop();
      if (voice.volume != level) await voice.setVolume(level);
      await voice.resume();
    }));
  }

  /// Grows [voices] by one player, which plays as soon as it is ready.
  void _addVoice(_Voices voices, String file, double level) {
    voices.creating++;
    final epoch = _epoch;
    unawaited(() async {
      final player = await _preparePlayer(
        file,
        releaseMode: ReleaseMode.stop,
        volume: level,
      );
      if (epoch != _epoch) {
        if (player != null) unawaited(_disposeQuietly(player));
        return;
      }
      voices.creating--;
      if (player == null) return;
      voices.ready.add(player);
      await _quietly(player.resume);
    }());
  }

  // --- music ----------------------------------------------------------------

  /// Starts the looping music track. Remembered even while music is disabled,
  /// so re-enabling music resumes the same track.
  Future<void> playMusic() async {
    _musicWanted = true;
    if (!isMusicWanted) return;
    try {
      await FlameAudio.bgm.play(musicTrack, volume: 0.8);
    } catch (_) {}
  }

  /// Stops the music and clears the want — called when the player turns
  /// music off, not by pausing (backgrounding pauses via [pauseAll]).
  Future<void> stopMusic() async {
    _musicWanted = false;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {}
  }

  // --- engine loop ----------------------------------------------------------

  /// Sets whether the engine should be running (the taxi is live on the
  /// road). Idempotent and safe from every frame: once the loop exists, a
  /// call that changes nothing makes no platform call (issue #49).
  void setEngineRunning(bool running) {
    _engineWanted = running;
    _syncEngine();
  }

  /// Speed 0..1 — scales the engine from idle to revved. Cheap enough to
  /// call every frame: the platform only hears about it when the volume
  /// moves by a whole [_engineVolumeStep].
  void setEngineIntensity(double intensity) {
    _engineIntensity = intensity.clamp(0.0, 1.0);
    _applyEngineVolume();
  }

  /// Idle hum under a stopped taxi, up to a full rev.
  double get _engineVolume => 0.22 + 0.68 * _engineIntensity;

  int get _engineVolumeSteps => (_engineVolume / _engineVolumeStep).round();

  void _applyEngineVolume() {
    final player = _enginePlayer;
    if (player == null) return;
    final steps = _engineVolumeSteps;
    if (steps == _engineSentStep) return;
    _engineSentStep = steps;
    unawaited(_quietly(() => player.setVolume(steps * _engineVolumeStep)));
  }

  void _syncEngine() {
    final want = _engineWanted && _soundEnabled && !_suspended;
    final player = _enginePlayer;
    if (player == null) {
      if (want) _startEngine();
      return;
    }
    if (want) _applyEngineVolume();
    if (want == _engineAudible) return;
    _engineAudible = want;
    unawaited(_quietly(want ? player.resume : player.pause));
  }

  /// Creates the one engine player. At most one start is ever in flight,
  /// and a failed one backs off before the next try. When the player is
  /// ready it is adopted paused, and [_syncEngine] then applies whatever
  /// the game wants *by then*.
  void _startEngine() {
    if (_engineStarting) return;
    final retryAfter = _engineRetryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) return;
    _engineStarting = true;
    final epoch = _epoch;
    final steps = _engineVolumeSteps;
    unawaited(() async {
      final player = await _preparePlayer(
        engineLoop,
        releaseMode: ReleaseMode.loop,
        volume: steps * _engineVolumeStep,
        onError: (error) =>
            debugPrint('[audio] engine loop failed to start: $error'),
      );
      if (epoch != _epoch) {
        if (player != null) unawaited(_disposeQuietly(player));
        return;
      }
      _engineStarting = false;
      if (player == null) {
        _engineStartFailures++;
        final backoff = 1 << _engineStartFailures.clamp(1, 6);
        _engineRetryAfter = DateTime.now().add(Duration(seconds: backoff));
        return;
      }
      _engineStartFailures = 0;
      _engineRetryAfter = null;
      _enginePlayer = player;
      _engineAudible = false;
      _engineSentStep = steps;
      debugPrint('[audio] engine loop started');
      _syncEngine();
    }());
  }

  // --- settings -------------------------------------------------------------

  /// Set sound enabled/disabled. Turning sound off kills the engine loop
  /// outright; turning it back on hands the want back to the next live game
  /// frame, which re-asserts it.
  void setSoundEnabled(bool enabled) {
    if (_soundEnabled == enabled) return;
    _soundEnabled = enabled;
    _syncEngine();
  }

  /// Set music enabled/disabled. Disabling stops playback; enabling restarts
  /// the wanted track from its top.
  Future<void> setMusicEnabled(bool enabled) async {
    if (_musicEnabled == enabled) return;
    _musicEnabled = enabled;
    if (enabled && _musicWanted) {
      await playMusic();
    } else if (!enabled) {
      try {
        await FlameAudio.bgm.stop();
      } catch (_) {}
    }
  }

  /// Applies both settings at once (startup sync from the save).
  Future<void> applySettings({
    required bool soundEnabled,
    required bool musicEnabled,
  }) async {
    setSoundEnabled(soundEnabled);
    await setMusicEnabled(musicEnabled);
  }

  // --- lifecycle ------------------------------------------------------------

  /// Pause all audio: the app left the foreground. The engine's *want* is
  /// cleared, not kept — a backgrounded shift returns through the pause
  /// menu, not straight onto a live street, and the engine comes back only
  /// when a live game frame re-asserts it. Music resumes through
  /// [resumeAll], which the same game frames cannot do for themselves.
  Future<void> pauseAll() async {
    _suspended = true;
    setEngineRunning(false);
    try {
      await FlameAudio.bgm.pause();
    } catch (_) {}
  }

  /// Resume after [pauseAll]. Music resumes if the player still wants it;
  /// the engine stays silent until the game's update loop re-asserts the
  /// running want on a live street.
  Future<void> resumeAll() async {
    _suspended = false;
    _syncEngine();
    if (isMusicWanted) {
      try {
        await FlameAudio.bgm.resume();
      } catch (_) {}
    }
  }

  /// Releases the engine player, every one-shot voice, and the BGM
  /// observer. The service is an app-lifetime singleton; this exists for
  /// tests and hot restarts.
  Future<void> dispose() async {
    _epoch++;
    _engineStarting = false;
    _engineAudible = false;
    final engine = _enginePlayer;
    final players = [
      if (engine != null) engine,
      for (final voices in _voices.values) ...voices.ready,
    ];
    _enginePlayer = null;
    _voices.clear();
    await Future.wait(players.map(_disposeQuietly));
    try {
      await FlameAudio.bgm.dispose();
    } catch (_) {}
  }

  // --- predefined gameplay sounds -------------------------------------------

  void playCrashSound() => playSound('crash');
  void playScrapeSound() => playSound('scrape');
  void playBrakeSound() => playSound('brake');
  void playPickupSound() => playSound('pickup');
  void playDropoffSound() => playSound('dropoff');
  void playCoinSound() => playSound('coin');
  void playButtonSound() => playSound('button_click');
  void playLevelCompleteSound() => playSound('level_complete');
  void playLevelFailedSound() => playSound('level_failed');
  void playBankedJingle() => playSound('banked');
}

/// One sound's voice pool: the players ready to replay, how many more are
/// still being created, and a round-robin cursor for when all are busy.
class _Voices {
  final List<AudioPlayer> ready = <AudioPlayer>[];
  int creating = 0;
  int next = 0;
}

/// Best-effort read of the [AudioService] above [context]: null when no
/// provider is there (headless widget tests, the screenshot entry point).
/// UI sounds are dressing — a missing provider must never break a button.
AudioService? audioOf(BuildContext context) {
  try {
    return context.read<AudioService>();
  } on ProviderNotFoundException {
    return null;
  }
}
