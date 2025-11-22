import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../components/player_vehicle.dart';

/// Handles touch input and controls the player vehicle
class InputController extends Component with TapCallbacks {
  final PlayerVehicle player;
  
  InputController(this.player);
  
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    player.startAccelerating();
  }
  
  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    player.stopAccelerating();
  }
  
  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    player.stopAccelerating();
  }
  
  @override
  void onLongTapDown(TapDownEvent event) {
    super.onLongTapDown(event);
    // Long press is same as regular tap for this game
    player.startAccelerating();
  }
}
