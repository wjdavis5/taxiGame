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

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GameStateService>.value(value: gameState),
        Provider<AudioService>.value(value: AudioService()),
        Provider<StorageService>.value(value: storage),
      ],
      child: const MaterialApp(home: MainMenuScreen()),
    );
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
      await tester.pumpAndSettle();

      expect(find.byType(CreditsScreen), findsOneWidget);
    });

    testWidgets('back returns to the main menu', (tester) async {
      await tester.pumpWidget(await buildMenu());
      await tester.pump();

      final button = find.byKey(const ValueKey('credits_button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('credits_back_button')));
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('credits list scrolls when content exceeds the viewport',
        (tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
