import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/models/achievements.dart';
import 'package:taxi_game/models/next_goal.dart';

/// The next-goal selection (issue #282): the garage ladder while a car is
/// unowned, then the closest locked achievement. The City License board
/// (#278) adds a source to [NextGoal.select]; these tests pin the two
/// sources that ship and the seam they plug into.
void main() {
  const starterId = 'taxi_yellow';

  AchievementState stateWith({
    int bestBankedScore = 0,
    int longestChain = 0,
    int furthestDistanceMetres = 0,
    int mostFaresInOneShift = 0,
    int cleanBankedShifts = 0,
    int unlockedVehicleCount = 1,
    int longestDailyStreak = 0,
  }) =>
      AchievementState(
        bestBankedScore: bestBankedScore,
        longestChain: longestChain,
        furthestDistanceMetres: furthestDistanceMetres,
        mostFaresInOneShift: mostFaresInOneShift,
        cleanBankedShifts: cleanBankedShifts,
        unlockedVehicleCount: unlockedVehicleCount,
        longestDailyStreak: longestDailyStreak,
      );

  NextGoal? select({
    int totalCoins = 0,
    List<String> unlocked = const [starterId],
    AchievementState? state,
    Set<String> earned = const {},
  }) =>
      NextGoal.select(
        totalCoins: totalCoins,
        unlockedVehicleIds: unlocked,
        achievementState:
            state ?? stateWith(unlockedVehicleCount: unlocked.length),
        isAchievementEarned: earned.contains,
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

  test('a completed fleet falls through to the closest locked achievement',
      () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(
        furthestDistanceMetres: 3000,
        unlockedVehicleCount: VehicleCatalog.vehicles.length,
      ),
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
    )!;
    expect(goal.id, 'chain_8');
  });

  test('null when every car is owned and every achievement is earned', () {
    final goal = select(
      unlocked: VehicleCatalog.vehicles.map((v) => v.id).toList(),
      state: stateWith(unlockedVehicleCount: VehicleCatalog.vehicles.length),
      earned: AchievementCatalog.all.map((a) => a.id).toSet(),
    );
    expect(goal, isNull,
        reason: 'a completed save renders no line, never a placeholder');
  });
}
