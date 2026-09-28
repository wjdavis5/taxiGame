import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The game's haptics wiring (issue #5): a mounted game carrying a real
/// [HapticsService] must actually reach for the right impacts at the right
/// gameplay moments. The service's weights and gate are proven in
/// haptics_service_test.dart — here it is the *routing* under test,
/// observed through `attemptedBuzzes` (nothing buzzes under flutter test).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late StorageService storage;
  late HapticsService haptics;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    haptics = HapticsService();
  });

  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // Internal on purpose — the same call GameWidget makes (see
    // endless_run_test.dart for the full explanation).
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  TaxiGame endlessGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        haptics: haptics,
        endlessSeed: 42,
      )
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink());

  TaxiGame levelGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        haptics: haptics,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink());

  /// Lets pending component mounts finish before the next simulated tick.
  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  CrashReport busCrash() => CollisionRules.buildReport(
        severity: ContactSeverity.crash,
        vehicleKind: 'bus',
        playerVelocity: Vector2(0, -150),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, 60),
        trafficPosition: Vector2(200, 40),
        contactPoint: Vector2(199.5, 70),
      );

  CrashReport coneScrape() => CollisionRules.buildReport(
        severity: ContactSeverity.scrape,
        vehicleKind: 'traffic cone',
        playerVelocity: Vector2(0, -40),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2.zero(),
        trafficPosition: Vector2(210, 100),
        contactPoint: Vector2(200, 100),
      );

  test('an endless crash buzzes heavy once', () async {
    final game = await mountGame(endlessGame());

    game.onCrash(busCrash());

    expect(haptics.attemptedBuzzes['crash_heavy'], 1,
        reason: 'the heavy buzz lands in the same instant as the hit-stop');
  });

  test('a fare ride buzzes medium at both kerbs', () async {
    final game = await mountGame(endlessGame());
    await tickAndSettle(game);

    final fare = game.course!.fare(0);

    // Pull up to the pickup kerb.
    game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
    game.update(1 / 60);
    expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');
    expect(haptics.attemptedBuzzes['pickup_medium'], 1,
        reason: 'boarding confirms itself in the hand');

    // And to the dropoff kerb, where the fare pays.
    game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
    game.update(1 / 60);
    expect(game.fareController!.faresDelivered, 1);

    expect(haptics.attemptedBuzzes['pickup_medium'], 1);
    expect(haptics.attemptedBuzzes['dropoff_medium'], 1,
        reason: 'the payout confirms itself in the hand');
  });

  test('a scrape is heard, never buzzed', () async {
    final game = await mountGame(endlessGame());

    game.onScrape(coneScrape());

    expect(haptics.attemptedBuzzes, isEmpty,
        reason: 'only a judged crash carries a buzz — a scrape is '
            'sheet-metal noise, not an impact');
  });

  test('completing a level ticks light for the coin award', () async {
    final game = await mountGame(levelGame());
    await game.loadLevel(1);
    await tickAndSettle(game);

    final level = game.currentLevel;
    for (var f = 0; f < level.pickupPoints.length; f++) {
      game.player.position = Vector2(
          level.pickupPoints[f].x, level.pickupPoints[f].y + 30);
      game.update(1 / 60);
      await drain();
      game.player.position = Vector2(
          level.dropoffPoints[f].x, level.dropoffPoints[f].y + 30);
      game.update(1 / 60);
      await drain();
    }

    expect(game.overlays.isActive('levelComplete'), isTrue,
        reason: 'the level actually completed');
    // Level 1 is a single fare: its kerbs buzz medium like any other
    // ride, and the completion's coin award ticks light on top.
    expect(haptics.attemptedBuzzes, {
      'pickup_medium': 1,
      'dropoff_medium': 1,
      'coin_light': 1,
    });
  });

  test('a disabled service routes nothing, loudly or quietly', () async {
    haptics.setEnabled(false);
    final game = await mountGame(endlessGame());

    game.onCrash(busCrash());
    game.onScrape(coneScrape());

    expect(haptics.attemptedBuzzes, isEmpty,
        reason: 'the save vibration setting gates the game wiring too');
  });
}
