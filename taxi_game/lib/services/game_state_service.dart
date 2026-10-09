import 'package:flutter/foundation.dart';
import '../game/levels/level.dart';
import '../game/systems/daily_shift.dart';
import '../models/achievements.dart';
import '../models/daily_result.dart';
import '../models/ghost_trace.dart';
import '../models/personal_bests.dart';
import '../models/run_record.dart';
import '../models/run_stats.dart';
import '../models/save_data.dart';
import 'diagnostics.dart';
import 'storage_service.dart';

/// Manages global game state and notifies listeners of changes
class GameStateService extends ChangeNotifier {
  final StorageService _storageService;
  late SaveData _saveData;

  /// How many ended shifts the on-device history keeps (issue #17). Old
  /// records fall off the front as new ones arrive: a fixed window is all
  /// the tuning instrument needs, and it bounds the prefs payload forever.
  static const int maxRecordedRuns = 200;

  /// How many completed daily results the on-device history keeps
  /// (issue #19) — a bit over a year of daily play, bounding the prefs
  /// payload forever the same way [maxRecordedRuns] does. Old days fall
  /// off the front as new ones arrive.
  static const int maxRecordedDailyResults = 400;

  final List<RunRecord> _runHistory = <RunRecord>[];
  final List<DailyResult> _dailyHistory = <DailyResult>[];

  /// The stored Daily Shift ghost trace (issue #20) — the best run's
  /// path for one day's course. Null until a daily-course run has ever
  /// finished.
  GhostTrace? _dailyGhost;

  /// Achievements earned by the most recent gameplay event and not yet
  /// surfaced to the player (issue #21). The UI that caused the event —
  /// the run-summary panel after a shift, a snackbar after a garage
  /// purchase — drains it via [takePendingAchievementUnlocks]; the load
  /// path evaluates without queueing, so a retro-award from an app
  /// update never banners unasked.
  final List<AchievementDef> _pendingAchievementUnlocks =
      <AchievementDef>[];

  GameStateService(this._storageService) {
    _saveData = SaveData.createDefault();
  }

  // Getters
  int get currentLevel => _saveData.currentLevel;

  /// True once the save sits past the last rung of the tutorial ladder
  /// (issue #16): the ladder is finished, and the game's answer to PLAY —
  /// in the menu stat and the level loader alike — is the Endless
  /// handoff, never a replay of the final level.
  bool get tutorialComplete => _saveData.currentLevel > GameLevel.ladderLength;

  int get totalCoins => _saveData.totalCoins;
  int get totalGems => _saveData.totalGems;
  String get selectedVehicle => _saveData.selectedVehicle;
  List<String> get unlockedVehicles => _saveData.unlockedVehicles;
  bool get soundEnabled => _saveData.settings.soundEnabled;
  bool get musicEnabled => _saveData.settings.musicEnabled;

  /// Whether haptic feedback fires (issue #5). The save always carried the
  /// flag; the game has only read it since the haptics service was wired.
  bool get vibrationEnabled => _saveData.settings.vibrationEnabled;

  /// The best score an endless shift has ever ended with (issue #15).
  int get endlessBestScore => _saveData.endlessBestScore;

  /// The player's lifetime records (issue #21): best banked score,
  /// longest chain, furthest distance, most fares in one shift.
  PersonalBests get personalBests => _saveData.personalBests;

  /// True when the achievement with [id] has been earned (issue #21).
  /// The save's `achievements` map is the only source of truth — a
  /// definition whose measure currently reads below its threshold can
  /// still be earned, because earned means "was earned", forever.
  bool isAchievementUnlocked(String id) => _saveData.achievements[id] == true;

  /// How many achievements have been earned (issue #21).
  int get unlockedAchievementCount =>
      _saveData.achievements.values.where((earned) => earned).length;

  /// The current achievement measures (issue #21): one snapshot of the
  /// player's standing, rebuilt on demand from the records, the shift
  /// history, the garage, and the daily history. The records screen
  /// reads it for progress toward locked achievements; evaluation reads
  /// it to decide awards.
  AchievementState get achievementState => AchievementState(
        bestBankedScore: _saveData.personalBests.bestBankedScore,
        longestChain: _saveData.personalBests.longestChain,
        furthestDistanceMetres:
            _saveData.personalBests.furthestDistanceMetres.floor(),
        mostFaresInOneShift: _saveData.personalBests.mostFaresInOneShift,
        // The lifetime counter, not a count over the history window
        // (issue #55): the window trims at [maxRecordedRuns], and a
        // progress number that falls as old clean banks age out is the
        // bug this field replaced.
        cleanBankedShifts: _saveData.personalBests.cleanBankedShifts,
        unlockedVehicleCount: _saveData.unlockedVehicles.length,
        longestDailyStreak: AchievementCatalog.longestDailyStreak(
          _dailyHistory,
        ),
      );

  /// Drains the achievements unlocked by the most recent gameplay event
  /// (issue #21): the caller that just caused an award — the shift-end
  /// summary, the garage purchase — shows them and clears the queue.
  List<AchievementDef> takePendingAchievementUnlocks() {
    if (_pendingAchievementUnlocks.isEmpty) return const [];
    final drained = List<AchievementDef>.of(_pendingAchievementUnlocks);
    _pendingAchievementUnlocks.clear();
    return drained;
  }

  /// Awards every achievement the current state has earned but the save
  /// does not yet hold (issue #21), queueing each new award for the
  /// unlock notification and persisting it into the save's
  /// `achievements` map — the map that existed since the first save
  /// schema and was, until now, never written by gameplay.
  ///
  /// [announce] false evaluates silently: no notification queue, no
  /// listener broadcast — the load path's retro-award for achievements
  /// introduced by an app update. The awards still persist.
  void _evaluateAchievements({bool announce = true}) {
    final state = achievementState;
    var awardedAny = false;
    for (final def in AchievementCatalog.all) {
      if (isAchievementUnlocked(def.id)) continue;
      if (!def.isEarned(state)) continue;
      _saveData.achievements[def.id] = true;
      awardedAny = true;
      if (announce) _pendingAchievementUnlocks.add(def);
    }
    if (!awardedAny) return;
    if (announce) notifyListeners();
    save();
  }

  /// Every recorded ended shift, oldest first (issue #17). The raw,
  /// per-shift history; see [runStats] for the aggregates.
  List<RunRecord> get runHistory => List.unmodifiable(_runHistory);

  /// The shift history aggregated for tuning (issue #17): totals, medians,
  /// run-length distribution, bank-vs-push ratio. Since issue #183 the
  /// six totals read the save's lifetime counters — the window trims at
  /// [maxRecordedRuns], and totals folded over it freeze at 200 then fall
  /// — while the medians, the run-length bands and the bank-vs-push
  /// counts stay window-scoped, with [RunStats.runCount] the window's own
  /// size as their denominator.
  RunStats get runStats =>
      RunStats.compute(_runHistory, lifetime: _saveData.lifetimeRunTotals);

  /// Every completed Daily Shift, oldest first (issue #19) — the player's
  /// daily history. At most one result per day ever exists.
  List<DailyResult> get dailyHistory => List.unmodifiable(_dailyHistory);

  /// Today's completed Daily Shift, or null while today's is unplayed
  /// (issue #19). The menu's daily button branches on exactly this.
  DailyResult? get todayDailyResult {
    final today = DailyShift.todayKey;
    for (final result in _dailyHistory) {
      if (result.dateKey == today) return result;
    }
    return null;
  }

  /// True once today's Daily Shift has ended — the day's one attempt is
  /// spent, and the result stands until tomorrow's course arrives.
  bool get todayDailyComplete => todayDailyResult != null;

  /// The completed Daily Shift recorded for [dateKey], or null.
  DailyResult? dailyResultFor(String dateKey) {
    for (final result in _dailyHistory) {
      if (result.dateKey == dateKey) return result;
    }
    return null;
  }

  /// The stored ghost trace for the course of [dateKey], or null (issue
  /// #20). A trace only ever replays on the day's course it was
  /// recorded on — a ghost of a different road is meaningless.
  GhostTrace? ghostFor(String dateKey) {
    final ghost = _dailyGhost;
    if (ghost == null || ghost.dateKey != dateKey) return null;
    return ghost;
  }

  /// The stored ghost for today's course, or null (issue #20).
  GhostTrace? get todayGhost => ghostFor(DailyShift.todayKey);

  /// Offers a finished daily-course run's trace as the new ghost (issue
  /// #20). The rule is the personal-best rule scoped to the course: a
  /// trace is kept only if it scores strictly more than the stored one
  /// for the same day — a tie keeps the older ghost. The first trace
  /// offered for a *new* day replaces the previous day's outright,
  /// because that course (and its ghost) is gone for good.
  ///
  /// Returns true when the offer became the stored ghost. A run with no
  /// recorded path offers nothing. Strictly local, like every other
  /// record here.
  Future<bool> recordDailyGhostRun({
    required String dateKey,
    required int score,
    required bool banked,
    required String vehicleId,
    required List<int> samples,
  }) async {
    if (samples.isEmpty) return false;
    if (ghostFor(dateKey) != null && score <= ghostFor(dateKey)!.score) {
      return false;
    }
    _dailyGhost = GhostTrace(
      dateKey: dateKey,
      score: score,
      banked: banked,
      vehicleId: vehicleId,
      samples: samples,
    );
    notifyListeners();
    await _storageService.saveDailyGhost(_dailyGhost!);
    return true;
  }

  /// Load save data and the shift history from storage
  Future<void> loadSaveData() async {
    final data = await _storageService.loadSaveData();
    if (data != null) {
      _saveData = data;
    } else {
      // A corrupt (or absent) save is a fresh save (issue #218): the
      // history, the daily results, and the ghost left on disk describe
      // a save that no longer exists — the same progress a reset wipes —
      // and the migrations below used to seed phantom stats and awards
      // from that dead window and hand its ghost back. Clearing here, the
      // way [resetProgress] does, keeps the fresh save and the records
      // that leave with it in agreement; a first launch has nothing to
      // clear.
      _runHistory.clear();
      await _storageService.clearRunHistory();
      _dailyHistory.clear();
      await _storageService.clearDailyHistory();
      _dailyGhost = null;
      await _storageService.clearDailyGhost();
    }
    // A missing or corrupt history is a fresh one — the same recovery a
    // corrupt save gets, never a crash.
    final history = _storageService.loadRunHistory();
    if (history != null) {
      _runHistory
        ..clear()
        ..addAll(history);
    }
    final dailies = _storageService.loadDailyHistory();
    if (dailies != null) {
      _dailyHistory
        ..clear()
        ..addAll(dailies);
    }
    // The clean-bank counter's one-time migration (issue #55): saves
    // written before the counter existed have no number stored, and
    // their only record of clean banks is the history window. Seed the
    // lifetime counter with the larger of what is stored and what the
    // window holds, so a pre-fix save keeps every clean bank its window
    // still shows — and persist it immediately, before the window can
    // trim one out from under the seed. Post-migration saves always hold
    // the larger number, so this no-ops from then on. Only a loaded save
    // (no else above) has a window that belongs to it (issue #218).
    var migratedCleanBanks = false;
    // The lifetime totals' seed of the same shape (issue #183): a save
    // written before the totals block existed stores nothing, and its
    // only record of anything is the window. Each counter takes the
    // larger of what is stored and what the window holds — per field —
    // and the seed persists immediately, before the window can trim a
    // shift out from under it. Post-migration saves always hold the
    // larger number, so this no-ops from then on.
    var migratedTotals = false;
    // The personal-best maxima seed the same way (issue #247): the four
    // records are stored maxima too, and a save whose block predates (or
    // missed the write of) a window best used to keep the older number
    // while the history — and the menu's BEST line — still showed the
    // better shift. Per-field max, folded into the one migration write.
    var migratedPbs = false;
    if (data != null) {
      final windowCleanBanks = _runHistory
          .where((record) => record.banked && record.livesLost == 0)
          .length;
      if (windowCleanBanks > _saveData.personalBests.cleanBankedShifts) {
        _saveData.personalBests.cleanBankedShifts = windowCleanBanks;
        migratedCleanBanks = true;
      }
      migratedTotals = _saveData.lifetimeRunTotals.seedFromWindow(_runHistory);
      migratedPbs = _saveData.personalBests.seedFromWindow(_runHistory);
      // The ghost trace loads with everything else (issue #20); a missing
      // or corrupt one just means no ghost to race, never a crash.
      _dailyGhost = _storageService.loadDailyGhost();
    }
    // A save can silently deserve achievements it has never been given
    // (issue #21): this build ships awards an older build never knew
    // about. Retro-award them once, quietly — no unlock banner fires
    // from a load; the records screen simply shows them earned.
    _evaluateAchievements(announce: false);
    notifyListeners();
    if (migratedCleanBanks || migratedTotals || migratedPbs) await save();
  }

  /// True while [resetProgress]'s storage transaction is in flight
  /// (issue #246): mutator saves issued in that window must not encode the
  /// doomed old save and land behind the wipe.
  bool _resetInFlight = false;

  /// True once a [save] was requested inside the reset window; the reset
  /// flushes it — once — after the transaction settles.
  bool _saveRequestedDuringReset = false;

  /// Save current data to storage
  Future<void> save() async {
    if (_resetInFlight) {
      // A save issued while the reset transaction runs (issue #246) is
      // deferred, not encoded: writing the current `_saveData` now would
      // queue a snapshot behind the wipe — and before the fix that
      // snapshot was the old save, resurrecting wiped progress on the
      // next launch. The reset flushes one deferred save when it settles,
      // so a settings toggle made mid-window still reaches the disk.
      _saveRequestedDuringReset = true;
      return;
    }
    await _storageService.saveSaveData(_saveData);
  }

  /// Runs one deferred [save] if a write was requested while the reset
  /// transaction was in flight; the reset calls this on both of its exits.
  /// A false answer from [save]'s storage queue is ignored, like every
  /// other mutator write: the durable state is the reset's own business.
  Future<void> _flushDeferredSave() async {
    if (!_saveRequestedDuringReset) return;
    _saveRequestedDuringReset = false;
    await save();
  }
  
  /// Add coins to player's total
  void addCoins(int amount) {
    _saveData.totalCoins += amount;
    notifyListeners();
    save();
  }
  
  /// Spend coins (returns true if successful)
  bool spendCoins(int amount) {
    if (_saveData.totalCoins >= amount) {
      _saveData.totalCoins -= amount;
      notifyListeners();
      save();
      return true;
    }
    return false;
  }
  
  /// Complete a level: award coins and, if it was the player's furthest
  /// level, unlock the next one. Replaying an old level only earns coins.
  void completeLevel(int levelNumber, int coinsEarned) {
    addCoins(coinsEarned);
    if (levelNumber == _saveData.currentLevel) {
      _saveData.currentLevel++;
      notifyListeners();
      save();
    }
  }

  /// Records the score an endless shift just ended with against the
  /// personal best (issue #15). Returns true when [score] beats the
  /// stored best — a new PB — and stores it; a tie keeps the old best.
  /// The score counts however the shift ended: banked payouts and
  /// forfeited unbanked scores are both the number a replay tries to
  /// beat.
  bool recordEndlessScore(int score) {
    if (score <= _saveData.endlessBestScore) return false;
    _saveData.endlessBestScore = score;
    notifyListeners();
    save();
    return true;
  }

  /// Adds an ended shift to the on-device history (issue #17), trimming
  /// the oldest records past [maxRecordedRuns], and persists it. Strictly
  /// local — this is the game's only tuning instrument, and it never
  /// leaves the device.
  ///
  /// The same shift is folded into the lifetime records (issue #21)
  /// first — best banked score, longest chain, furthest distance, most
  /// fares — and into the lifetime totals (issue #183), the six monotone
  /// counters the stats screen's Totals read, before the window trim can
  /// age the shift out of any sum. The achievements are then evaluated
  /// against the new standing, because shift end is where every gameplay
  /// measure lands.
  /// The evaluation runs **before the first await**: the shift-end flow
  /// is fire-and-forget, and its very next synchronous step drains the
  /// unlock queue to build the run summary — so the queue must be filled
  /// before this method suspends on storage.
  Future<void> recordEndlessRun(RunRecord record) async {
    _saveData.personalBests.applyRun(
      score: record.score,
      banked: record.banked,
      longestChain: record.longestChain,
      distancePx: record.distancePx,
      faresDelivered: record.faresDelivered,
      livesLost: record.livesLost,
    );
    // The same shift folds into the lifetime totals (issue #183) — before
    // the window trim below, so a shift leaving the window can never take
    // itself back out of the totals. Every counter only moves up, and the
    // block lives in the save, so the save must reach the disk on every
    // recorded shift now, records improved or not.
    _saveData.lifetimeRunTotals.applyRun(record);
    _runHistory.add(record);
    if (_runHistory.length > maxRecordedRuns) {
      _runHistory.removeRange(0, _runHistory.length - maxRecordedRuns);
    }
    notifyListeners();
    _evaluateAchievements();
    await _storageService.saveRunHistory(_runHistory);
    await save();
  }

  /// Records a completed Daily Shift (issue #19) and persists it. One
  /// attempt per day is the rule, so the **first** result for a date is
  /// the one that counts: a later record for the same day is dropped, and
  /// no flow can overwrite a settled daily. Trims the oldest days past
  /// [maxRecordedDailyResults]. Strictly local — the shared course is
  /// derived from the date; nothing here is ever sent anywhere.
  ///
  /// The daily is also where a streak extends (issue #21), so the
  /// achievements are re-evaluated with the day in — before a shift-end
  /// evaluation could reach the same conclusion one call late. Like
  /// [recordEndlessRun], the evaluation precedes the first await: the
  /// caller drains the unlock queue synchronously right after this
  /// fire-and-forget call.
  Future<void> recordDailyResult(DailyResult result) async {
    if (dailyResultFor(result.dateKey) != null) return;
    _dailyHistory.add(result);
    if (_dailyHistory.length > maxRecordedDailyResults) {
      _dailyHistory.removeRange(
          0, _dailyHistory.length - maxRecordedDailyResults);
    }
    notifyListeners();
    _evaluateAchievements();
    await _storageService.saveDailyHistory(_dailyHistory);
  }
  
  /// Unlock a vehicle
  bool unlockVehicle(String vehicleId, int cost) {
    // Ownership is checked before the spend (issue #221): the spend used
    // to run first and a duplicate BUY — two taps inside one garage frame
    // — charged the same car twice, permanently. A repeat call now costs
    // nothing and reports true, the purchase it repeats.
    if (_saveData.unlockedVehicles.contains(vehicleId)) return true;
    if (_saveData.totalCoins < cost) return false;
    // The spend and the unlock are one transaction (issue #230): the old
    // path saved the spend through [spendCoins] and then the unlock in a
    // second save, so a kill between the two flushed writes could land
    // the charge without the car. Mutate both, then save once.
    _saveData.totalCoins -= cost;
    _saveData.unlockedVehicles.add(vehicleId);
    notifyListeners();
    // The garage is a gameplay event too (issue #21): cars-collected
    // achievements are evaluated the moment the fleet grows, so the
    // purchase that earned one can announce it — and the award (if any)
    // rides this save rather than a second one.
    _evaluateAchievements();
    save();
    return true;
  }
  
  /// Select a vehicle
  void selectVehicle(String vehicleId) {
    if (_saveData.unlockedVehicles.contains(vehicleId)) {
      _saveData.selectedVehicle = vehicleId;
      notifyListeners();
      save();
    }
  }
  
  /// Check if vehicle is unlocked
  bool isVehicleUnlocked(String vehicleId) {
    return _saveData.unlockedVehicles.contains(vehicleId);
  }
  
  /// Toggle sound
  void toggleSound() {
    _saveData.settings.soundEnabled = !_saveData.settings.soundEnabled;
    notifyListeners();
    save();
  }
  
  /// Toggle music
  void toggleMusic() {
    _saveData.settings.musicEnabled = !_saveData.settings.musicEnabled;
    notifyListeners();
    save();
  }

  /// Toggle vibration (issue #5). Notifies synchronously, so the
  /// composition root's listener flips the running haptics service's gate
  /// before the toggle's caller continues — an enabling tap can buzz its
  /// own confirmation, a disabling one goes out silently.
  void toggleVibration() {
    _saveData.settings.vibrationEnabled =
        !_saveData.settings.vibrationEnabled;
    notifyListeners();
    save();
  }

  /// True once the one-time stick-control hint (issue #37) has been
  /// dismissed for this save. The game screen reads this to decide
  /// whether a first game start still needs teaching.
  bool get controlHintDismissed => _saveData.controlHintDismissed;

  /// Dismisses the one-time stick-control hint (issue #37) and persists
  /// the dismissal immediately, so the flag is on disk before the next
  /// session renders its first frame — the hint can then never return
  /// for this save. Idempotent: a save that already dismissed it saves
  /// nothing and notifies nobody.
  void dismissControlHint() {
    if (_saveData.controlHintDismissed) return;
    _saveData.controlHintDismissed = true;
    notifyListeners();
    save();
  }

  /// True once this save has been offered a bank-or-push choice at least
  /// once. The first offer on a save stops traffic for the decision (the
  /// primer); the game reads this to decide whether an offer is a first.
  bool get bankPromptSeen => _saveData.bankPromptSeen;

  /// Marks the save as having seen the bank-or-push choice, and persists
  /// it immediately — the primer is once per save, ever. Idempotent,
  /// like [dismissControlHint].
  void markBankPromptSeen() {
    if (_saveData.bankPromptSeen) return;
    _saveData.bankPromptSeen = true;
    notifyListeners();
    save();
  }

  /// Reset all progress (for testing)
  ///
  /// The wipe is one storage transaction (issue #232): the three record
  /// keys and the fresh save move together inside a single queue entry
  /// that nothing else can slip into, and every step is retried before
  /// the transaction rolls the earlier removes back. The old shape
  /// awaited three separate clears, which left the reset half-applied in
  /// two ways: a run-history clear that landed stayed landed when a later
  /// clear failed (no rollback), and a fresh save whose both attempts
  /// failed was never inspected, so the reset returned with fresh memory
  /// and deleted records beside the old durable save.
  ///
  /// Memory swaps to the fresh save before the transaction and back to
  /// the old save on failure (issue #246): a save issued while the
  /// transaction runs must never encode the doomed old save and land
  /// behind the wipe, and mutator saves are deferred for the same reason
  /// — the transaction's own fresh-save write stays the last word, with
  /// one deferred flush after it so a settings toggle made mid-window
  /// still reaches the disk. A terminal failure therefore leaves the old,
  /// coherent save in memory and on disk, the abandoned reset logged,
  /// not applied.
  Future<void> resetProgress() async {
    // Single-flight (issue #246): a second reset confirmed while the first
    // transaction still runs was the one overlap the defer gate could not
    // cover — the second transaction queues behind the first, and a failed
    // first reset then restores and flushes the old save after the
    // second's fresh write, making the old progress the last word on disk.
    // A reset of a save already being wiped has nothing left to do, so a
    // second call is refused while one is in flight.
    if (_resetInFlight) return;
    // Settings are preference, not progress (issue #83): the whole
    // Settings block — the three toggles and both volumes — rides over
    // to the fresh save, not just the booleans a bug report names. A
    // reset that restored the defaults would flip sound, music, and
    // vibration back on under a player who had turned them off, and the
    // notifyListeners below would then hand `true` to the composition
    // root's audio listener — starting the menu music mid-dialog-
    // dismissal. Built before the transaction; applied via the cascade
    // because `createDefault` takes no settings override.
    final freshSave = SaveData.createDefault()..settings = _saveData.settings;
    // Memory swaps to the fresh save *before* the transaction (issue
    // #246): a mutator save issued while the transaction runs must encode
    // the fresh save, never the one being wiped. Under the old shape the
    // save called here in the window still pointed at the old data, so it
    // queued behind the transaction and resurrected the wiped progress on
    // the next launch. A failed transaction puts the old object back.
    final previousSave = _saveData;
    _saveData = freshSave;
    // The transaction writes the fresh save itself (issue #232): a
    // separate save() after it would be the second entry the reservation
    // exists to prevent. Saves issued mid-transaction are deferred by the
    // gate in [save] so the reset's own write stays the last word; the
    // deferred flush below runs after it.
    _resetInFlight = true;
    final landed = await _storageService.resetAll(freshSave);
    _resetInFlight = false;
    if (!landed) {
      _saveData = previousSave;
      // The restore is a state change the UI may already have painted over
      // from the temporary fresh save (a mid-window toggle rebuilds the
      // settings card): notify so the screens show the save that survived.
      notifyListeners();
      // A save deferred in the window is not lost with the abandoned
      // reset: with the old save back in memory, flushing persists it —
      // a mid-reset settings toggle included (the two saves share the
      // same Settings object) — without writing the fresh save the
      // rollback just undid.
      await _flushDeferredSave();
      Diagnostics.instance.logError(
        'reset',
        StateError('reset abandoned: the storage transaction did not land'),
        StackTrace.current,
      );
      return;
    }
    // The wipe has fully landed; only now do the records swap with the
    // fresh save. The fresh save also un-dismisses the stick-control
    // hint (issue #37): a wiped save is a first-time player again, and
    // the next game start teaches the stick once more.
    // The shift history is progress too (issue #17): a reset wipes it with
    // everything else, so the stats screen never shows numbers from a run
    // of a save that no longer exists.
    _runHistory.clear();
    // The daily history is the same kind of progress (issue #19): a reset
    // wipes it, and today's course becomes playable again.
    _dailyHistory.clear();
    // The ghost is progress too (issue #20): a reset takes the stored
    // best run with everything else.
    _dailyGhost = null;
    // The records and achievements are progress like everything else
    // (issue #21): the fresh save has empty records and an empty
    // achievements map, and any unlock still queued to be announced dies
    // with the save that earned it.
    _pendingAchievementUnlocks.clear();
    notifyListeners();
    // Whatever save was requested inside the window rides last — after
    // the transaction's own fresh-save write — and still carries fresh
    // data, never the old save (issue #246).
    await _flushDeferredSave();
  }
}
