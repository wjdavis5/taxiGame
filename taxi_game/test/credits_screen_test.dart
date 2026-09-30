import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/credits.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/credits_screen.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<Widget> buildMenu() async {
    final storage = StorageService();
    await storage.init();
    final gameState = GameStateService(storage);

    // Sound is gated off at the service — the documented no-platform path
    // (playSound's first line). Every _MenuButton wraps its onPressed in
    // playButtonSound(), and a live voice pool reaches the audioplayers
    // plugin, which does not exist under flutter test. The old fake-async
    // settles never yielded a real event-loop turn, so the plugin's error
    // response never made it back into the test and the latent
    // MissingPluginException stayed invisible; the real 2 ms turns
    // untilCreditsSettles polls with (issue #77) are exactly what lets it
    // arrive. Nothing in this file asserts about sound.
    final audio = AudioService()..setSoundEnabled(false);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GameStateService>.value(value: gameState),
        Provider<AudioService>.value(value: audio),
        Provider<StorageService>.value(value: storage),
      ],
      child: const MaterialApp(home: MainMenuScreen()),
    );
  }

  /// Waits until [done] holds, alternating a real 2 ms event-loop turn
  /// with a 100 ms frame pump, and fails loudly at a 5 s deadline.
  ///
  /// `pumpAndSettle` drained this file cleanly in isolation but raced the
  /// suite's real async work under full-suite parallel load: four tests
  /// here reported '(did not complete)' on one loaded run and the file
  /// passed 7/7 the moment it ran alone (issue #77) — the same flake class
  /// #46's `untilShareSettles` and #69's `untilQuiet` already fixed by
  /// polling the actual settled condition to a deadline instead of
  /// betting on a fixed drain. Deadline polling is load-immune by
  /// construction: quick runs exit on an early check, slow ones keep
  /// stepping, and a genuine hang fails here by name instead of as the
  /// runner's anonymous '(did not complete)'.
  ///
  /// The 100 ms step is what moves a route transition forward — a
  /// zero-duration pump would leave a 300 ms push/pop forever mid-flight —
  /// and the 2 ms delay inside [WidgetTester.runAsync] is a real
  /// event-loop turn, exactly the thing a loaded machine defers and a
  /// bare pump never yields to.
  Future<void> untilCreditsSettles(
    WidgetTester tester,
    bool Function() done,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for the credits screen to settle');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('credits content', () {
    testWidgets('renders the Kenney artwork and sound attributions',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
      await tester.pump();

      // One courtesy credit per Kenney bundle family: artwork and sound.
      expect(find.textContaining('Kenney'), findsNWidgets(2));
      expect(find.textContaining('CC0'), findsNWidgets(2));
      expect(find.text('kenney.nl'), findsNWidgets(2));
    });

    testWidgets('renders a block for every credit entry', (tester) async {
      // A tall surface so the ListView builds every block — a short phone
      // viewport only materializes what is scrolled to.
      tester.view.physicalSize = const Size(750, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
      await tester.pump();

      for (final entry in appCredits) {
        expect(
          find.text(entry.title.toUpperCase()),
          findsOneWidget,
          reason: 'missing credit block for "${entry.title}"',
        );
      }
    });

    test('every credit entry carries non-empty text', () {
      expect(appCredits, isNotEmpty);
      for (final entry in appCredits) {
        expect(entry.title.trim(), isNotEmpty);
        expect(entry.body.trim(), isNotEmpty);
      }
    });
  });

  group('navigation', () {
    testWidgets('credits button on the main menu opens the credits screen',
        (tester) async {
      await tester.pumpWidget(await buildMenu());
      await tester.pump();

      final button = find.byKey(const ValueKey('credits_button'));
      expect(button, findsOneWidget);

      await tester.ensureVisible(button);
      await tester.tap(button);
      // Settled when the pushed route has actually built the credits
      // screen, not after a guessed drain.
      await untilCreditsSettles(
        tester,
        () => tester.any(find.byType(CreditsScreen)),
      );

      expect(find.byType(CreditsScreen), findsOneWidget);
    });

    testWidgets('back returns to the main menu', (tester) async {
      await tester.pumpWidget(await buildMenu());
      await tester.pump();

      final button = find.byKey(const ValueKey('credits_button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await untilCreditsSettles(
        tester,
        () => tester.any(find.byType(CreditsScreen)),
      );

      await tester.tap(find.byKey(const ValueKey('credits_back_button')));
      // Settled when the pop has actually removed the credits route —
      // what the findsNothing assertion below needs to be true.
      await untilCreditsSettles(
        tester,
        () => !tester.any(find.byType(CreditsScreen)),
      );

      expect(find.byType(CreditsScreen), findsNothing);
      expect(find.byType(MainMenuScreen), findsOneWidget);
      expect(find.text('CAB HUSTLE'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('renders without overflow on a narrow portrait screen',
        (tester) async {
      // iPhone SE logical width — the narrowest portrait target, and where the
      // long attribution paragraphs are most likely to overflow.
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
      // Frame-quiet — the very condition pumpAndSettle waits on — polled
      // to a deadline so a loaded machine can take as long as it needs.
      await untilCreditsSettles(
        tester,
        () => !tester.binding.hasScheduledFrame,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('credits list scrolls when content exceeds the viewport',
        (tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
      await untilCreditsSettles(
        tester,
        () => !tester.binding.hasScheduledFrame,
      );

      expect(find.byType(ListView), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      // The drag hands the list a ballistic activity; settled once it has
      // gone frame-quiet again, so the post-scroll layout is what the
      // takeException check reads.
      await untilCreditsSettles(
        tester,
        () => !tester.binding.hasScheduledFrame,
      );

      expect(tester.takeException(), isNull);
    });
  });
}
