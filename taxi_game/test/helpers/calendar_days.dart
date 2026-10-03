/// Calendar-day arithmetic for the daily-shift tests (issue #196).
///
/// "Tomorrow" and "yesterday" in these tests used to be built as
/// `DateTime.now().add(const Duration(days: 1))` — 24 *absolute* hours,
/// which is a calendar day only when no daylight-saving transition sits in
/// between. On the 25-hour fall-back day, now + 24h is still today for the
/// hour after midnight (and now − 24h is still tomorrow for the hour before
/// it), so a rollover test that pinned `DailyShift.clock` to "tomorrow" was
/// pinning it back to day D and its "new day" assertions went vacuous or
/// red; on the 23-hour spring day the key skips a day outright. The
/// day-walking loops had the same defect one level down — a +24h step
/// repeats the fall-back day's key, so a "full year of days yields 365
/// distinct seeds" walk yields 364 in the southern hemisphere, where the
/// calendar year hits fall-back (April) before spring (October) and the
/// walk is still anchored at midnight when it does.
///
/// The fix is the move `DailyShift.dateKeyFor` itself makes everywhere:
/// read calendar fields, never elapsed time. The `DateTime` constructor
/// normalizes out-of-range components as *wall-clock* arithmetic — day 0 is
/// the last day of the previous month, day 32 the first of the next, across
/// month, year, and leap-year boundaries — with no absolute duration ever
/// crossing a transition. Noon is the anchor hour because a transition
/// would have to fall exactly on 12:00 to touch it; real zones switch in
/// the small hours (02:00–03:00 typically, midnight historically, even
/// Lord Howe's half-hour shift at 02:00), so noon stays clear of both
/// edges of every 23- and 25-hour day the walk may cross.
DateTime calendarDaysFrom(DateTime base, int days) =>
    DateTime(base.year, base.month, base.day + days, 12);

/// [days] calendar days from now, at noon — see [calendarDaysFrom].
///
/// Reading `DateTime.now()` per call (not once at capture) keeps the
/// composed pins honest: `DailyShift.clock = () => calendarDaysFromNow(1)`
/// re-derives tomorrow at every read, exactly as the production clock
/// re-reads now.
DateTime calendarDaysFromNow(int days) => calendarDaysFrom(DateTime.now(), days);
