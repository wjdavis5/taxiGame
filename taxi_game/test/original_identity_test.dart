import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The originality guard: no shipped surface may carry another game's
/// identity, a template scaffold, or a placeholder identity.
///
/// Cab Hustle was rejected under Guideline 4.3(a) (Design - Spam) after a
/// review that read it as another taxi-game look-alike. The review-notes
/// guard (issue #211) makes every submission state what is original; this
/// suite keeps the surfaces a reviewer can inspect free of the opposite.
/// Scanned: `lib/`, `ios/`, `assets/`, `fastlane/`, and `pubspec.yaml` —
/// what ships in the bundle or rides with the submission. Repo-only
/// documents are deliberately out of scope: history may name what it must,
/// and this test file itself names the denied tokens.
void main() {
  // Tight on purpose: names of other games/publishers that must never leak
  // into a shipped surface, plus Flutter scaffold identities.
  const denied = <String>[
    'pick me up',
    'pickmeup',
    'pmu3d',
    'voodoo',
    'crazy taxi',
    'traffic rider',
    'smashy road',
    'dr. driving',
    'crossy road',
    'com.example',
    'a new flutter project',
    'flutter_application',
  ];

  // Text formats only; the same trees hold PNG/WAV bytes that would match
  // anything.
  const textExtensions = <String>[
    '.dart', '.yaml', '.yml', '.txt', '.md', '.json', '.plist', '.swift',
    '.h', '.m', '.storyboard', '.xib', '.strings', '.xcprivacy',
    '.entitlements', '.html', '.js', '.css', '.gradle', '.kts', '.xml',
  ];

  // Build products and dependency checkouts are not part of the repo's
  // shipped surface (and CocoaPods brings thousands of files of its own).
  final skippedSegments = <String>[
    '${Platform.pathSeparator}Pods${Platform.pathSeparator}',
    '${Platform.pathSeparator}.symlinks${Platform.pathSeparator}',
    '${Platform.pathSeparator}ephemeral${Platform.pathSeparator}',
    '${Platform.pathSeparator}build${Platform.pathSeparator}',
    '${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}',
  ];

  List<File> surfaceFiles(String root, {bool allText = false}) {
    final dir = Directory(root);
    expect(dir.existsSync(), isTrue, reason: 'missing shipped surface $root');
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final path = file.path;
          if (skippedSegments.any(path.contains)) {
            return false;
          }
          if (allText) {
            return true;
          }
          return textExtensions
              .any((ext) => path.toLowerCase().endsWith(ext));
        })
        .toList();
  }

  test("no shipped surface carries another game's or a template's identity",
      () {
    final files = <File>[
      ...surfaceFiles('lib'),
      ...surfaceFiles('ios'),
      ...surfaceFiles('assets'),
      // Fastfile and Appfile carry no extension; the lane is all text.
      ...surfaceFiles('fastlane', allText: true),
      File('pubspec.yaml'),
    ];

    final violations = <String>[];
    for (final file in files) {
      final text = file.readAsStringSync().toLowerCase();
      for (final token in denied) {
        if (text.contains(token)) {
          violations.add('${file.path}: $token');
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'shipped surfaces must not carry template or third-party '
            'identity — the 4.3(a) originality guard (issue #214). '
            'Violations:\n${violations.join('\n')}');
  });

  test('every surface the guard scans still exists', () {
    // A rename that moves a shipped tree must not silently shrink the guard.
    expect(File('pubspec.yaml').existsSync(), isTrue);
    expect(Directory('lib').existsSync(), isTrue);
    expect(Directory('ios').existsSync(), isTrue);
    expect(Directory('assets').existsSync(), isTrue);
    expect(Directory('fastlane').existsSync(), isTrue);
  });
}
