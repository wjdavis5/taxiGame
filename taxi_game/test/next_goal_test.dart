import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/models/achievements.dart';
import 'package:taxi_game/models/city_license.dart';
import 'package:taxi_game/models/next_goal.dart';

/// The next-goal selection (issue #282): the garage ladder while a car is
/// unowned, then the City License board's next open objective (issue
/// #278), then the closest locked achievement. These tests pin all three
/// sources and the priority order between them.
void main() {
  const starterId = 'taxi_yellow';

  /// Every license objective's id — the shape a save holds once the whole
  /// board is complete.
  final allLicenseIds = CityLicense.board.map((rule) => rule.id).toSet();

  AchievementState stateWith({
    int bestBankedScore = 0,
    int longestChain = 0,
    int furthestDistanceMetres = 0,
    int mostFaresInOneShift = 0,
    int cleanBankedShifts = 0,
    int unlockedVehicleCount = 1,
    int longestDailyStreak = 0,
    int totalNearMisses = 0,
    int completedDailyCount = 0,
    int lifetimeDistanceMetres = 0,
    bool tutorialComplete = false,
  }) =>
      AchievementState(
        bestBankedScore: bestBankedScore,
        longestChain: longestChain,
        furthestDistanceMetres: furthestDistanceMetres,
        mostFaresInOneShift: mostFaresInOneShift,
        cleanBankedShifts: cleanBankedShifts,
        unlockedVehicleCount: unlockedVehicleCount,
        longestDailyStreak: longestDailyStreak,
        totalNearMisses: totalNearMisses,
        completedDailyCount: completedDailyCount,
        lifetimeDistanceMetres: lifetimeDistanceMetres,
        tutorialComplete: tutorialComplete,
      );

  NextGoal? select({
    int totalCoins = 0,
    List<String> unlocked = const [starterId],
    AchievementState? state,
    Set<String> earned = const {},
    Set<String> completedLicense = const {},
  }) =>
      NextGoal.select(
        totalCoins: totalCoins,
        unlockedVehicleIds: unlocked,
        achievementState:
            state ?? stateWith(unlockedVehicleCount: unlocked.length),
        isAchievementEarned: earned.contains,
        completedLicenseObjectiveIds: completedLicense,
      );

  test('a fresh save chases the first unowned car, in ladder order', () {
    final goal = select()!;
    expect(goal.kind, NextGoalKind.vehicle);
    expect(goal.id, 'compact_red',
        reason: 'the ladder is priced ascending; the compact is next');
    expect(goal.title, 'CITY COMPACT');
    expect(goal.detail, '5000 COINS TO GO');
  });

  test('the detail is the shortfall, or READY TO BUY once affordable', () {
    expect(select(totalCoins: 2000)!.detail, '3000 COINS TO GO');
    expect(select(totalCoins: 5000)!.detail, 'READY TO BUY');
  });

  test('the first owned car drops out of the goal', () {
    final goal = select(unlocked: const [starterId, 'compact_red'])!;
    expect(goal.id, 'sedan_blue');
  });

  test('a completed fleet falls through to the next open license objective',
      () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(unlockedVehicleCount: VehicleCatalog.vehicles.length),
    )!;
    expect(goal.kind, NextGoalKind.license,
        reason: 'the garage ladder is spent; the post-tutorial board leads');
    expect(goal.id, 'cleanBank',
        reason: 'board order: the first objective is the first goal');
    expect(goal.title, 'CLEAN BANK');
    expect(goal.detail, 'BANK A SHIFT WITH 0 CRASHES');
    expect(goal.line,
        'NEXT GOAL \u00b7 CLEAN BANK \u2014 BANK A SHIFT WITH 0 CRASHES');
  });

  test('a completed objective drops out for the next open one', () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(unlockedVehicleCount: VehicleCatalog.vehicles.length),
      completedLicense: const {'cleanBank'},
    )!;
    expect(goal.kind, NextGoalKind.license);
    expect(goal.id, 'bigBank');
  });

  test('a completed board falls through to the closest locked achievement',
      () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(
        furthestDistanceMetres: 3000,
        unlockedVehicleCount: VehicleCatalog.vehicles.length,
      ),
      completedLicense: allLicenseIds,
    )!;
    expect(goal.kind, NextGoalKind.achievement);
    expect(goal.id, 'distance_5000',
        reason: '3000/5000 is closer than any other locked tier');
    expect(goal.title, 'CROSS-TOWN LEGEND');
    expect(goal.detail, '3000/5000');
    expect(goal.line, 'NEXT GOAL \u00b7 CROSS-TOWN LEGEND \u2014 3000/5000');
  });

  test('achievement ties keep catalog order', () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(unlockedVehicleCount: VehicleCatalog.vehicles.length),
      completedLicense: allLicenseIds,
    )!;
    expect(goal.id, 'chain_3',
        reason: 'every ratio is 0; the first track\'s first tier leads');
    expect(goal.detail, '0/3');
  });

  test('earned achievements are skipped for the next locked one', () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(unlockedVehicleCount: VehicleCatalog.vehicles.length),
      earned: const {'chain_3', 'chain_5'},
      completedLicense: allLicenseIds,
    )!;
    expect(goal.id, 'chain_8');
  });

  test('null when every car is owned, the board is complete, and every '
      'achievement is earned', () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(unlockedVehicleCount: VehicleCatalog.vehicles.length),
      earned: AchievementCatalog.all.map((a) => a.id).toSet(),
      completedLicense: allLicenseIds,
    );
    expect(goal, isNull,
        reason: 'a completed save renders no line, never a placeholder');
  });
}
