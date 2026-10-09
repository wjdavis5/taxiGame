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
///
/// Issue #49 needs more than "it worked": a real device answers slowly, so
/// [latency] delays the calls that are slow on iOS (`create`, loading a
/// source, `resume`), [failing] makes named calls throw, and every call is
/// recorded so tests can count players created and disposed, volumes sent,
/// and platform traffic.
class FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final Map<String, StreamController<AudioEvent>> _events = {};

  /// Every context handed to [setAudioContext], in order.
  final List<AudioContext> audioContexts = [];

  /// Every platform call, by method name, in order.
  final List<String> calls = [];

  /// Player ids, in the order [create] and [dispose] saw them.
  final List<String> created = [];
  final List<String> disposed = [];

  /// Every volume handed to [setVolume], in order.
  final List<double> volumes = [];

  /// How long `create`, `setSourceUrl` and `resume` take to answer. Zero
  /// answers at once, as the Simulator effectively does.
  Duration latency = Duration.zero;

  /// Method names that throw a [PlatformException] instead of answering.
  final Set<String> failing = {};

  int count(String method) => calls.where((c) => c == method).length;

  StreamController<AudioEvent> _controllerFor(String playerId) =>
      _events.putIfAbsent(playerId, StreamController<AudioEvent>.broadcast);

  Future<void> _call(String method, {bool slow = false}) async {
    calls.add(method);
    if (slow && latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (failing.contains(method)) {
      throw PlatformException(code: method, message: 'simulated failure');
    }
  }

  /// Ends [playerId]'s current playback, as the native player does when a
  /// one-shot reaches its end.
  void complete(String playerId) {
    _controllerFor(playerId)
        .add(const AudioEvent(eventType: AudioEventType.complete));
  }

  @override
  Future<void> create(String playerId) async {
    await _call('create', slow: true);
    created.add(playerId);
  }

  @override
  Future<void> dispose(String playerId) async {
    await _call('dispose');
    disposed.add(playerId);
    final controller = _events.remove(playerId);
    await controller?.close();
  }

  @override
  Future<void> pause(String playerId) => _call('pause');

  @override
  Future<void> stop(String playerId) => _call('stop');

  @override
  Future<void> resume(String playerId) => _call('resume', slow: true);

  @override
  Future<void> release(String playerId) => _call('release');

  @override
  Future<void> seek(String playerId, Duration position) => _call('seek');

  @override
  Future<void> setBalance(String playerId, double balance) =>
      _call('setBalance');

  @override
  Future<void> setVolume(String playerId, double volume) async {
    await _call('setVolume');
    volumes.add(volume);
  }

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) =>
      _call('setReleaseMode');

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) =>
      _call('setPlaybackRate');

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    await _call('setSourceUrl', slow: true);
    _controllerFor(playerId).add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) =>
      _call('setSourceBytes');

  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) {
    audioContexts.add(audioContext);
    return _call('setAudioContext');
  }

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) =>
      _call('setPlayerMode');

  @override
  Future<int?> getDuration(String playerId) async {
    await _call('getDuration');
    return null;
  }

  @override
  Future<int?> getCurrentPosition(String playerId) async {
    await _call('getCurrentPosition');
    return null;
  }

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

  /// Every [setGlobalAudioContext] invocation, successful or not —
  /// includes held and failed attempts, so retry counts are observable.
  int attempts = 0;

  /// When true, [setGlobalAudioContext] throws — simulating a session the
  /// OS refuses to configure.
  bool failSetGlobalAudioContext = false;

  /// While set, [setGlobalAudioContext] waits for it: a session that is
  /// slow to configure (issue #49: nothing may play before it lands).
  Completer<void>? hold;

  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {
    attempts++;
    await hold?.future;
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
