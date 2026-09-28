import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/services/audio_service.dart';

import 'helpers/fake_audio_platform.dart';

/// Tests for the audio service (issue #4).
///
/// The audioplayers platform is faked, so every platform call the service
/// makes completes harmlessly here exactly as it does on device — and the
/// service's own state machine (gates, music want, engine loop adoption) is
/// observable without hearing anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installFakeAudioPlatform);


  /// Lets the fire-and-forget platform chains finish. They hop through real
  /// event-loop turns — asset loads and cache file writes among them — so a
  /// microtask drain is not enough; short real delays are.
  Future<void> settle() async {
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  group('the license inventory (issue #4)', () {
    test('lists every audio file the bundle ships', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final shipped = manifest
          .listAssets()
          .where((path) => path.startsWith('assets/audio/'))
          .toSet();
      expect(shipped, isNotEmpty,
          reason: 'the audio bundle must not silently go empty');

      final licenses = await rootBundle.loadString(
        'assets/licenses/LICENSES.txt',
      );
      for (final asset in shipped) {
        final name = asset.split('/').last;
        expect(licenses.contains(name), isTrue,
            reason: '$asset ships but LICENSES.txt never names it');
      }
    });

    test('covers the two asset folders the pubspec declares', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final shipped = manifest.listAssets().where(
            (path) => path.startsWith('assets/audio/'),
          );
      expect(
        shipped.where((path) => path.endsWith('.wav')),
        hasLength(12),
        reason: 'six Kenney effects, three Kenney jingles, and the three '
            'generated loops (engine, brake, music). If this count changes, '
            'assets/licenses/LICENSES.txt must change with it.',
      );
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
  });

  group('the engine loop', () {
    test('adopts a player while running and releases it when stopped',
        () async {
      final audio = AudioService();

      audio.setEngineRunning(true);
      await settle();
      expect(audio.isEngineLoopActive, isTrue);

      audio.setEngineRunning(false);
      await settle();
      expect(audio.isEngineLoopActive, isFalse);
    });

    test('revives straight back when sound returns mid-shift', () async {
      final audio = AudioService()..setSoundEnabled(false);

      // A live shift asserts the running want every frame, muted or not.
      audio.setEngineRunning(true);
      await settle();
      expect(audio.isEngineLoopActive, isFalse);

      // Unmuting through settings must not wait for anything: the shift is
      // live, the want is live, so the engine comes straight back.
      audio.setSoundEnabled(true);
      await settle();
      expect(audio.isEngineLoopActive, isTrue);
    });

    test('survives intensity changes at any moment', () async {
      final audio = AudioService()..setEngineRunning(true);
      await settle();
      expect(audio.isEngineLoopActive, isTrue);

      audio
        ..setEngineIntensity(0)
        ..setEngineIntensity(0.5)
        ..setEngineIntensity(1)
        ..setEngineIntensity(42);
      await settle();
      expect(audio.isEngineLoopActive, isTrue);
    });
  });

  group('app lifecycle', () {
    test('pauseAll suspends everything and resumeAll restores the wants',
        () async {
      final audio = AudioService();
      await audio.playMusic();
      audio.setEngineRunning(true);
      await settle();
      expect(audio.isEngineLoopActive, isTrue);
      expect(audio.isMusicWanted, isTrue);

      await audio.pauseAll();
      expect(audio.isMusicWanted, isFalse);
      await settle();
      expect(audio.isEngineLoopActive, isFalse);

      await audio.resumeAll();
      expect(audio.isMusicWanted, isTrue);
      // The engine comes back only through the running flag — the game's
      // update loop re-asserts it when the app is truly live again.
      await settle();
      expect(audio.isEngineLoopActive, isFalse);
      audio.setEngineRunning(true);
      await settle();
      expect(audio.isEngineLoopActive, isTrue);
    });
  });

  test('initialize is safe to call twice', () async {
    final audio = AudioService();
    await audio.initialize();
    await audio.initialize();
  });
}
