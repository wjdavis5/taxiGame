import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The What's New contract (issue #199).
///
/// Apple requires release notes on every version after the first, and
/// 1.0.0 spent the exemption: the submit lane created each new version
/// with no whatsNew, Apple refused the submission, and the submit step's
/// `continue-on-error` (#94's still-open interim mitigation) kept the
/// run green — the first update after 1.0.0 would have been silently
/// unsubmitted. The notes now live in the repo
/// (`taxi_game/fastlane/whats_new.txt`), the lane writes them onto the
/// version's primary-locale localization record before the submit, the
/// release gate fails red before the macOS build when a submit is
/// intended and the file is missing or empty, and the status script
/// reports whatsNew beside the other listing fields — the same division
/// `set_manual_release` established (issue #111): per-release facts
/// read from the release commit, listing copy left to App Store Connect.
///
/// These tests pin the contract the way release_manual_release_test.dart
/// pins the release type: text assertions over the shipped files — no
/// network, no credentials. The ASC write itself needs Apple's servers;
/// what can be coded is that the write happens, in the right order,
/// from the right file, and that every silent-drop path is closed.
void main() {
  // flutter test runs with the package directory as the working
  // directory (the same assumption release_submit_gate_test.dart makes);
  // the pipeline files live one level up at the repo root. Fall back to
  // the working directory itself so running from the root still
  // resolves.
  File repoFile(String path) {
    for (final candidate in ['../$path', path]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
    fail('could not find $path relative to ${Directory.current.path}');
  }

  String readRepoFile(String path) => repoFile(path).readAsStringSync();

  final fastfile = readRepoFile('taxi_game/fastlane/Fastfile');
  final workflow = readRepoFile('.github/workflows/ios-release.yml');
  final asc = readRepoFile('.claude/skills/release/scripts/asc.rb');
  final skill = readRepoFile('.claude/skills/release/SKILL.md');
  final claude = readRepoFile('CLAUDE.md');

  /// The whole step block, from its `- name:` line to the next step's,
  /// so assertions cannot accidentally match text from some other step
  /// (the release_submit_gate_test.dart helper).
  String stepBlock(String stepName) {
    final start = workflow.indexOf('- name: $stepName');
    expect(start, greaterThan(-1), reason: 'step "$stepName" is missing');
    final next = workflow.indexOf('\n      - name: ', start + 1);
    return workflow.substring(start, next == -1 ? workflow.length : next);
  }

  group('the release notes file itself', () {
    test('whats_new.txt ships with player-facing, non-blank content', () {
      final notes = readRepoFile('taxi_game/fastlane/whats_new.txt');
      expect(notes.trim(), isNotEmpty,
          reason: 'an empty file is the exact silent drop issue #199 '
              'closed — the lane and the gate both refuse it, but the '
              'file must also not ship blank');
    });
  });

  group('the submit lane writes the What\'s New (issue #199)', () {
    test('set_whats_new PATCHes whatsNew before deliver, from the file',
        () {
      // The write itself: the localization record's whatsNew attribute,
      // through the same Spaceship primitives the release type's write
      // uses — because deliver's metadata upload, the one path that
      // would carry whatsNew, is skipped (skip_metadata: true).
      expect(fastfile, contains('whatsNew'));
      expect(fastfile, contains('ensure_version!'));
      expect(fastfile, contains('get_edit_app_store_version'));
      expect(fastfile, contains('get_app_store_version_localizations'));

      // Position and shape, the set_manual_release contract one write
      // over: called in the lane before deliver (a submission already in
      // review cannot pick the notes up after the fact), defined below
      // the platform block beside its sibling write.
      final laneCallAt = fastfile.indexOf('set_whats_new(version)');
      final defAt = fastfile.indexOf('def set_whats_new');
      final deliverAt = fastfile.indexOf('deliver(');
      final manualAt = fastfile.indexOf('set_manual_release(version)');
      expect(laneCallAt, greaterThan(-1), reason: 'the lane must call it');
      expect(defAt, greaterThan(-1));
      expect(deliverAt, greaterThan(-1));
      expect(laneCallAt, lessThan(defAt));
      expect(laneCallAt, lessThan(deliverAt),
          reason: 'the notes must be on the version before the submit');
      expect(manualAt, lessThan(laneCallAt),
          reason: 'the two writes sit together, release type first');
    });

    test('a missing or empty file is a loud lane failure, not a green skip',
        () {
      // The file contract: resolved beside the Fastfile (never the
      // runner's working directory), and both the missing and the
      // blank/whitespace-only cases fail with UI.user_error! — the same
      // loudness the wait and release-type helpers use.
      expect(fastfile, contains('whats_new.txt'));
      expect(fastfile, contains("File.expand_path(\"whats_new.txt\", __dir__)"));
      expect(fastfile, contains('File.read(notes_path).strip'));
      final laneDef = fastfile.substring(fastfile.indexOf('def set_whats_new'));
      expect(laneDef.indexOf('UI.user_error!'), greaterThan(-1),
          reason: 'the missing-file case must fail the lane');
      expect(blankFileRefused(laneDef), isTrue,
          reason: 'a whitespace-only file must fail the lane too');
    });

    test('the app\'s first version skips the write instead of losing the '
        'submit (issue #204)', () {
      // Apple offers no What's New field on an app's first version, so
      // the PATCH was refused there, the lane aborted before deliver,
      // and the submit step's continue-on-error kept the run green with
      // the submission silently lost — the mirror image of #199's
      // silent drop. The guard counts the app's version records and
      // skips the write when this is the only one, which is a skip with
      // a log, never a raise: failing the lane is exactly the behavior
      // that lost the 1.0.0 resubmission.
      final laneDef = fastfile.substring(fastfile.indexOf('def set_whats_new'));
      final notesChecksAt = laneDef.indexOf('notes.empty?');
      final ensureAt =
          laneDef.indexOf('app.ensure_version!(version, platform: platform)');
      final guardAt = laneDef.indexOf(
          'get_app_store_versions(filter: { platform: platform }, limit: 2)');
      final patchAt = laneDef.indexOf('whatsNew: notes');

      expect(guardAt, greaterThan(-1),
          reason: 'the first-version guard must exist');
      expect(notesChecksAt, greaterThan(-1));
      expect(ensureAt, greaterThan(-1));
      expect(patchAt, greaterThan(-1));
      // The file contract stays first and unchanged; the count sits
      // after ensure_version! (a not-yet-created first version then
      // counts one and is skipped, a created second counts two and the
      // write proceeds) and before the whatsNew PATCH it guards.
      expect(notesChecksAt, lessThan(guardAt),
          reason: 'the missing/empty file checks stay first');
      expect(ensureAt, lessThan(guardAt),
          reason: 'counting before ensure_version! would see one record '
              'for a fresh second version and wrongly skip it');
      expect(guardAt, lessThan(patchAt),
          reason: 'the guard must stand between ensure_version! and the '
              'write it guards');

      // A skip, not a raise: between the count and the return there is
      // a UI.important saying why, and no UI.user_error! failing the
      // lane the submit still needs to run.
      final returnAt = laneDef.indexOf('\n    return', guardAt);
      expect(returnAt, greaterThan(-1), reason: 'the guard must return');
      final guardBlock = laneDef.substring(guardAt, returnAt);
      expect(guardBlock, contains('UI.important'),
          reason: 'the skip must say why it skipped');
      expect(guardBlock.contains('UI.user_error!'), isFalse,
          reason: 'a first version must not fail the lane — that is the '
              'silent drop being fixed');

      // The humans' docs carry the exemption too, or the next release
      // of a first version reads the skip as a bug.
      expect(claude, contains('issue #204'));
      expect(skill, contains('issue #204'));
    });

    test('the skip_metadata carve-out names the one write it makes', () {
      // The lane's containment comment ("never overwrites the listing")
      // must not swallow the What's New write: the comment now names the
      // exception, so nobody reads the two as a contradiction and
      // removes the write to honor the comment.
      expect(fastfile, contains('never overwrites it — the one'));
      expect(fastfile, contains('issue #199'));
      // And the containment itself stands: the listing is still skipped.
      expect(fastfile, contains('skip_metadata: true'));
    });
  });

  group('the release gate fails red on a doomed submission (issue #199)',
      () {
    test('the gate checks the file before any build step', () {
      final gate = stepBlock('Decide whether to submit for review');
      // The check runs where the submit verdict is decided — steps
      // before the macOS build lane — and only when a submission will
      // actually be attempted: TestFlight-only runs need no notes.
      expect(gate, contains('whats_new.txt'));
      expect(gate, contains(r'if [ "$submit" = "true" ]'));
      expect(gate, contains('::error::'));
      expect(gate, contains('exit 1'));

      // Red before the spend: the gate step block precedes every build
      // step in the release job.
      final gateStart = workflow.indexOf('- name: Decide whether to submit');
      final buildStart = workflow.indexOf('- name: Build Flutter assets');
      expect(gateStart, greaterThan(-1));
      expect(buildStart, greaterThan(-1));
      expect(gateStart, lessThan(buildStart),
          reason: 'the empty-notes failure must land before the '
              'ten-minute macOS build, not after it');
    });

    test('the submit step keeps #94\'s continue-on-error untouched', () {
      // The interim mitigation stays exactly as it was: this issue's
      // fix is the gate failing early, not the submit step failing the
      // run late — #94 is still open, and a submit-lane failure must
      // still not strand the TestFlight build the run already uploaded.
      final submit = stepBlock('Submit for App Store review');
      expect(submit, contains('continue-on-error: true'));
      expect(submit, contains('whats_new.txt'),
          reason: 'the step\'s comment names the one listing write the '
              'lane makes');
    });
  });

  group('the humans can see it', () {
    test('asc.rb lists whatsNew with the other listing fields', () {
      expect(asc, contains('%w[description keywords supportUrl whatsNew]'));
    });

    test('the skill and CLAUDE.md make the file part of the bump', () {
      // The release recipe names both files a release commits: the
      // version string and the notes. Undocumented, the file is exactly
      // the kind of step a rush forgets — and the gate fails the run
      // over it.
      expect(skill, contains('whats_new.txt'));
      expect(skill, contains('issue #199'));
      expect(claude, contains('whats_new.txt'));
      expect(claude, contains('issue #199'));
    });
  });
}

/// True when the lane definition refuses a whitespace-only file: the
/// strip is what turns a blank file into the empty case the error
/// names, and the empty comparison is what fails it.
bool blankFileRefused(String laneDef) {
  final stripAt = laneDef.indexOf('File.read(notes_path).strip');
  if (stripAt == -1) return false;
  final tail = laneDef.substring(stripAt);
  return tail.contains('notes.empty?') && tail.contains('UI.user_error!');
}
