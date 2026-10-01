import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../game/systems/daily_shift.dart';

/// Rebuilds its subtree when the calendar day rolls over (issue #113).
///
/// A day-dependent widget — the menu's daily card, the Daily screen's
/// today card — is built once and rebuilt only when the save notifies,
/// so nothing told it the day had changed: a player who finished the
/// Daily Shift, backgrounded the app, and came back the next day found
/// the menu still saying "TODAY'S RESULT · DONE FOR TODAY", the new
/// day's course hidden behind a stale card until some unrelated save
/// write happened to rebuild it. The game screen has lifecycle handling
/// of its own ([TaxiGame.lifecycleStateChange]), but that lives and
/// dies with the game; menus have nothing.
///
/// Two triggers, for the two ways a day changes:
///
///  - *resume* — the app was backgrounded across midnight. The clock
///    rolled while nothing was observing it, so the check runs the
///    moment the app comes back to the foreground.
///  - *a one-minute timer* — the app stayed open across midnight and no
///    lifecycle event will ever come. One minute is the staleness
///    budget: a card at most 59 s behind the clock, invisible next to
///    the day-long granularity it guards. The timer is cancelled in
///    [State.dispose], so a screen torn down (the menu covered by a
///    pushed route, the app exiting) leaves nothing pending — and the
///    fresh mount on return re-reads the day anyway.
///
/// The builder receives the day key it is being built for — the
/// snapshot the subtree should cohere around. Taps that act on a day
/// still re-read the live [DailyShift.todayKey] at tap time (the
/// discipline the ghost-race button's #96 guard set): a build is for
/// the day it names, an action is for the day it finds.
class DayKeyBuilder extends StatefulWidget {
  const DayKeyBuilder({super.key, required this.builder});

  /// Builds the subtree for the day named by [dayKey].
  final Widget Function(BuildContext context, String dayKey) builder;

  @override
  State<DayKeyBuilder> createState() => _DayKeyBuilderState();
}

class _DayKeyBuilderState extends State<DayKeyBuilder>
    with WidgetsBindingObserver {
  /// How often the open-app path looks at the clock.
  static const _checkEvery = Duration(minutes: 1);

  late final Timer _dayTick;
  late String _dayKey;

  @override
  void initState() {
    super.initState();
    _dayKey = DailyShift.todayKey;
    WidgetsBinding.instance.addObserver(this);
    _dayTick = Timer.periodic(_checkEvery, (_) => _refreshDay());
  }

  @override
  void dispose() {
    _dayTick.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume is the only state where a missed rollover needs catching
    // up: inactive is a transient overlay (shade, call banner) the app
    // outlives with its timer still running, and everything below it
    // cannot run code at all.
    if (state == AppLifecycleState.resumed) _refreshDay();
  }

  void _refreshDay() {
    final key = DailyShift.todayKey;
    if (key == _dayKey) return;
    setState(() => _dayKey = key);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _dayKey);
}
