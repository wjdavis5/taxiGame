import 'dart:math';

import 'package:flutter/material.dart';

/// The kinds of fare a shift offers (issue #25).
///
/// Every fare is one of four kinds, and the kind changes the deal — what it
/// pays, how long the meter runs, and what it does to the chain on time —
/// so each pickup is a small decision: take it, or drive past.
///
/// The types are drawn deterministically from the run's seed (see
/// [draw]), so the same course always offers the same fares — the Daily
/// Shift's reproducibility (issue #19) covers the fare mix exactly like
/// the geometry.
///
/// Pure logic — no Flame state — so every rule is unit testable, matching
/// [FareChain] and `EndlessCourse`.
enum FareType {
  /// The everyday ride: nothing special about it.
  standard,

  /// A much better-paying ride on a much tighter clock. The premium buys
  /// the risk: the meter has no slack, so a VIP is a fare you take because
  /// you can see the road is clear — and decline when it is not.
  vip,

  /// A ride across the whole slot to a distant dropoff, paying its coin
  /// fare plus a big multiplier boost on time. The long-haul's payout is
  /// the chain it builds, not the coins it drops.
  longHaul,

  /// A short hop whose dropoff waits on the *far* kerb: the fare forces a
  /// lane change under a shortened clock. Paid a cross-town premium for
  /// the trouble.
  awkward;

  /// Coins multiplier applied to the distance-scaled base reward. VIP is
  /// the only get-rich-quick fare on the street; the long-haul is paid in
  /// chain instead of coins, and the awkward premium covers the crossing.
  double get rewardMultiplier => switch (this) {
        FareType.standard => 1.0,
        FareType.vip => 3.0,
        FareType.longHaul => 1.0,
        FareType.awkward => 1.5,
      };

  /// Fraction of the standard time budget this fare's countdown runs on
  /// ([FareChain.secondsForRide] scales every budget term by it). The VIP's
  /// 0.6 is the whole gamble — roughly the realistic deep-traffic cruise
  /// with none of the usual loading allowance — and the awkward fare's 0.8
  /// is what makes its lane change "under pressure".
  double get timeScale => switch (this) {
        FareType.standard => 1.0,
        FareType.vip => 0.6,
        FareType.longHaul => 1.0,
        FareType.awkward => 0.8,
      };

  /// Extra chain steps granted on top of [FareChain.multiplierStep] when
  /// this fare delivers on time. Only the long-haul boosts the chain —
  /// that boost *is* its payout — so a delivered long-haul jumps the
  /// multiplier three steps at once.
  int get chainStepBonus => switch (this) {
        FareType.longHaul => 2,
        _ => 0,
      };

  /// True for the everyday ride; the tutorial ladder's fares are all
  /// standard by design (a level's pickups are mandatory objectives, so
  /// there is no take-it-or-leave-it decision for a special fare to live
  /// in).
  bool get isStandard => this == FareType.standard;

  /// Marker and badge colour, shared by the world-space zone rendering and
  /// the HUD, so a fare reads as the same kind on the street and in the
  /// offer bar. Green stays the everyday fare's colour, as it always was.
  Color get markerColor => switch (this) {
        FareType.standard => Colors.green,
        FareType.vip => Colors.amber,
        FareType.longHaul => Colors.deepPurpleAccent,
        FareType.awkward => Colors.orange,
      };

  /// The label drawn under a waiting fare's zone markers.
  String get zoneLabel => switch (this) {
        FareType.standard => '',
        FareType.vip => 'VIP \u00d73',
        FareType.longHaul => 'LONG HAUL',
        FareType.awkward => 'FAR SIDE',
      };

  /// The one-line pitch the HUD's offer bar shows while this fare waits on
  /// the kerb, priced at [rewardCoins] coins. [chainStepBonus] feeds the
  /// long-haul's line so the pitch never drifts from the rule.
  String offerBlurb(int rewardCoins) => switch (this) {
        FareType.standard => 'FARE \u00b7 $rewardCoins c',
        FareType.vip => 'VIP \u00b7 $rewardCoins c \u00b7 TIGHT CLOCK',
        FareType.longHaul =>
          'LONG HAUL \u00b7 $rewardCoins c \u00b7 +${chainStepBonus + 1} CHAIN',
        FareType.awkward => 'FAR SIDE \u00b7 $rewardCoins c',
      };

  /// How often each kind turns up. One fare in ten is a VIP, one a
  /// long-haul, one an awkward crossing; the other seven are the everyday
  /// rides the chain economy was tuned around. A shift that delivers
  /// 10-20 fares therefore meets a handful of decisions without the
  /// specials crowding out the baseline.
  static const double vipShare = 0.10;
  static const double longHaulShare = 0.10;
  static const double awkwardShare = 0.10;

  /// Draws one fare kind from [random]. Deterministic given the generator's
  /// state, so a seeded course draws the same mix every replay.
  static FareType draw(Random random) {
    final roll = random.nextDouble();
    if (roll < vipShare) return FareType.vip;
    if (roll < vipShare + longHaulShare) return FareType.longHaul;
    if (roll < vipShare + longHaulShare + awkwardShare) {
      return FareType.awkward;
    }
    return FareType.standard;
  }
}
