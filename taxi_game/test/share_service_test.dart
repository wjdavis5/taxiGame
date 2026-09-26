import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/services/share_service.dart';

/// The share hand-off (issue #22): the bytes and the message reach the
/// platform channel intact, and a platform without a native handler is a
/// caught-by-the-caller failure — never a silent success.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final png = Uint8List.fromList(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4]);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ShareService.channel, null);
  });

  test('shareScoreCard invokes the channel with the bytes and the text',
      () async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ShareService.channel, (invoked) async {
      call = invoked;
      return null;
    });

    await const ShareService().shareScoreCard(
      png: png,
      text: 'CAB HUSTLE — DAILY SHIFT: 1234 pts',
    );

    expect(call, isNotNull);
    expect(call!.method, 'shareScoreCard');
    final args = call!.arguments as Map<Object?, Object?>;
    expect(args['png'], png);
    expect(args['text'], 'CAB HUSTLE — DAILY SHIFT: 1234 pts');
  });

  test('a platform with no native handler throws, not succeeds', () async {
    // No mock handler registered: the messenger answers
    // MissingPluginException, exactly what Android (or a stale binary)
    // produces — the button's SnackBar path exists for this.
    await expectLater(
      const ShareService().shareScoreCard(png: png, text: 'text'),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
