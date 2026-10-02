import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS UIScene adoption (issue #168).
///
/// iOS 27 requires the UIScene lifecycle, and Flutter's toolchain says so
/// — but the automatic migration only rewrites an AppDelegate that byte-
/// matches one of its stock templates (uiscene_migration.dart's
/// `originalSwiftAppDelegateTemplates`), and this app's delegate has
/// carried the `cab_hustle/share` channel since issue #22, so the tool
/// skipped it and the migration was done by hand, along the tool's own
/// shape:
///
/// - Info.plist gained the exact UIApplicationSceneManifest the tool
///   inserts for a customised app, naming the framework's
///   `FlutterSceneDelegate` directly — no SceneDelegate class of ours, so
///   no project.pbxproj edit and no $(PRODUCT_MODULE_NAME) spelling.
/// - AppDelegate conforms to FlutterImplicitEngineDelegate: plugin
///   registration and the share channel moved into
///   `didInitializeImplicitFlutterEngine`, on the bridge's registrars (the
///   engine initializes before any scene exists, so the old
///   didFinishLaunching reach-ins had nothing to hold).
/// - Both `window?.rootViewController` reads became a foreground-scene
///   keyWindow lookup: under scenes the app delegate owns no window.
/// - PR CI boots a simulator, installs the built app, launches it, and
///   asserts the process is alive — a broken scene adoption dies at
///   launch, before any test could run.
///
/// None of this compiles or runs on the dev boxes or the analyze/test
/// jobs: Swift and the plist only meet a compiler in CI's macOS build,
/// and the true human gate — launch the app, open the share sheet from
/// SHARE SCORE and from Settings — still applies before shipping. These
/// pins keep the *structure* from regressing the way the sweep-script
/// and asc.rb suites pin theirs.
void main() {
  // flutter test runs from the package directory; the iOS files and the
  // workflow live one level up. The in-repo fallback covers running from
  // the repo root.
  String readRepoFile(String path) {
    for (final candidate in ['../$path', path]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }
    fail('could not find $path relative to ${Directory.current.path}');
  }

  /// Raw bytes, so the CRLF pins judge the file as committed rather than
  /// through any reader that might translate endings.
  List<int> readRepoBytes(String path) {
    for (final candidate in ['../$path', path]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file.readAsBytesSync();
      }
    }
    fail('could not find $path relative to ${Directory.current.path}');
  }

  final infoPlist = readRepoFile('taxi_game/ios/Runner/Info.plist');
  final appDelegate = readRepoFile('taxi_game/ios/Runner/AppDelegate.swift');
  final builds = readRepoFile('.github/workflows/flutter-builds.yml');

  group('Info.plist adopts the UIScene lifecycle the tool would insert '
      '(issue #168)', () {
    test('the scene manifest names the framework delegate, exactly', () {
      // The tool's insert for a customised app (uiscene_migration.dart)
      // names FlutterSceneDelegate directly — the
      // $(PRODUCT_MODULE_NAME).SceneDelegate spelling belongs to the
      // fresh-app template and implies a SceneDelegate.swift this repo
      // does not ship (and a project.pbxproj edit nobody made).
      expect(infoPlist, contains('<key>UIApplicationSceneManifest</key>'));
      expect(
          infoPlist,
          contains('<string>FlutterSceneDelegate</string>'),
          reason: 'the delegate class must be the framework\'s own — no '
              'SceneDelegate.swift exists in this repo');
      expect(infoPlist, isNot(contains('\$(PRODUCT_MODULE_NAME).Scene')),
          reason: 'that spelling needs a SceneDelegate class the app never '
              'compiled');

      // One window-scene configuration on the Main storyboard the app
      // already shipped; the manifest without the storyboard key loses
      // the launch interface.
      expect(infoPlist, contains('<key>UISceneClassName</key>'));
      expect(infoPlist, contains('<string>UIWindowScene</string>'));
      expect(infoPlist, contains('<key>UISceneConfigurationName</key>'));
      expect(infoPlist, contains('<string>flutter</string>'));
      expect(infoPlist, contains('<key>UISceneStoryboardFile</key>'));
      expect(infoPlist, contains('<key>UIWindowSceneSessionRoleApplication</key>'));

      // iPhone app, one scene: multiple scenes were never supported and
      // enabling them now would be a behavior change, not a migration.
      expect(infoPlist, contains('<key>UIApplicationSupportsMultipleScenes</key>'));
      expect(
          RegExp('UIApplicationSupportsMultipleScenes</key>\r?\n\t*<false/>')
              .hasMatch(infoPlist),
          isTrue,
          reason: 'the manifest must decline multiple scenes explicitly');
    });
  });

  group('AppDelegate rides the implicit engine (issue #168)', () {
    test('conforms to FlutterImplicitEngineDelegate and registers there', () {
      expect(appDelegate,
          contains('FlutterAppDelegate, FlutterImplicitEngineDelegate'));
      expect(appDelegate,
          contains('func didInitializeImplicitFlutterEngine('));
      expect(
          appDelegate,
          contains(
              'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)'),
          reason: 'plugins register on the bridge the engine hands over — '
              'the engine initializes before any scene exists');
    });

    test('the share channel moved to the bridge registrar and survived',
        () {
      // Issue #22's channel must come through the migration intact: same
      // name, handler switch, and a messenger that exists at
      // engine-initialization time — the engine's applicationRegistrar,
      // not a view controller (there is no view controller yet).
      expect(appDelegate, contains('name: "cab_hustle/share"'));
      expect(appDelegate,
          contains('binaryMessenger: engineBridge.applicationRegistrar.messenger())'));
      expect(appDelegate, contains('case "shareScoreCard":'));
      expect(appDelegate, contains('case "shareText":'));
      expect(appDelegate,
          isNot(contains('FlutterViewController')),
          reason: 'the old launch-time lookup grabbed a view controller '
              'that no longer exists at engine-init time');
    });

    test('no code path still reads the app delegate\'s window', () {
      // Under scenes the delegate owns no window, so every
      // `window?.rootViewController` read returns nil — the share sheet
      // would silently die on the not_ready error. The doc comment may
      // name the old spelling when explaining this; code may not use it.
      final code = appDelegate
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('window?.rootViewController')),
          reason: 'the scene lookup must replace every window read');
      expect(code, contains('foregroundRootViewController()'),
          reason: 'the share sheet presents from the foreground scene\'s '
              'key window');
    });
  });

  group('PR CI launches the app it builds (issue #168)', () {
    test('the iOS job builds for a simulator and asserts the process lives',
        () {
      // Compile-only checks cannot catch a launch-time death, and the
      // scene adoption is exactly a launch-time change. The step's pieces
      // are pinned individually so a partial edit (build but no launch,
      // launch but no liveness check) fails here.
      expect(builds, contains('flutter build ios --simulator --debug'));
      expect(builds, contains('xcrun simctl boot'));
      expect(builds, contains('xcrun simctl bootstatus'));
      expect(builds, contains('xcrun simctl install'));
      expect(builds, contains('xcrun simctl launch'));
      expect(builds, contains('com.wjdavis5.taxigame'),
          reason: 'the launch must target the shipping bundle id');
      expect(builds, contains('ps -p "\$pid"'),
          reason: 'liveness is asserted from the host, where the app '
              'process runs');
      expect(builds, contains('UIScene adoption is broken'),
          reason: 'the failure message must name what the step guards');
    });
  });

  group('the two edited iOS files keep their CRLF endings', () {
    // CLAUDE.md: project.pbxproj and Info.plist use CRLF, and a script
    // that rewrites newlines turns a small change into a repo-wide diff.
    // AppDelegate.swift is committed CRLF the same way. A checkout keeps
    // the committed bytes (no gitattributes normalize them), so the pin
    // holds on every platform the suite runs on.
    test('Info.plist and AppDelegate.swift are CRLF throughout', () {
      for (final path in [
        'taxi_game/ios/Runner/Info.plist',
        'taxi_game/ios/Runner/AppDelegate.swift',
      ]) {
        final raw = readRepoBytes(path);
        expect(raw, contains(13),
            reason: '$path must keep its CR bytes (CRLF endings)');
        // A bare LF (10) not preceded by CR is the mixed-ending signature
        // of a script that rewrote the file.
        var bareLf = 0;
        for (var i = 0; i < raw.length; i++) {
          if (raw[i] == 10 && (i == 0 || raw[i - 1] != 13)) bareLf++;
        }
        expect(bareLf, 0,
            reason: '$path must not mix bare LF into CRLF endings '
                '($bareLf found)');
      }
    });
  });
}
