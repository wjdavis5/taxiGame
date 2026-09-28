import 'dart:async';
import 'dart:io';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Installs a hermetic audio stack for widget tests that pump live screens
/// (issue #4): the audio service runs for real, and every platform call it
/// makes completes harmlessly instead of hitting missing plugins.
///
/// Call from a test's `setUp` — it registers its own teardown. The returned
/// handle exposes the recording fakes, for tests that must assert on what
/// the audio stack actually received (issue #39: the audio session context).
FakeAudioPlatform installFakeAudioPlatform() {
  final handle = FakeAudioPlatform(
    player: FakeAudioplayersPlatform(),
    global: FakeGlobalAudioplayersPlatform(),
  );
  AudioplayersPlatformInterface.instance = handle.player;
  GlobalAudioplayersPlatformInterface.instance = handle.global;

  // AudioCache copies every asset into a temp directory before playing
  // (fetchToMemory), through path_provider — which has no test
  // implementation. Point it at a throwaway directory for the test.
  late Directory tempDir;
  tempDir = Directory.systemTemp.createTempSync('cab_hustle_audio_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  return handle;
}

/// The installed fakes, for tests that assert on received calls.
class FakeAudioPlatform {
  FakeAudioPlatform({required this.player, required this.global});

  /// The per-player fake.
  final FakeAudioplayersPlatform player;

  /// The global-scope fake — where the audio session context lands.
  final FakeGlobalAudioplayersPlatform global;
}

/// A no-op audioplayers platform: every call succeeds, and setting a source
/// reports the source as prepared (the real platform emits that event once
/// the native player has buffered; without it `AudioPlayer.play` never
/// returns). Player-level `setAudioContext` calls are recorded (issue #39).
class FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _events = {};

  /// Every context handed to [setAudioContext], in order.
  final List<AudioContext> audioContexts = [];

  StreamController<AudioEvent> _controllerFor(String playerId) =>
      _events.putIfAbsent(playerId, StreamController<AudioEvent>.broadcast);

  @override
  Future<void> create(String playerId) async {}

  @override
  Future<void> dispose(String playerId) async {
    final controller = _events.remove(playerId);
    await controller?.close();
  }

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    _controllerFor(playerId).add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {}

  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) {
    audioContexts.add(audioContext);
    return Future.value();
  }

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<int?> getDuration(String playerId) async => null;

  @override
  Future<int?> getCurrentPosition(String playerId) async => null;

  @override
  Future<void> emitLog(String playerId, String message) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _controllerFor(playerId).stream;
}

/// The no-op counterpart for the global scope, which the first [AudioPlayer]
/// initializes — and listens to — before it can create anything. Records the
/// audio session contexts it is handed (issue #39) and can be made to fail,
/// proving the service survives a session that will not configure.
class FakeGlobalAudioplayersPlatform
    implements GlobalAudioplayersPlatformInterface {
  /// Every context handed to [setGlobalAudioContext], in order.
  final List<AudioContext> contexts = [];

  /// When true, [setGlobalAudioContext] throws — simulating a session the
  /// OS refuses to configure.
  bool failSetGlobalAudioContext = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {
    if (failSetGlobalAudioContext) {
      throw PlatformException(
        code: 'audio_context',
        message: 'simulated: the session refused to configure',
      );
    }
    contexts.add(ctx);
  }

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
}
