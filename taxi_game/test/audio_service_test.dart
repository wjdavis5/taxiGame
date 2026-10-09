import 'dart:async' show Completer, unawaited;
import 'dart:io' show Directory, File;

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart'
    show AVAudioSessionCategory;
import 'package:flame_audio/flame_audio.dart' show FlameAudio, PlayerState;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart'
    show AssetManifest, MethodCall, StandardMethodCodec, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/diagnostics.dart';
import 'package:taxi_game/services/share_service.dart';

import 'helpers/fake_audio_platform.dart';

/// Tests for the audio service (issue #4).
///
/// The audioplayers platform is faked, so every platform call the service
/// makes completes harmlessly here exactly as it does on device — and the
/// service's own state machine (gates, music want, engine loop adoption) is
/// observable without hearing anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioPlatform fake;
  setUp(() {
    fake = installFakeAudioPlatform();
  });


  /// Lets the fire-and-forget platform chains finish. They hop through real
  /// event-loop turns — asset loads and cache file writes among them — so a
  /// microtask drain is not enough; short real delays are.
  Future<void> settle() async {
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  /// Waits until [condition] holds, failing after 5 s. The engine-loop
  /// chains are fire-and-forget through real asset loads, so the number of
  /// event-loop turns varies with machine load — a fixed drain (settle)
  /// passed locally but raced on loaded CI runners (run 36451103837).
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for the audio stack to settle');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  /// Waits until the fake platform has gone quiet — no new calls across
  /// two consecutive polls — failing loudly after 5 s. This is the
  /// deadline-polling answer for a *negative* assertion, where [until]
  /// cannot work: `fake.player.created` is empty at t=0, so polling
  /// `until(created.isEmpty)` would return before the fire-and-forget
  /// chains have had any chance to show a leak and the test would pass
  /// vacuously every run. Polling the platform's total traffic instead
  /// waits exactly as long as work is still in flight and no longer:
  /// those chains hop through `AudioPlayer._create()` and AudioCache's
  /// real asset loads and temp-file writes, so the event-loop turns they
  /// need vary with machine load — the fixed 50 ms drain ([settle]) this
  /// replaced raced exactly there on loaded full-suite runs, passing in
  /// isolation (issue #69). Once two polls agree that nothing new
  /// landed, whatever the chains were going to do, they have done it.
  Future<void> untilQuiet() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    var lastCount = fake.player.calls.length;
    var quietPolls = 0;
    while (quietPolls < 2) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for the audio platform to go quiet');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final count = fake.player.calls.length;
      quietPolls = count == lastCount ? quietPolls + 1 : 0;
      lastCount = count;
    }
  }

  group('the license inventory (issue #4)', () {
    /// LICENSES.txt is two documents: the inventory proper, and — from
    /// `## Removed assets` on — the record of what was pulled from the
    /// bundle when audio last went away (the CC-BY menu_music.mp3 among
    /// it) plus the maintenance notes. Every check in this group runs
    /// against the shipped half alone: the original name check
    /// substring-matched the whole file, so a re-added menu_music.mp3
    /// was "named" by its own removal entry and passed (issue #190).
    Future<(String, String)> licenseHalves() async {
      final licenses = await rootBundle.loadString(
        'assets/licenses/LICENSES.txt',
      );
      const marker = '## Removed assets';
      final splitAt = licenses.indexOf(marker);
      expect(splitAt, greaterThanOrEqualTo(0),
          reason: 'the inventory must keep its Removed assets section — '
              'the checks here split the file there to tell claims about '
              'the bundle apart from history');
      return (licenses.substring(0, splitAt), licenses.substring(splitAt));
    }

    /// Every filename-shaped token in [text]. Names are matched on those
    /// token boundaries, never as bare substrings: `scrape.wav` would be
    /// a substring of a hypothetical `disc_scrape.wav`, and a plain
    /// `contains` would credit the inventory with a name it never wrote.
    Set<String> filenameTokens(String text) =>
        RegExp(r'[A-Za-z0-9_.-]+').allMatches(text).map((m) => m[0]!).toSet();

    test('names every shipped audio file, and none of the removed ones',
        () async {
      final (shippedHalf, removedHalf) = await licenseHalves();

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      // Every extension, not a .wav filter — the count check this group
      // used to have filtered .wav before asserting 12, so a re-added
      // .mp3 slipped past it unseen (issue #190).
      final shipped = manifest
          .listAssets()
          .where((path) => path.startsWith('assets/audio/'))
          .toSet();
      expect(shipped, isNotEmpty,
          reason: 'the audio bundle must not silently go empty');

      final inventoryNames = filenameTokens(shippedHalf);
      final removedNames = filenameTokens(removedHalf);
      for (final asset in shipped) {
        final name = asset.split('/').last;
        expect(inventoryNames.contains(name), isTrue,
            reason: '$asset ships but the license inventory never names it');
        expect(removedNames.contains(name), isFalse,
            reason: '$asset ships but is also named at or after the '
                'Removed assets marker — that section must only ever name '
                'files that stay out of the bundle');
      }
    });

    test('names exactly the files the bundle ships — no more, no fewer',
        () async {
      final (shippedHalf, _) = await licenseHalves();

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final onDisk = manifest
          .listAssets()
          .where((path) => path.startsWith('assets/audio/'))
          .map((path) => path.split('/').last)
          .toSet();

      // The inventory writes shipped names two ways: as full
      // `assets/audio/…` paths (the generated files) and as the
      // right-hand `→ shipped.ext` column of the Kenney conversion
      // table. The dot requirement keeps the parenthetical "(original
      // pack file → shipped as)" out of the parse. Set equality catches
      // both directions the old hasLength(12)-on-.wav could not: a file
      // that ships unnamed, and a name that ships no file.
      final named = <String>{
        ...RegExp(r'assets/audio/[\w/]+\.\w+')
            .allMatches(shippedHalf)
            .map((m) => m[0]!.split('/').last),
        ...RegExp(r'→\s*([\w-]+\.[\w-]+)')
            .allMatches(shippedHalf)
            .map((m) => m[1]!),
      };

      expect(onDisk, equals(named),
          reason: 'the bundle and the license inventory must name the same '
              'audio files: anything on disk but unnamed ships uncredited, '
              'and anything named but not on disk is the inventory lying '
              'about the bundle');
    });
  });

  group('one-shot sounds', () {
    test('play when sound is enabled, and the attempt is recorded', () {
      final audio = AudioService();

      audio.playCrashSound();
      expect(audio.attemptedPlays['crash'], 1);

      audio.playSound('pickup');
      expect(audio.attemptedPlays['pickup'], 1);
    });

    test('are gated behind the sound setting', () {
      final audio = AudioService()..setSoundEnabled(false);

      audio.playCrashSound();
      audio.playButtonSound();
      expect(audio.attemptedPlays, isEmpty,
          reason: 'a muted game must not even reach for the player');
    });

    test('with unknown names are ignored rather than guessed at', () {
      final audio = AudioService()..playSound('nonexistent_sound');
      expect(audio.attemptedPlays, isEmpty);
    });

    test('count repeated plays per sound', () {
      final audio = AudioService();
      audio
        ..playCoinSound()
        ..playCoinSound()
        ..playCoinSound();
      expect(audio.attemptedPlays['coin'], 3);
    });
  });

  group('music', () {
    test('the want starts with playMusic and stops with stopMusic',
        () async {
      final audio = AudioService();

      expect(audio.isMusicWanted, isFalse);
      await audio.playMusic();
      expect(audio.isMusicWanted, isTrue);

      await audio.stopMusic();
      expect(audio.isMusicWanted, isFalse,
          reason: 'stopMusic is the deliberate off — no restart from it');
    });

    test('the music setting gates playback but keeps the want', () async {
      final audio = AudioService();
      await audio.playMusic();
      expect(audio.isMusicWanted, isTrue);

      await audio.setMusicEnabled(false);
      expect(audio.isMusicWanted, isFalse);

      // Re-enabling restarts the wanted track — this is the settings
      // toggle's path through the composition root's listener.
      await audio.setMusicEnabled(true);
      expect(audio.isMusicWanted, isTrue);
    });

    test('a service started with music off never wants music on its own',
        () async {
      final audio = AudioService()..setMusicEnabled(false);

      await audio.playMusic();
      expect(audio.isMusicWanted, isFalse);
    });

    test('a start that outlasts the switch going off is stopped (issue #178)',
        () async {
      // The launch-time start and a quick settings flick race exactly
      // like this: `playMusic` is left unawaited, the Music switch goes
      // off while the start is still climbing `Bgm.play`'s five-step
      // chain (release, release mode, volume, source, resume — and only
      // then does the chain flip its own `isPlaying`), and the chain's
      // tail used to finish the start *after* the stop with nothing left
      // to re-check the setting: music played with the switch off. The
      // fake's latency makes source and resume slow, so the off lands
      // deterministically mid-chain while the start is still ≥ 100 ms
      // from finishing.
      fake.player.latency = const Duration(milliseconds: 50);
      final audio = AudioService();

      final starting = audio.playMusic();
      await audio.setMusicEnabled(false);
      await starting;

      expect(FlameAudio.bgm.isPlaying, isFalse,
          reason: 'the start landed after the stop — the setting must '
              'win, or the switch lies');
    });

    test('a start that outlasts a backgrounding pauses, not stops (#178)',
        () async {
      // The same race through [pauseAll] instead of the switch: the
      // reconcile must mirror what landed — a pause (which keeps the
      // track loaded for resumeAll to bring back if still wanted), not a
      // stop (which throws the source away).
      fake.player.latency = const Duration(milliseconds: 50);
      final audio = AudioService();

      final starting = audio.playMusic();
      await audio.pauseAll();
      await starting;

      expect(FlameAudio.bgm.isPlaying, isFalse);
      expect(FlameAudio.bgm.audioPlayer.state, PlayerState.paused,
          reason: 'the app is backgrounded, not muted — resumeAll must be '
              'able to revive the wanted track, and a stop would have '
              'unloaded it');
    });
  });

  group('one-shot voices (issue #49)', () {
    test('a replay restarts an existing voice instead of making a player',
        () async {
      final audio = AudioService()..playCoinSound();
      await until(() => fake.player.count('resume') == 1);

      // The first coin is still ringing (the fake never finishes it), so
      // the second grows the pool to its second voice.
      audio.playCoinSound();
      await until(() => fake.player.count('resume') == 2);

      // The pool is full: the third coin restarts a voice.
      audio.playCoinSound();
      await until(() => fake.player.count('resume') == 3);

      expect(fake.player.created, hasLength(2));
      expect(fake.player.count('stop'), 1,
          reason: 'the restarted voice is stopped back to its top first');
      expect(fake.player.disposed, isEmpty);
      await audio.dispose();
    });

    test('a finished voice is reused before the pool grows', () async {
      final audio = AudioService()..playCoinSound();
      await until(() => fake.player.count('resume') == 1);

      fake.player.complete(fake.player.created.single);
      await settle();
      audio.playCoinSound();
      await until(() => fake.player.count('resume') == 2);

      expect(fake.player.created, hasLength(1));
      await audio.dispose();
    });

    test('a long shift of one-shots never grows past the fixed pool',
        () async {
      final audio = AudioService();
      for (var round = 0; round < 10; round++) {
        for (final name in AudioService.soundFiles.keys) {
          audio.playSound(name);
        }
        await settle();
      }

      expect(fake.player.created.length,
          lessThanOrEqualTo(2 * AudioService.soundFiles.length),
          reason: 'each sound owns at most two voices; the old path made a '
              'new native player for every play and never disposed it');
      expect(fake.player.disposed, isEmpty);
      expect(fake.player.count('getCurrentPosition'), 0,
          reason: 'nothing reads position, so no player may poll for it '
              'every frame');
      await audio.dispose();
      expect(fake.player.disposed, unorderedEquals(fake.player.created),
          reason: 'dispose releases every voice');
    });
  });

  group('sound-off and pauseAll govern one-shot voices (issue #219)', () {
    test('a mute landing mid-creation stops the in-flight one-shot',
        () async {
      // The first play of a sound creates its player asynchronously — on
      // a device tens of milliseconds. The switch used to be read once,
      // at admission, so a mute landing inside that window still heard
      // the sound start.
      fake.player.latency = const Duration(milliseconds: 50);
      final audio = AudioService();

      audio.playCoinSound();
      audio.setSoundEnabled(false);

      // The voice being created is dropped: it never resumes, and its
      // half-made player is disposed rather than left for a sound nobody
      // asked to hear.
      await until(() => fake.player.count('dispose') == 1);
      expect(fake.player.count('resume'), 0,
          reason: 'the voice must not start after the mute');
      await audio.dispose();
    });

    test('a backgrounding landing mid-creation drops the in-flight one-shot',
        () async {
      // The same window as the mute case, with the lifecycle instead of
      // the switch: pauseAll promises silence from the moment the app
      // leaves the foreground, so a voice still being created must not
      // start behind the pause when its player lands.
      fake.player.latency = const Duration(milliseconds: 50);
      final audio = AudioService();

      audio.playCoinSound();
      await audio.pauseAll();

      await until(() => fake.player.count('dispose') == 1);
      expect(fake.player.count('resume'), 0,
          reason: 'the voice must not start behind the pause');
      await audio.resumeAll();
      await audio.dispose();
    });

    test('turning sound off stops a ready voice', () async {
      final audio = AudioService()..playCoinSound();
      await until(() => fake.player.count('resume') == 1);

      audio.setSoundEnabled(false);
      await until(() => fake.player.count('stop') == 1);

      expect(fake.player.created, hasLength(1));
      await audio.dispose();
    });

    test('pauseAll stops a ready voice', () async {
      final audio = AudioService()..playLevelCompleteSound();
      await until(() => fake.player.count('resume') == 1);

      await audio.pauseAll();
      await until(() => fake.player.count('stop') == 1);

      await audio.resumeAll();
      await audio.dispose();
    });
  });

  group('the engine loop on a slow device (issue #49)', () {
    /// One game frame: the two calls TaxiGame.update makes every frame,
    /// then a real gap so the slow fake platform can make progress.
    Future<void> frame(AudioService audio) async {
      audio
        ..setEngineRunning(true)
        ..setEngineIntensity(0.5);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    test('a start that outlasts many frames creates exactly one player',
        () async {
      // Each slow call takes 100 ms, so the start spans dozens of frames,
      // as it does on an iPhone and never in the Simulator.
      fake.player.latency = const Duration(milliseconds: 100);
      final audio = AudioService();

      for (var i = 0; i < 5; i++) {
        await frame(audio);
      }
      expect(audio.isEngineLoopActive, isFalse,
          reason: 'the start must still be pending for this test to mean '
              'anything');
      while (!audio.isEngineLoopActive) {
        await frame(audio);
      }
      for (var i = 0; i < 20; i++) {
        await frame(audio);
      }

      expect(fake.player.created, hasLength(1),
          reason: 'the old code started a new player on every frame of the '
              'wait and adopted none of them: ~120 AVPlayers a second on a '
              'ProMotion iPhone, until the watchdog killed the app');
      expect(fake.player.disposed, isEmpty);
      await audio.dispose();
    });

    test('the per-frame steady state makes no platform calls', () async {
      final audio = AudioService()
        ..setEngineIntensity(0.5)
        ..setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      await settle();

      final before = fake.player.calls.length;
      for (var i = 0; i < 120; i++) {
        audio
          ..setEngineRunning(true)
          ..setEngineIntensity(0.5);
      }
      await settle();

      expect(fake.player.calls.sublist(before), isEmpty);
      await audio.dispose();
    });

    test('intensity reaches the platform only in whole volume steps',
        () async {
      final audio = AudioService()..setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      await settle();

      final before = fake.player.volumes.length;
      for (var i = 0; i <= 1000; i++) {
        audio.setEngineIntensity(i / 1000);
      }
      await settle();

      final sent = fake.player.volumes.sublist(before);
      expect(sent.length, lessThanOrEqualTo(34),
          reason: 'idle 0.22 to full 0.90 is 34 steps of 0.02, not 1000 '
              'frame-rate setVolume calls');
      expect(sent.last, closeTo(0.90, 1e-9));
      await audio.dispose();
    });

    test('hit-stops pause and resume the one player, never re-create it',
        () async {
      final audio = AudioService()..setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);

      for (var i = 0; i < 50; i++) {
        audio.setEngineRunning(false);
        expect(audio.isEngineLoopActive, isFalse);
        audio.setEngineRunning(true);
        expect(audio.isEngineLoopActive, isTrue);
      }
      await settle();

      expect(fake.player.created, hasLength(1));
      expect(fake.player.disposed, isEmpty);
      await audio.dispose();
    });

    test('a start that lands after the want is gone stays paused',
        () async {
      fake.player.latency = const Duration(milliseconds: 50);
      final audio = AudioService()..setEngineRunning(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      audio.setEngineRunning(false);

      await until(() => fake.player.created.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(audio.isEngineLoopActive, isFalse);
      expect(fake.player.count('resume'), 0,
          reason: 'the loop is adopted paused and only resumed when wanted');

      audio.setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      expect(fake.player.created, hasLength(1));
      await audio.dispose();
    });

    test('a failed start disposes its player and backs off', () async {
      fake.player.failing.add('setReleaseMode');
      final audio = AudioService();

      for (var i = 0; i < 50; i++) {
        await frame(audio);
      }
      await until(() => fake.player.disposed.isNotEmpty);

      expect(fake.player.created, hasLength(1),
          reason: 'one attempt, then a backoff — not one attempt per frame');
      expect(fake.player.disposed, fake.player.created,
          reason: 'a half-made player must not leak');
      expect(audio.isEngineLoopActive, isFalse);
      await audio.dispose();
    });
  });

  group('the engine loop', () {
    test('runs while wanted and falls silent when stopped', () async {
      final audio = AudioService();

      audio.setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isTrue);

      audio.setEngineRunning(false);
      await until(() => !audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isFalse);
    });

    test('revives straight back when sound returns mid-shift', () async {
      final audio = AudioService()..setSoundEnabled(false);

      // A live shift asserts the running want every frame, muted or not.
      audio.setEngineRunning(true);
      await until(() => !audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isFalse);

      // Unmuting through settings must not wait for anything: the shift is
      // live, the want is live, so the engine comes straight back.
      audio.setSoundEnabled(true);
      await until(() => audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isTrue);
    });

    test('survives intensity changes at any moment', () async {
      final audio = AudioService()..setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isTrue);

      audio
        ..setEngineIntensity(0)
        ..setEngineIntensity(0.5)
        ..setEngineIntensity(1)
        ..setEngineIntensity(42);
      await until(() => audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isTrue);
    });
  });

  group('app lifecycle', () {
    test('pauseAll suspends everything and resumeAll restores the wants',
        () async {
      final audio = AudioService();
      await audio.playMusic();
      audio.setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isTrue);
      expect(audio.isMusicWanted, isTrue);

      await audio.pauseAll();
      expect(audio.isMusicWanted, isFalse);
      await until(() => !audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isFalse);

      await audio.resumeAll();
      expect(audio.isMusicWanted, isTrue);
      // The engine comes back only through the running flag — the game's
      // update loop re-asserts it when the app is truly live again.
      await until(() => !audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isFalse);
      audio.setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      expect(audio.isEngineLoopActive, isTrue);
    });
  });

  group('the iOS audio session (issue #39)', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('initialize configures an ambient session on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await AudioService().initialize();

      expect(fake.global.contexts, hasLength(1),
          reason: 'the session is claimed exactly once, at startup');
      final context = fake.global.contexts.single;
      expect(context.iOS.category, AVAudioSessionCategory.ambient,
          reason: 'ambient mixes with whatever the player was listening to '
              'and obeys the Ring/Silent switch');
      expect(context.iOS.options, isEmpty,
          reason: 'ambient mixes by definition — an explicit mixWithOthers '
              'is illegal on this category in audioplayers and would throw '
              'in debug builds');
    });

    test('playback never re-applies the session per player (issue #49)',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final audio = AudioService();

      audio.playCoinSound();
      audio.setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      await settle();
      await audio.dispose();

      expect(fake.player.created, isNotEmpty);
      expect(fake.player.audioContexts, isEmpty,
          reason: 'on iOS a player-level context IS the global session — '
              'audioplayers answers it with setCategory + setActive on the '
              'main thread. initialize claims ambient once; re-applying it '
              'per play cost main-thread time, and flame_audio\'s own '
              'helpers would have applied .playback, silencing the '
              'Ring/Silent switch (issue #39)');
    });

    test('nothing plays before the ambient session lands', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final hold = fake.global.hold = Completer<void>();
      final audio = AudioService();

      final initializing = audio.initialize();
      audio.playCoinSound();
      audio.setEngineRunning(true);
      await untilQuiet();
      expect(fake.player.created, isEmpty,
          reason: 'a player that started under the plugin\'s launch-time '
              '.playback session would stop the player\'s own music');

      hold.complete();
      await initializing;
      await until(() => audio.isEngineLoopActive);
      expect(fake.global.contexts.single.iOS.category,
          AVAudioSessionCategory.ambient);
      await audio.dispose();
    });

    test('the seeded sound flag governs the launch window: a muted menu '
        'tap before the un-awaited start-up lands stays silent (issue #207)',
        () async {
      // The bug's window: main() starts audio without awaiting it, and
      // the save's settings reached the service only inside that chain's
      // applySettings — so a menu tap in the first moments after launch
      // found the sound flag's `true` default and clicked with Sound
      // turned off. main() now seeds the flag at construction (the
      // haptics pattern); this test replays exactly that shape with the
      // hold above keeping initialize() parked mid-flight. It lives in
      // this group — after the music group — deliberately: dispose()
      // tears down the global FlameAudio.bgm player, and the #178 tests
      // read that player's state, so any initialize()+dispose() test
      // must run after them.
      final hold = fake.global.hold = Completer<void>();

      final audio = AudioService()..setSoundEnabled(false);
      final initializing = audio.initialize();

      // The menu-tap window: sound is off, the start-up chain is still
      // held mid-flight, and the tap must not even reach for a player.
      // attemptedPlays registers before any player is waited on, so an
      // unseeded flag shows up here immediately — the click the issue
      // heard.
      audio.playButtonSound();
      await untilQuiet();
      expect(audio.attemptedPlays, isEmpty,
          reason: 'a muted game must stay muted through launch: the '
              'seed, not the start-up chain, owns the first frame');

      hold.complete();
      await initializing;
      await audio.dispose();
    });

    test('off iOS the session is left entirely alone', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final audio = AudioService();

      await audio.initialize();
      audio.playCoinSound();
      await settle();
      await audio.dispose();

      expect(fake.global.contexts, isEmpty,
          reason: 'Android mixes by default — no session counterpart');
      expect(fake.player.audioContexts, isNotEmpty);
      expect(
        fake.player.audioContexts.map((c) => c.iOS.category),
        everyElement(AVAudioSessionCategory.playback),
        reason: 'off iOS each player gets flame_audio\'s own mix-with-'
            'others default once, at creation — exactly as shipped before '
            '#39',
      );
    });

    test('a context failure neither crashes nor blocks initialize', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      fake.global.failSetGlobalAudioContext = true;

      // Completing at all is the assertion: the failure is logged and the
      // rest of startup (BGM init, cache warm) runs.
      await AudioService().initialize();
      expect(fake.global.contexts, isEmpty);
    });

    test('a failed session claim is logged and retried on the next play '
        '(issue #234)', () async {
      // On iOS this call is the only place the ambient session is claimed
      // — per-player contexts are null there (issue #49) — so a refused
      // activation must not leave the plugin's `.playback` default
      // standing without a trace or a second chance.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      fake.global.failSetGlobalAudioContext = true;
      Diagnostics.instance.resetForTest();
      addTearDown(Diagnostics.instance.resetForTest);

      final audio = AudioService();
      await audio.initialize();
      expect(Diagnostics.instance.export(),
          contains('[error:audio_session]'),
          reason: 'the refusal is recorded, not swallowed');
      expect(fake.global.contexts, isEmpty);

      // The next play spends the one retry, and the session lands.
      fake.global.failSetGlobalAudioContext = false;
      audio.playCoinSound();
      await until(() => fake.global.contexts.isNotEmpty);
      expect(fake.global.contexts.single.iOS.category,
          AVAudioSessionCategory.ambient);
      await audio.dispose();
    });

    test('the session retry is spent once, not once per play (issue #234)',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      fake.global.failSetGlobalAudioContext = true;
      Diagnostics.instance.resetForTest();
      addTearDown(Diagnostics.instance.resetForTest);

      final audio = AudioService();
      await audio.initialize();
      audio.playCoinSound();
      await until(() => fake.global.attempts == 2);
      await settle();

      // The retry failed too: it is spent. Later plays must not hammer a
      // session the OS keeps refusing.
      audio.playCoinSound();
      await audio.playMusic();
      await settle();
      expect(fake.global.attempts, 2,
          reason: 'one initial attempt plus exactly one retry');
      await audio.dispose();
    });

    test('the BGM start waits for the retry the next play spends (issue #234)',
        () async {
      // playMusic spent the armed session retry but did not wait for it:
      // `bgm.play` began while the ambient session was still being
      // claimed, under the plugin's launch-time `.playback` default. The
      // one-shot players wait on `_sessionReady`; the music must too.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      fake.global.failSetGlobalAudioContext = true;
      Diagnostics.instance.resetForTest();
      addTearDown(Diagnostics.instance.resetForTest);

      final audio = AudioService();
      await audio.initialize(); // the claim fails; the one retry is armed
      expect(fake.global.contexts, isEmpty);

      // The retry will succeed, but only when the test lets it: held, it
      // keeps the claim in flight while playMusic runs.
      fake.global.failSetGlobalAudioContext = false;
      final hold = fake.global.hold = Completer<void>();
      var finished = false;
      final starting = audio.playMusic();
      unawaited(starting.whenComplete(() => finished = true));
      await until(() => fake.global.attempts == 2);
      await settle();

      // The claim is still in flight: the start must still be waiting on
      // it, not running `bgm.play` under the plugin's launch-time
      // `.playback` default behind the retry.
      expect(finished, isFalse,
          reason: 'the BGM start must wait for the session claim');

      hold.complete();
      await starting;

      expect(fake.global.contexts, hasLength(1));
      expect(fake.global.contexts.single.iOS.category,
          AVAudioSessionCategory.ambient);
      expect(finished, isTrue,
          reason: 'the start completes once the session has landed');
      await audio.dispose();
    });
  });

  test('initialize is safe to call twice', () async {
    final audio = AudioService();
    await audio.initialize();
    await audio.initialize();
  });

  group('the asset cache folder (issue #198)', () {
    /// The UUID-v4 shape audioplayers mints per AudioCache construction
    /// — duplicated here (not imported) because the service's own copy
    /// is the private half of the sweep's contract.
    final uuidShape = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );

    test('initialize pins the cache id to one fixed, non-UUID name',
        () async {
      await AudioService().initialize();

      // The one assignment every load reads at copy time — the warm, the
      // voice and engine players, the BGM, all through this shared
      // AudioCache instance. Pinned, every launch overwrites one folder
      // instead of minting a UUID-named ~1 MB one apiece that nothing
      // ever deleted.
      expect(FlameAudio.audioCache.cacheId, AudioService.audioCacheId);
      // And the pinned name must not be UUID-shaped: the backlog sweep
      // hunts exactly that shape, and it may never be able to take the
      // live folder.
      expect(uuidShape.hasMatch(AudioService.audioCacheId), isFalse,
          reason: 'a UUID-shaped pinned name would feed the live cache '
              'folder to the sweep');
    });

    test('the sweep deletes minted audio cache folders and spares the rest',
        () async {
      // A real slice of the temp directory, planted with every kind of
      // neighbor the sweep can meet — no path_provider fake needed, the
      // helper takes the directory.
      final temp = await Directory.systemTemp.createTemp('sweep_198');
      addTearDown(() async {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      });

      // Two minted folders, both shapes AudioCache writes: wavs nested
      // under the asset prefix (sfx/…, music/…) and a flat file.
      final nested = Directory(
        '${temp.path}/1c0b5e2a-3d4f-4b5a-9c8d-0a1b2c3d4e5f',
      )..createSync(recursive: true);
      Directory('${nested.path}/sfx').createSync(recursive: true);
      File('${nested.path}/sfx/coin.wav').writeAsBytesSync([1]);
      final flat = Directory(
        '${temp.path}/9f8e7d6c-5b4a-4938-8271-112233445566',
      )..createSync(recursive: true);
      File('${flat.path}/engine_loop.wav').writeAsBytesSync([1]);

      // The neighbors that must survive: the share sheet's folder
      // (AppDelegate prunes its own), a UUID-named folder holding no
      // wav, the pinned live cache folder — with wavs in it, proving
      // sparing is by name, not by content — a non-UUID folder with
      // wavs, and a loose file.
      final cards = Directory('${temp.path}/score_cards')
        ..createSync(recursive: true);
      File('${cards.path}/cab-hustle-score-1.png').writeAsBytesSync([1]);
      final uuidNoWav = Directory(
        '${temp.path}/abcdef01-2345-4789-8abc-def012345678',
      )..createSync(recursive: true);
      File('${uuidNoWav.path}/note.txt').writeAsStringSync('not audio');
      final live = Directory('${temp.path}/${AudioService.audioCacheId}')
        ..createSync(recursive: true);
      Directory('${live.path}/music').createSync(recursive: true);
      File('${live.path}/music/shift_loop.wav').writeAsBytesSync([1]);
      final named = Directory('${temp.path}/some_other_folder')
        ..createSync(recursive: true);
      File('${named.path}/x.wav').writeAsBytesSync([1]);
      final loose = File('${temp.path}/loose.wav')..writeAsBytesSync([1]);

      await AudioService.sweepAbandonedAudioCaches(temp);

      expect(nested.existsSync(), isFalse,
          reason: 'a minted folder with prefix-nested wavs is the exact '
              'backlog the issue names');
      expect(flat.existsSync(), isFalse,
          reason: 'a minted folder with a flat wav too');
      expect(cards.existsSync(), isTrue,
          reason: 'the share sheet prunes score_cards itself');
      expect(uuidNoWav.existsSync(), isTrue,
          reason: 'UUID-named but holding no audio — not this service\'s '
              'to judge');
      expect(live.existsSync(), isTrue,
          reason: 'the pinned folder is this launch\'s cache, wavs and all');
      expect(named.existsSync(), isTrue,
          reason: 'a non-UUID folder is never a minted cache, wavs or not');
      expect(loose.existsSync(), isTrue,
          reason: 'the sweep walks folders only, never loose files');
    });

    test('the sweep tolerates a missing temp directory', () async {
      // Completing at all is the assertion — the class convention: a
      // sweep that cannot run costs some disk, never a launch.
      await AudioService.sweepAbandonedAudioCaches(
        Directory('${Directory.systemTemp.path}/sweep_198_not_here'),
      );
    });
  });

  group('system audio events (issue #236)', () {
    // The iOS audio session exists only in native code: AppDelegate
    // observes AVAudioSession interruptions and route changes and sends
    // systemAudioPaused/systemAudioResumed over the share channel. These
    // tests replay both the handler and the channel route.
    test('a system pause suspends the engine and music; a resume restores '
        'the wants', () async {
      final audio = AudioService();
      await audio.playMusic();
      audio.setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);

      await audio.handleSystemAudioPaused();

      expect(audio.isEngineLoopActive, isFalse,
          reason: 'the OS owns the session; the loop must go quiet');
      expect(audio.isMusicWanted, isFalse);

      await audio.handleSystemAudioResumed();

      expect(audio.isMusicWanted, isTrue);
      // The engine comes back only through the game's per-frame want, the
      // same re-entry backgrounding uses.
      audio.setEngineRunning(true);
      await until(() => audio.isEngineLoopActive);
      await audio.dispose();
    });

    test('native messages ride the share channel to the service', () async {
      final audio = AudioService();
      await audio.initialize();
      await audio.playMusic();
      expect(audio.isMusicWanted, isTrue);

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();

      await messenger.handlePlatformMessage(
        ShareService.channel.name,
        codec.encodeMethodCall(const MethodCall('systemAudioPaused')),
        null,
      );
      expect(audio.isMusicWanted, isFalse,
          reason: 'the native pause event reached the running service');

      await messenger.handlePlatformMessage(
        ShareService.channel.name,
        codec.encodeMethodCall(const MethodCall('systemAudioResumed')),
        null,
      );
      expect(audio.isMusicWanted, isTrue,
          reason: 'and so did the resume');

      await audio.dispose();
    });
  });
}
