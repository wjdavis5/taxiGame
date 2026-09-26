import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/bank_prompt.dart';

/// The timed bank-or-push choice (issue #13): a five-second window that
/// defaults to pushing on when it closes without an answer.
void main() {
  group('an inactive prompt', () {
    test('offers nothing and resolves nothing', () {
      final prompt = BankPrompt();

      expect(prompt.isActive, isFalse);
      expect(prompt.remainingSeconds, 0);
      expect(prompt.fractionRemaining, 0);
      expect(prompt.update(1.0), isNull);
      expect(prompt.bank(), isNull);
      expect(prompt.push(), isNull);
    });
  });

  group('an offered prompt', () {
    test('opens with the full window', () {
      final prompt = BankPrompt()..offer();

      expect(prompt.isActive, isTrue);
      expect(prompt.remainingSeconds, BankPrompt.windowSeconds);
      expect(prompt.fractionRemaining, 1.0);
    });

    test('ticks down in update without resolving early', () {
      final prompt = BankPrompt()..offer();

      expect(prompt.update(1.0), isNull);
      expect(prompt.update(0.5), isNull);
      expect(prompt.isActive, isTrue);
      expect(prompt.remainingSeconds, closeTo(BankPrompt.windowSeconds - 1.5, 1e-9));
      expect(prompt.fractionRemaining, closeTo(1 - 1.5 / BankPrompt.windowSeconds, 1e-9));
    });

    test('a closed window defaults to pushing on, exactly once', () {
      final prompt = BankPrompt()..offer();

      // Burn the whole window in small steps.
      BankDecision? resolution;
      for (var i = 0; i < 60; i++) {
        resolution = prompt.update(0.1) ?? resolution;
      }

      expect(resolution, BankDecision.pushed,
          reason: 'no answer is an answer: the player rode on');
      expect(prompt.isActive, isFalse);

      // The resolution is spent — later ticks must not push again.
      expect(prompt.update(1.0), isNull);
      expect(prompt.update(1.0), isNull);
    });

    test('banking resolves to banked exactly once', () {
      final prompt = BankPrompt()..offer();
      prompt.update(1.0);

      expect(prompt.bank(), BankDecision.banked);
      expect(prompt.isActive, isFalse);
      expect(prompt.bank(), isNull, reason: 'a spent prompt pays out once');
      expect(prompt.push(), isNull,
          reason: 'and cannot also count as a push');
    });

    test('pushing resolves to pushed exactly once', () {
      final prompt = BankPrompt()..offer();

      expect(prompt.push(), BankDecision.pushed);
      expect(prompt.isActive, isFalse);
      expect(prompt.push(), isNull);
      expect(prompt.bank(), isNull);
    });

    test('offering again while open restarts the window', () {
      final prompt = BankPrompt()..offer();
      prompt.update(4.0);
      expect(prompt.remainingSeconds, closeTo(1.0, 1e-9));

      // A second fare delivered before the player answered: the freshest
      // dropoff owns the decision.
      prompt.offer();

      expect(prompt.isActive, isTrue);
      expect(prompt.remainingSeconds, BankPrompt.windowSeconds);
    });

    test('dismiss tears it down with no decision owed', () {
      final prompt = BankPrompt()..offer();

      prompt.dismiss();

      expect(prompt.isActive, isFalse);
      expect(prompt.remainingSeconds, 0);
      // Nothing resolves after a dismissal: a crash supersedes the
      // choice without paying its consequence.
      expect(prompt.bank(), isNull);
      expect(prompt.push(), isNull);
      expect(prompt.update(1.0), isNull);
    });
  });
}
