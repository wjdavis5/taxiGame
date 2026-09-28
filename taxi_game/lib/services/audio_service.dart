import 'dart:async' show unawaited;

import 'package:flame_audio/flame_audio.dart';
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

  bool _soundEnabled = true;
  bool _musicEnabled = true;

  /// Music state: the app wants one track playing whenever music is enabled
  /// ([playMusic] declares the want; the settings toggle gates it).
  bool _musicWanted = false;

  /// Engine loop state. The running *want* is re-asserted every frame by the
  /// game, so pause, crash stalls, and lifecycle changes only ever flip the
  /// want off — the next live frame brings the engine back.
  AudioPlayer? _enginePlayer;
  bool _engineWanted = false;
  double _engineIntensity = 0;
  bool _suspended = false;

  /// Guards the async engine start against rapid toggles: a superseded
  /// start disposes its player instead of adopting it.
  int _engineGeneration = 0;

  /// The sounds playback was attempted for, since construction (issue #4).
  /// Gated calls never register — tests assert against this to check the
  /// enabled-gates without a platform plugin.
  @visibleForTesting
  final Map<String, int> attemptedPlays = <String, int>{};

  /// Initializes the BGM lifecycle handler (auto pause/resume around app
  /// backgrounding) and warms the sound cache. Safe to call twice; safe when
  /// no plugin exists (tests) — everything below swallows its failures.
  Future<void> initialize() async {
    try {
      await FlameAudio.bgm.initialize();
    } catch (_) {}
    try {
      await FlameAudio.audioCache.loadAll(soundFiles.values.toList());
    } catch (_) {}
  }

  /// True when music should currently be audible.
  @visibleForTesting
  bool get isMusicWanted => _musicWanted && _musicEnabled && !_suspended;

  /// Whether the engine loop player currently exists (test observability —
  /// there is nothing audible to assert against under flutter test).
  @visibleForTesting
  bool get isEngineLoopActive => _enginePlayer != null;

  // --- one-shot sounds ------------------------------------------------------

  /// Plays the one-shot named [soundName] (see [_soundFiles]). Unknown names
  /// are ignored rather than guessed at. Fire and forget.
  void playSound(String soundName, {double? volume}) {
    if (!_soundEnabled) return;
    final file = soundFiles[soundName];
    if (file == null) return;
    attemptedPlays.update(soundName, (n) => n + 1, ifAbsent: () => 1);
    unawaited(() async {
      try {
        await FlameAudio.play(
          file,
          volume: volume ?? _defaultVolumes[soundName] ?? 1.0,
        );
      } catch (_) {}
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
  /// road). Idempotent; safe from every frame.
  void setEngineRunning(bool running) {
    _engineWanted = running;
    _syncEngine();
  }

  /// Speed 0..1 — scales the engine from idle to revved. Cheap enough to
  /// call every frame; only touches the player's volume.
  void setEngineIntensity(double intensity) {
    _engineIntensity = intensity.clamp(0.0, 1.0);
    _applyEngineVolume();
  }

  /// Idle hum under a stopped taxi, up to a full rev.
  double get _engineVolume => 0.22 + 0.68 * _engineIntensity;

  void _applyEngineVolume() {
    final player = _enginePlayer;
    if (player == null) return;
    unawaited(() async {
      try {
        await player.setVolume(_engineVolume);
      } catch (_) {}
    }());
  }

  void _syncEngine() {
    final gen = ++_engineGeneration;
    final want = _engineWanted && _soundEnabled && !_suspended;
    if (want) {
      if (_enginePlayer != null) {
        _applyEngineVolume();
        return;
      }
      unawaited(() async {
        AudioPlayer? player;
        try {
          player = await FlameAudio.loop(engineLoop, volume: _engineVolume);
        } catch (_) {
          return;
        }
        if (gen != _engineGeneration) {
          // Superseded while starting: never adopt, never leak.
          try {
            await player.stop();
            await player.dispose();
          } catch (_) {}
          return;
        }
        _enginePlayer = player;
      }());
    } else {
      final player = _enginePlayer;
      _enginePlayer = null;
      if (player != null) {
        unawaited(() async {
          try {
            await player.stop();
            await player.dispose();
          } catch (_) {}
        }());
      }
    }
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

  /// Releases the engine player and the BGM observer. The service is an
  /// app-lifetime singleton; this exists for tests and hot restarts.
  Future<void> dispose() async {
    _engineGeneration++;
    final player = _enginePlayer;
    _enginePlayer = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {}
    }
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
