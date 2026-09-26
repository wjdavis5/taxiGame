import 'package:flutter/services.dart';

/// Hands a rendered score card to the OS share sheet (issue #22).
///
/// The zero-network claim stays intact by construction: this is a plain
/// [MethodChannel] to the app's own `AppDelegate` — no plugin, no SDK,
/// nothing that ships code beyond a `UIActivityViewController` the user
/// drives themselves. The PNG bytes and the share text go over; the
/// native side stages the bytes in the app's tmp directory and presents
/// the sheet. Nothing is transmitted unless the player picks a
/// destination, and then it is the OS doing it, not the app.
class ShareService {
  const ShareService();

  /// The channel the iOS `AppDelegate` registers a handler for. A platform
  /// without a handler raises [MissingPluginException] — the caller is
  /// expected to catch it, which is also what keeps the button honest on
  /// platforms that were never given the native side.
  static const MethodChannel channel = MethodChannel('cab_hustle/share');

  /// Presents the share sheet for [png] with [text] as the accompanying
  /// message. Completes when the sheet is dismissed (not when a
  /// destination finishes anything).
  Future<void> shareScoreCard({
    required Uint8List png,
    required String text,
  }) {
    return channel.invokeMethod<void>('shareScoreCard', {
      'png': png,
      'text': text,
    });
  }
}
