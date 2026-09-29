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
        cleanBankedShifts: _runHistory
            .where((record) => record.banked && record.livesLost == 0)
            .length,
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
  /// run-length distribution, bank-vs-push ratio.
  RunStats get runStats => RunStats.compute(_runHistory);

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
    // The ghost trace loads with everything else (issue #20); a missing
    // or corrupt one just means no ghost to race, never a crash.
    _dailyGhost = _storageService.loadDailyGhost();
    // A save can silently deserve achievements it has never been given
    // (issue #21): this build ships awards an older build never knew
    // about. Retro-award them once, quietly — no unlock banner fires
    // from a load; the records screen simply shows them earned.
    _evaluateAchievements(announce: false);
    notifyListeners();
  }

  /// Save current data to storage
  Future<void> save() async {
    await _storageService.saveSaveData(_saveData);
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
  /// fares — and the achievements are then evaluated against the new
  /// standing, because shift end is where every gameplay measure lands.
  /// The evaluation runs **before the first await**: the shift-end flow
  /// is fire-and-forget, and its very next synchronous step drains the
  /// unlock queue to build the run summary — so the queue must be filled
  /// before this method suspends on storage.
  Future<void> recordEndlessRun(RunRecord record) async {
    final recordsImproved = _saveData.personalBests.applyRun(
      score: record.score,
      banked: record.banked,
      longestChain: record.longestChain,
      distancePx: record.distancePx,
      faresDelivered: record.faresDelivered,
    );
    _runHistory.add(record);
    if (_runHistory.length > maxRecordedRuns) {
      _runHistory.removeRange(0, _runHistory.length - maxRecordedRuns);
    }
    notifyListeners();
    _evaluateAchievements();
    await _storageService.saveRunHistory(_runHistory);
    // A record-setting shift must reach the disk even when it earns no
    // achievement — the records live in the save, not the history.
    if (recordsImproved) await save();
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
    if (spendCoins(cost)) {
      if (!_saveData.unlockedVehicles.contains(vehicleId)) {
        _saveData.unlockedVehicles.add(vehicleId);
        notifyListeners();
        save();
        // The garage is a gameplay event too (issue #21): cars-collected
        // achievements are evaluated the moment the fleet grows, so the
        // purchase that earned one can announce it.
        _evaluateAchievements();
      }
      return true;
    }
    return false;
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
  void resetProgress() {
    // The fresh save also un-dismisses the stick-control hint (issue
    // #37): a wiped save is a first-time player again, and the next
    // game start teaches the stick once more — the same convention as
    // the run history below.
    _saveData = SaveData.createDefault();
    // The shift history is progress too (issue #17): a reset wipes it with
    // everything else, so the stats screen never shows numbers from a run
    // of a save that no longer exists.
    _runHistory.clear();
    _storageService.clearRunHistory();
    // The daily history is the same kind of progress (issue #19): a reset
    // wipes it, and today's course becomes playable again.
    _dailyHistory.clear();
    _storageService.clearDailyHistory();
    // The ghost is progress too (issue #20): a reset takes the stored
    // best run with everything else.
    _dailyGhost = null;
    _storageService.clearDailyGhost();
    // The records and achievements are progress like everything else
    // (issue #21): the fresh save has empty records and an empty
    // achievements map, and any unlock still queued to be announced dies
    // with the save that earned it.
    _pendingAchievementUnlocks.clear();
    notifyListeners();
    save();
  }
}
