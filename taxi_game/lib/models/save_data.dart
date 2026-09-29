import 'personal_bests.dart';

/// Save data model that persists player progress
class SaveData {
  int currentLevel;
  int totalCoins;
  int totalGems;
  List<String> unlockedVehicles;
  String selectedVehicle;

  /// Achievements the player has earned (issue #21), keyed by the
  /// achievement catalog's stable ids. Written by the achievement
  /// evaluation in `GameStateService` — an id present with `true` is
  /// earned, forever: achievements are never revoked, only reset with
  /// the whole save.
  Map<String, bool> achievements;

  /// The player's lifetime records (issue #21): best banked score,
  /// longest chain, furthest distance, most fares in one shift.
  PersonalBests personalBests;

  /// The best score any endless shift has ever ended with, banked or
  /// forfeited (issue #15). Compared against at every shift end.
  int endlessBestScore;

  /// True once the one-time stick-control hint (issue #37) has been
  /// dismissed — by the thumb landing on the stick, never by time or by a
  /// session ending — so the game must never render it again. Only a
  /// fresh save (or an explicit reset) leaves it false.
  bool controlHintDismissed;

  /// True once the save has been offered a bank-or-push choice at least
  /// once. The **first** offer on a save stops traffic for the decision
  /// (the primer): the choice is the game's core gamble, and it deserves
  /// one calm, readable introduction before it starts arriving mid-drive
  /// on a five-second clock. Every later offer rides live traffic, as
  /// designed. Same convention as [controlHintDismissed]: only a fresh
  /// save (or an explicit reset) leaves it false.
  bool bankPromptSeen;
  Settings settings;

  SaveData({
    required this.currentLevel,
    required this.totalCoins,
    required this.totalGems,
    required this.unlockedVehicles,
    required this.selectedVehicle,
    required this.achievements,
    this.endlessBestScore = 0,
    this.controlHintDismissed = false,
    this.bankPromptSeen = false,
    PersonalBests? personalBests,
    required this.settings,
  }) : personalBests = personalBests ?? PersonalBests();

  /// Create default save data for new players
  factory SaveData.createDefault() {
    return SaveData(
      currentLevel: 1,
      totalCoins: 0,
      totalGems: 0,
      unlockedVehicles: ['taxi_yellow'], // Default vehicle
      selectedVehicle: 'taxi_yellow',
      achievements: {},
      endlessBestScore: 0,
      settings: Settings.createDefault(),
    );
  }

  /// Load from JSON
  factory SaveData.fromJson(Map<String, dynamic> json) {
    return SaveData(
      currentLevel: json['currentLevel'] as int,
      totalCoins: json['totalCoins'] as int,
      totalGems: json['totalGems'] as int,
      unlockedVehicles: List<String>.from(json['unlockedVehicles'] as List),
      selectedVehicle: json['selectedVehicle'] as String,
      achievements: Map<String, bool>.from(json['achievements'] as Map),
      // Saves written before issue #15 have no best score yet; a missing
      // key means "no shift has ever ended", not a corrupt save.
      endlessBestScore: (json['endlessBestScore'] as int?) ?? 0,
      // Saves written before issue #21 have no records block yet; a
      // missing key means "nothing recorded", not a corrupt save.
      personalBests: json['personalBests'] == null
          ? PersonalBests()
          : PersonalBests.fromJson(
              json['personalBests'] as Map<String, dynamic>),
      // Saves written before issue #37 have no hint flag at all — and a
      // save that exists at all means its player has already driven.
      // A missing key therefore reads as dismissed: the stick hint is
      // for players a first game start can still teach, and a seasoned
      // save is never shown it. Fresh saves carry the key with false,
      // which round-trips below.
      controlHintDismissed:
          (json['controlHintDismissed'] as bool?) ?? true,
      // Saves written before the primer existed have already been
      // offered the choice — a missing key reads as seen, exactly like
      // the control-hint flag above it. Fresh saves carry the key with
      // false, which round-trips below.
      bankPromptSeen: (json['bankPromptSeen'] as bool?) ?? true,
      settings: Settings.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'currentLevel': currentLevel,
      'totalCoins': totalCoins,
      'totalGems': totalGems,
      'unlockedVehicles': unlockedVehicles,
      'selectedVehicle': selectedVehicle,
      'achievements': achievements,
      'endlessBestScore': endlessBestScore,
      'controlHintDismissed': controlHintDismissed,
      'bankPromptSeen': bankPromptSeen,
      'personalBests': personalBests.toJson(),
      'settings': settings.toJson(),
    };
  }
}

/// Game settings
class Settings {
  bool soundEnabled;
  bool musicEnabled;
  bool vibrationEnabled;
  double musicVolume;
  double sfxVolume;
  
  Settings({
    required this.soundEnabled,
    required this.musicEnabled,
    required this.vibrationEnabled,
    required this.musicVolume,
    required this.sfxVolume,
  });
  
  factory Settings.createDefault() {
    return Settings(
      soundEnabled: true,
      musicEnabled: true,
      vibrationEnabled: true,
      musicVolume: 0.7,
      sfxVolume: 0.8,
    );
  }
  
  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      soundEnabled: json['soundEnabled'] as bool,
      musicEnabled: json['musicEnabled'] as bool,
      vibrationEnabled: json['vibrationEnabled'] as bool,
      musicVolume: (json['musicVolume'] as num).toDouble(),
      sfxVolume: (json['sfxVolume'] as num).toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'soundEnabled': soundEnabled,
      'musicEnabled': musicEnabled,
      'vibrationEnabled': vibrationEnabled,
      'musicVolume': musicVolume,
      'sfxVolume': sfxVolume,
    };
  }
}
