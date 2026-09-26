/// The Date-seeded Daily Shift (issue #19).
///
/// The game is permanently offline — no leaderboards, no accounts, no
/// server — but the *effect* of a leaderboard is reachable without one:
/// the run seed is derived from the calendar date, so every player in the
/// world gets the identical course on the same day. Comparison then
/// happens socially (screenshots), with no backend and no change to the
/// zero-network claim. The seed is computed, never fetched.
///
/// The daily shift **is** an endless shift (issue #11's ramp — the open
/// question in the issue resolved as "the same endless ramp, shared
/// seed", not a fixed distance): [EndlessCourse] is already a pure
/// function of (seed, index) and the difficulty curve a pure function of
/// distance, so a shared seed is all reproducibility costs. One attempt
/// per day: the attempt is spent when the shift ends — banked or wrecked
/// — and until midnight the day's button becomes the way to see the
/// result instead.
///
/// Pure logic — no I/O, no clock reads except [todayKey] — so the date
/// rules are unit testable like [EndlessCourse] itself.
class DailyShift {
  DailyShift._();

  /// The date key of the local calendar day [moment] falls on:
  /// zero-padded 'yyyy-MM-dd'. Local, deliberately — there is no server
  /// to define a canonical time zone, and none is wanted; the day a
  /// player wakes up to is the day they share with everyone else playing
  /// their calendar day.
  static String dateKeyFor(DateTime moment) {
    final year = moment.year.toString().padLeft(4, '0');
    final month = moment.month.toString().padLeft(2, '0');
    final day = moment.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// The date key of today, on this device's clock.
  static String get todayKey => dateKeyFor(DateTime.now());

  /// The run seed for the day named by [dateKey] ('yyyy-MM-dd').
  ///
  /// A pure hash of the date: the same day always yields the same seed on
  /// every device, and neighbouring days land on unrelated seeds, so a
  /// new day is genuinely a new city. The layout of this function is
  /// load-bearing — changing it would rewrite the courses of history's
  /// dates, so once shipped it must never be "improved".
  ///
  /// Every intermediate value stays inside 62 bits (the day number is
  /// under 2^25 and every multiplier under 2^31), so the arithmetic is
  /// exact — and therefore identical — on every platform Dart compiles to.
  static int seedForDateKey(String dateKey) {
    if (dateKey.length != 10 || dateKey[4] != '-' || dateKey[7] != '-') {
      throw ArgumentError.value(dateKey, 'dateKey', 'expected yyyy-MM-dd');
    }
    final year = int.parse(dateKey.substring(0, 4));
    final month = int.parse(dateKey.substring(5, 7));
    final day = int.parse(dateKey.substring(8, 10));
    final dayNumber = year * 10000 + month * 100 + day;

    var x = dayNumber * 0x7F4A7C15 ^ 0x5EEDCAB5; // < 2^57, exact
    x = ((x ^ (x >> 17)) & 0x3FFFFFFF) * 0x2C1B3C6D; // < 2^60, exact
    return (x ^ (x >> 13)) & 0x3FFFFFFF; // same 30-bit space as freshSeed()
  }
}
