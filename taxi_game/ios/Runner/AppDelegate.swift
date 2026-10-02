import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Issue #168 — the UIScene lifecycle iOS 27 requires. The engine now
  // initializes before any scene (or window) exists, so everything that
  // used to reach into the engine at launch moves to this hook, on the
  // bridge the engine hands over — the same shape as the tool's own
  // migration and the official guide.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Issue #22 — the score card share sheet. The app's only outbound
    // path: a UIActivityViewController the user drives themselves, over a
    // card the game just rendered. No plugin, no SDK, no network — the
    // zero-network claim (PrivacyInfo.xcprivacy) is untouched by design.
    let channel = FlutterMethodChannel(
      name: "cab_hustle/share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "shareScoreCard":
        self?.handleShareScoreCard(call, result: result)
      case "shareText":
        self?.handleShareText(call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The root view controller of the foreground scene's key window. Under
  /// the UIScene lifecycle (issue #168) the app delegate no longer owns a
  /// window — the scene does — so the old `window?.rootViewController`
  /// reads nil and the share sheet would have nowhere to present from.
  /// The 15.0 deployment target puts UIWindowScene.keyWindow on every OS
  /// the app installs on.
  private func foregroundRootViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
      .flatMap { $0.keyWindow?.rootViewController }
  }

  /// Validates the call, then presents the sheet on the main thread.
  /// Arguments: `png` (Uint8List, required), `text` (String, optional).
  private func handleShareScoreCard(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let args = call.arguments as? [String: Any],
      let typedData = args["png"] as? FlutterStandardTypedData
    else {
      result(FlutterError(
        code: "bad_arguments",
        message: "shareScoreCard needs PNG bytes under 'png'",
        details: nil))
      return
    }
    let text = args["text"] as? String

    DispatchQueue.main.async { [weak self] in
      self?.presentScoreCardShare(png: typedData.data, text: text, result: result)
    }
  }

  /// Stages the card in the app's tmp directory — local disk only — and
  /// presents the share sheet over the topmost view controller.
  private func presentScoreCardShare(
    png: Data,
    text: String?,
    result: @escaping FlutterResult
  ) {
    guard let root = foregroundRootViewController() else {
      result(FlutterError(
        code: "not_ready",
        message: "No root view controller to present the share sheet from",
        details: nil))
      return
    }

    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("score_cards", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let stamp = Int(Date().timeIntervalSince1970 * 1000)
      let fileURL = dir.appendingPathComponent("cab-hustle-score-\(stamp).png")
      try png.write(to: fileURL)

      var items: [Any] = [fileURL]
      if let text = text { items.append(text) }
      let sheet = UIActivityViewController(
        activityItems: items, applicationActivities: nil)

      // One staged file per share; prune all but the newest few so tmp
      // stays bounded.
      pruneStagedCards(in: dir, keeping: 5)

      // The completion can arrive off the main queue; FlutterResult must
      // be called on the platform thread.
      sheet.completionWithItemsHandler = { _, _, _, _ in
        DispatchQueue.main.async { result(nil) }
      }

      // iPhone-only app; the popover plumbing only exists so the
      // presentation rules never reject the sheet in another idiom.
      if let popover = sheet.popoverPresentationController, let view = root.view {
        popover.sourceView = view
        popover.sourceRect = CGRect(
          x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }

      var top = root
      while let presented = top.presentedViewController { top = presented }
      top.present(sheet, animated: true)
    } catch {
      result(FlutterError(
        code: "stage_failed",
        message: "Could not stage the score card: \(error.localizedDescription)",
        details: nil))
    }
  }

  /// Shares plain text — the diagnostics export. The same rules as the
  /// score card: a UIActivityViewController the user drives themselves,
  /// no file staging needed because there is no file.
  private func handleShareText(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let args = call.arguments as? [String: Any],
      let text = args["text"] as? String
    else {
      result(FlutterError(
        code: "bad_arguments",
        message: "shareText needs a String under 'text'",
        details: nil))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let this = self, let root = this.foregroundRootViewController() else {
        result(FlutterError(
          code: "not_ready",
          message: "No root view controller to present the share sheet from",
          details: nil))
        return
      }
      let sheet = UIActivityViewController(
        activityItems: [text], applicationActivities: nil)
      sheet.completionWithItemsHandler = { _, _, _, _ in
        DispatchQueue.main.async { result(nil) }
      }
      if let popover = sheet.popoverPresentationController, let view = root.view {
        popover.sourceView = view
        popover.sourceRect = CGRect(
          x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      var top = root
      while let presented = top.presentedViewController { top = presented }
      top.present(sheet, animated: true)
    }
  }

  /// Deletes the oldest staged cards past [keep].
  private func pruneStagedCards(in dir: URL, keeping keep: Int) {
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return }
    let sorted = files
      .filter { $0.pathExtension.caseInsensitiveCompare("png") == .orderedSame }
      .sorted { a, b in
        let dateOf: (URL) -> Date = { url in
          (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
        }
        return dateOf(a) > dateOf(b)
      }
    for stale in sorted.dropFirst(keep) {
      try? FileManager.default.removeItem(at: stale)
    }
  }
}
