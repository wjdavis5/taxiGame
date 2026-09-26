import 'package:flame/components.dart';

import 'fare_type.dart';

/// Represents a passenger to be picked up and dropped off
class PassengerData {
  final String id;
  final Vector2 pickupLocation;
  final Vector2 dropoffLocation;
  final int reward;

  /// What kind of fare this is (issue #25): a plain ride, a VIP on a
  /// tight clock, a long-haul that boosts the chain, or an awkward
  /// far-side crossing. Defaults to standard, so hand-made levels and any
  /// data written before the types existed read as the everyday fare.
  final FareType fareType;

  bool isPickedUp;
  bool isDelivered;

  PassengerData({
    required this.id,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.reward,
    this.fareType = FareType.standard,
    this.isPickedUp = false,
    this.isDelivered = false,
  });

  /// Create from JSON
  factory PassengerData.fromJson(Map<String, dynamic> json) {
    return PassengerData(
      id: json['id'] as String,
      pickupLocation: Vector2(
        (json['pickupLocation'][0] as num).toDouble(),
        (json['pickupLocation'][1] as num).toDouble(),
      ),
      dropoffLocation: Vector2(
        (json['dropoffLocation'][0] as num).toDouble(),
        (json['dropoffLocation'][1] as num).toDouble(),
      ),
      reward: json['reward'] as int,
      // Fares written before the types existed are the everyday ride they
      // were generated as.
      fareType: json['fareType'] == null
          ? FareType.standard
          : FareType.values.byName(json['fareType'] as String),
      isPickedUp: json['isPickedUp'] as bool? ?? false,
      isDelivered: json['isDelivered'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pickupLocation': [pickupLocation.x, pickupLocation.y],
      'dropoffLocation': [dropoffLocation.x, dropoffLocation.y],
      'reward': reward,
      'fareType': fareType.name,
      'isPickedUp': isPickedUp,
      'isDelivered': isDelivered,
    };
  }

  /// Create a copy with updated values
  PassengerData copyWith({
    String? id,
    Vector2? pickupLocation,
    Vector2? dropoffLocation,
    int? reward,
    FareType? fareType,
    bool? isPickedUp,
    bool? isDelivered,
  }) {
    return PassengerData(
      id: id ?? this.id,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      reward: reward ?? this.reward,
      fareType: fareType ?? this.fareType,
      isPickedUp: isPickedUp ?? this.isPickedUp,
      isDelivered: isDelivered ?? this.isDelivered,
    );
  }
}
