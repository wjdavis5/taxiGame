import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The 4.3(a) guard (issue #211): every App Store submission must carry the
/// app's differentiation statement for App Review.
///
/// Apple rejected Cab Hustle 1.0.0 (1068) under Guideline 4.3(a) (Design -
/// Spam) — "the app shares a similar binary, metadata, and/or concept as
/// apps submitted to the App Store by other developers" — after a review
/// that never saw a word about what makes this game its own. Three things
/// are pinned here so that cannot recur silently: the statement file is
/// present, non-empty, within Apple's field cap, and never names another
/// game or publisher; the release workflow refuses a submission run when
/// the file is missing or empty (before the macOS build); and the fastlane
/// lane writes the file onto the version's App Review Information before
/// submitting. The pubspec pin keeps the shipped package identity from
/// describing the game as another game's copy.
void main() {
  // flutter test runs from the package directory (the assumption
  // vehicle_sprites_test.dart makes for assets); the workflow lives one
  // level up. The in-repo fallback covers running from the repo root.
  String readRepoFile(String path) {
    for (final candidate in ['../$path', path]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }
    fail('could not find $path relative to ${Directory.current.path}');
  }

  group('the review-notes statement', () {
    final notes = readRepoFile('fastlane/review_notes.txt');

    test('exists, is non-empty, and fits the App Review notes field', () {
      expect(notes.trim(), isNotEmpty);
      expect(notes.trim().length, lessThanOrEqualTo(4000),
          reason: 'appStoreReviewDetails.notes caps at 4000 characters');
    });

    test('identifies the app and its original provenance', () {
      expect(notes, contains('Cab Hustle'));
      expect(notes, contains('Flutter'));
      expect(notes, contains('original'));
      expect(notes, contains('template'));
    });

    test('never names another game or publisher', () {
      for (final forbidden in ['Pick Me Up', 'Voodoo', 'Crazy Taxi']) {
        expect(notes, isNot(contains(forbidden)),
            reason: 'the notes must not invite the comparison they answer');
      }
    });

    test('names the features a reviewer can verify quickly', () {
      for (final feature in ['Daily Shift', 'Endless Shift', 'bank']) {
        expect(notes, contains(feature));
      }
    });
  });

  group('the submit pipeline refuses submissions without the notes', () {
    test('the release workflow gates submission runs on the file', () {
      final workflow = readRepoFile('.github/workflows/ios-release.yml');
      expect(workflow, contains('fastlane/review_notes.txt is missing'));
      expect(workflow, contains('fastlane/review_notes.txt is empty'));
      expect(workflow, contains('4.3(a) guard'));
    });

    test('the fastlane lane writes the file onto the version before deliver',
        () {
      final fastfile = readRepoFile('fastlane/Fastfile');
      expect(fastfile, contains('set_review_notes(version)'));
      expect(fastfile, contains('review_notes.txt'));
      expect(fastfile, contains('fetch_app_store_review_detail'));
      expect(fastfile, contains('create_app_store_review_detail'));
    });
  });

  group('the shipped package identity', () {
    test('does not describe the game as another game', () {
      final pubspec = readRepoFile('pubspec.yaml');
      final description = pubspec
          .split('\n')
          .firstWhere((line) => line.startsWith('description:'),
              orElse: () => '');
      expect(description, isNotEmpty);
      for (final forbidden in ['Pick Me Up', 'Voodoo', 'clone']) {
        expect(description, isNot(contains(forbidden)));
      }
    });
  });
}
