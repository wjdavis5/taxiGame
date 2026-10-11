import '../data/vehicle_catalog.dart';
import 'achievements.dart';

/// What the next-goal line is pointing at (issue #282).
///
/// The City License board (#278) adds a third kind for its license
/// objective; the selection below is written as a list of sources so
/// that arrives as one more entry, not a rewrite.
enum NextGoalKind { vehicle, achievement }

/// The one goal the menu and the run summary point at next (issue #282):
/// the next unowned car while the garage ladder has one, otherwise the
/// closest locked achievement.
///
/// Pure selection over plain values — no service, no storage, no widget —
/// so the rules are unit-testable, and both surfaces render the same
/// [line].
class NextGoal {
  const NextGoal({
    required this.kind,
    required this.id,
    required this.title,
    required this.detail,
  });

  final NextGoalKind kind;

  /// Stable id of the thing the goal names — a vehicle id or an
  /// achievement id. Pinned by tests and the seam #278 reuses.
  final String id;

  /// Uppercase display name ('CITY COMPACT', 'HOT STREAK').
  final String title;

  /// What reaching it takes, in the app's own voice ('3000 COINS TO GO',
  /// '2/3').
  final String detail;

  /// The one-line form both surfaces render, so the menu and the run
  /// summary can never phrase the same goal differently.
  String get line => 'NEXT GOAL \u00b7 $title \u2014 $detail';

  /// Picks the next goal from the live save's values.
  ///
  /// Sources are tried in order: the garage ladder first (the only coin
  /// sink, priced as an ascending progression), then the closest locked
  /// achievement by progress toward its threshold. Null only when every
  /// car is owned and every achievement is earned — a save with nothing
  /// left to chase renders no line rather than a placeholder.
  static NextGoal? select({
    required int totalCoins,
    required List<String> unlockedVehicleIds,
    required AchievementState achievementState,
    required bool Function(String achievementId) isAchievementEarned,
  }) {
    final query = _GoalQuery(
      totalCoins: totalCoins,
      unlockedVehicleIds: unlockedVehicleIds,
      achievementState: achievementState,
      isAchievementEarned: isAchievementEarned,
    );
    for (final source in _sources) {
      final goal = source(query);
      if (goal != null) return goal;
    }
    return null;
  }

  /// The sources, in priority order. Issue #278's license objective plugs
  /// in here as one more function, alongside the query and kind fields it
  /// needs; this class is where that seam lives.
  static final List<NextGoal? Function(_GoalQuery)> _sources = [
    _nextVehicle,
    _nextAchievement,
  ];

  static NextGoal? _nextVehicle(_GoalQuery query) {
    for (final vehicle in VehicleCatalog.vehicles) {
      if (query.unlockedVehicleIds.contains(vehicle.id)) continue;
      final shortfall = vehicle.price - query.totalCoins;
      return NextGoal(
        kind: NextGoalKind.vehicle,
        id: vehicle.id,
        title: vehicle.name.toUpperCase(),
        detail: shortfall > 0 ? '$shortfall COINS TO GO' : 'READY TO BUY',
      );
    }
    return null;
  }

  static NextGoal? _nextAchievement(_GoalQuery query) {
    AchievementDef? closest;
    var closestRatio = -1.0;
    for (final def in AchievementCatalog.all) {
      if (query.isAchievementEarned(def.id)) continue;
      final progress = def.progress(query.achievementState);
      // A measure already at the threshold is reached even before the
      // save records it (an unevaluated save) — never a goal.
      if (progress >= def.threshold) continue;
      final ratio = progress / def.threshold;
      // Strict greater: an all-zero save keeps catalog order, so the
      // first track's first tier is the named goal.
      if (ratio > closestRatio) {
        closest = def;
        closestRatio = ratio;
      }
    }
    if (closest == null) return null;
    return NextGoal(
      kind: NextGoalKind.achievement,
      id: closest.id,
      title: closest.title,
      detail:
          '${closest.progress(query.achievementState)}/${closest.threshold}',
    );
  }
}

/// One immutable snapshot of the save values the sources read.
class _GoalQuery {
  const _GoalQuery({
    required this.totalCoins,
    required this.unlockedVehicleIds,
    required this.achievementState,
    required this.isAchievementEarned,
  });

  final int totalCoins;
  final List<String> unlockedVehicleIds;
  final AchievementState achievementState;
  final bool Function(String achievementId) isAchievementEarned;
}
