import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The manual-release contract (issue #111).
///
/// The submit lane meant to keep shipping a human decision — its
/// `automatic_release: false` — but deliver reads that flag only inside
/// the metadata upload, and the lane submits with `skip_metadata: true`
/// so the listing maintained in App Store Connect is never touched.
/// Under the skip the flag is inert: the version keeps ASC's
/// AFTER_APPROVAL default and an approved build would go live on its
/// own. The lane now sets the release type itself — Spaceship's
/// find-or-create for the editable version, then a PATCH to
/// `ReleaseType::MANUAL`, before the submit — the status script says
/// what a release type actually means, and the skill reads the real
/// value instead of asserting the wrong one. These tests pin the
/// contract the way release_submit_gate_test.dart pins the submit gate:
/// text assertions over the shipped files — no network, no credentials,
/// exactly the parts of the issue that can be coded. The one human-only
/// item (checking Version Release on a version already in review in App
/// Store Connect) is a UI act; the lane fix covers every submission
/// this repo makes from here on.
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
  final skill = readRepoFile('.claude/skills/release/SKILL.md');
  final asc = readRepoFile('.claude/skills/release/scripts/asc.rb');

  group('the release type is MANUAL by an explicit write (issue #111)', () {
    test('the submit lane PATCHes ReleaseType::MANUAL before deliver', () {
      // The write itself: find-or-create the editable version, then set
      // its release type through the Connect API — the primitives
      // deliver's metadata upload would have used, minus the skip that
      // makes it return before ever reading automatic_release.
      expect(fastfile, contains('ensure_version!'));
      expect(fastfile, contains('get_edit_app_store_version'));
      expect(fastfile, contains('ReleaseType::MANUAL'));

      // Position: the lane must reach the write before it reaches
      // deliver, so the submission carries the release type. (The
      // constant itself lives in the helper's body, defined below the
      // platform block like wait_until_processed — what orders is the
      // call site.) Done after the submit, the version would already be
      // in review with whatever type ASC defaulted to.
      final writeAt = fastfile.indexOf('ReleaseType::MANUAL');
      final deliverAt = fastfile.indexOf('deliver(');
      expect(writeAt, greaterThan(-1));
      expect(deliverAt, greaterThan(-1));

      // The write is reached from the lane, not just defined beside
      // it — the same shape as wait_until_processed: called in the lane,
      // defined below the platform block.
      final laneCallAt = fastfile.indexOf('set_manual_release(version)');
      final defAt = fastfile.indexOf('def set_manual_release');
      expect(laneCallAt, greaterThan(-1),
          reason: 'the lane must call the write');
      expect(defAt, greaterThan(-1));
      expect(laneCallAt, lessThan(defAt));
      expect(laneCallAt, lessThan(deliverAt),
          reason: 'the lane writes the release type before its deliver');
    });

    test('skip_metadata stays: the listing is still never overwritten', () {
      // The containment the lane runs under — the reason
      // automatic_release cannot work is the same reason the listing
      // must not be clobbered by a submit. Both stay.
      expect(fastfile, contains('skip_metadata: true'));
      expect(fastfile, contains('skip_screenshots: true'));
      // The flag is kept — decorative under the skip, load-bearing if
      // the skip ever comes off — and its comment must say which is
      // which, so nobody "cleans it up" into a lie again.
      expect(fastfile, contains('automatic_release: false'));
      expect(fastfile, contains('Decorative under `skip_metadata: true`'));
    });

    test('the skill no longer claims AFTER_APPROVAL is the manual setting',
        () {
      // The wrong sentence told the operator that AFTER_APPROVAL meant
      // "nothing reaches users without them pressing the button" — the
      // exact opposite — so every green report blessed an automatic
      // release.
      expect(
        skill,
        isNot(contains('AFTER_APPROVAL`, so nothing reaches users')),
        reason: 'the skill must not read AFTER_APPROVAL as the manual '
            'setting (issue #111)',
      );
      // The correction: read the actual value, and say what each one
      // means for the user.
      expect(skill, contains('release=MANUAL'));
      expect(skill, contains('goes live automatically'));
      expect(skill, contains('asc.rb version'));
    });

    test('asc.rb flags an automatic release next to the raw value', () {
      // The status script is where a human looks: AFTER_APPROVAL and
      // SCHEDULED both put the build on the store without one, and the
      // bare enum value does not say that on its own.
      expect(asc, contains("['AFTER_APPROVAL', 'SCHEDULED']"));
      expect(asc, contains('goes live automatically'));
    });
  });
}
