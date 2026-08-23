import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('orientation lock', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('requests exactly the portrait orientations', () async {
      await lockOrientation();

      final call = platformCalls.singleWhere(
        (c) => c.method == 'SystemChrome.setPreferredOrientations',
      );

      expect(call.arguments, <String>[
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ]);
    });

    test('requests no landscape orientation', () async {
      await lockOrientation();

      final call = platformCalls.singleWhere(
        (c) => c.method == 'SystemChrome.setPreferredOrientations',
      );

      expect(
        (call.arguments as List).where((o) => '$o'.contains('landscape')),
        isEmpty,
      );
    });

    test('supportedOrientations contains no landscape entry', () {
      expect(
        supportedOrientations.where(
          (o) => o == DeviceOrientation.landscapeLeft ||
              o == DeviceOrientation.landscapeRight,
        ),
        isEmpty,
      );
    });
  });
}
