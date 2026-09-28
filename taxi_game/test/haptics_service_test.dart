import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/services/haptics_service.dart';

/// The haptics service itself (issue #5): which impact each gameplay event
/// asks for, and that the enabled-gate decides at fire time. The game's
/// routing — that a crash actually calls [HapticsService.crash] — is proven
/// in haptics_wiring_test.dart, exactly as the audio service pairs
/// audio_service_test.dart with audio_wiring_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HapticsService', () {
    test('a fresh service vibrates', () {
      expect(HapticsService().enabled, isTrue,
          reason: 'a fresh save carries vibrationEnabled true; the service '
              'default matches it');
    });

    testWidgets('each event asks the platform for its own weight',
        (tester) async {
      // Capture the raw platform calls: the heavy/medium/light split is
      // the whole feel contract, so it is asserted against what the
      // platform channel was actually asked for. The HapticFeedback
      // wrappers send `HapticFeedback.vibrate` carrying the intensity as
      // a HapticFeedbackType value (kept as its toString here — the type
      // itself is not part of the public services API).
      final requested = <String>[];
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method.startsWith('HapticFeedback.')) {
          requested.add(call.arguments.toString());
        }
        return 0;
      });
      addTearDown(() => TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final haptics = HapticsService();
      haptics.crash();
      haptics.pickup();
      haptics.dropoff();
      haptics.coinAward();
      haptics.buttonPress();
      await tester.pump();

      expect(requested, [
        'HapticFeedbackType.heavyImpact', // crash
        'HapticFeedbackType.mediumImpact', // pickup
        'HapticFeedbackType.mediumImpact', // dropoff
        'HapticFeedbackType.lightImpact', // coin award
        'HapticFeedbackType.lightImpact', // button press
      ]);
    });

    test('every gated-through attempt is recorded per event', () {
      final haptics = HapticsService();
      haptics.crash();
      haptics.pickup();
      haptics.dropoff();
      haptics.coinAward();
      haptics.buttonPress();

      expect(haptics.attemptedBuzzes, {
        'crash_heavy': 1,
        'pickup_medium': 1,
        'dropoff_medium': 1,
        'coin_light': 1,
        'button_light': 1,
      });
    });

    test('a disabled service routes nothing, heavy or light', () {
      final haptics = HapticsService()..setEnabled(false);
      haptics.crash();
      haptics.pickup();
      haptics.dropoff();
      haptics.coinAward();
      haptics.buttonPress();

      expect(haptics.attemptedBuzzes, isEmpty,
          reason: 'the save vibration setting gates every impact');
    });

    test('re-enabling restores the buzz', () {
      final haptics = HapticsService()
        ..setEnabled(false)
        ..setEnabled(true);

      haptics.buttonPress();

      expect(haptics.attemptedBuzzes['button_light'], 1);
    });
  });
}
