/// Save data model that persists player progress
class SaveData {
  int currentLevel;
  int totalCoins;
  int totalGems;
  List<String> unlockedVehicles;
  String selectedVehicle;
  Map<String, bool> achievements;
  Settings settings;
  
  SaveData({
    required this.currentLevel,
    required this.totalCoins,
    required this.totalGems,
    required this.unlockedVehicles,
    required this.selectedVehicle,
    required this.achievements,
    required this.settings,
  });
  
  /// Create default save data for new players
  factory SaveData.createDefault() {
    return SaveData(
      currentLevel: 1,
      totalCoins: 0,
      totalGems: 0,
      unlockedVehicles: ['taxi_yellow'], // Default vehicle
      selectedVehicle: 'taxi_yellow',
      achievements: {},
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
