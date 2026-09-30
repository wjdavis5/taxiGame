import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The issue-sweep workflow's push and CI contract (issue #88).
///
/// The sweep script (`.zcode/workflows/gh-issue-sweep.dwf.ts`) drives real
/// git pushes and real CI waits, so this suite cannot execute it — the
/// behavioral truth table for its helpers ran against a scripted fake world
/// when the fix landed, and these assertions keep the *structure* from
/// regressing afterwards. The bug was structural: bare
/// `await world.run("git", ["push", …])` calls (world.run reports failures
/// as exit codes, it does not throw) let a rejected push pass silently, and
/// CI was awaited once before review but never again on the heads that
/// review-round fixes produced — so the merge could ship a head CI never
/// passed, or a remote head that never got the fix at all.
void main() {
  // flutter test runs from the package directory (the assumption
  // vehicle_sprites_test.dart makes for assets); the workflow lives one
  // level up. The in-repo fallback covers running from the repo root.
  String readRepoFile(String path) {
    for (final candidate in ['../$path', path]) {      final file = File(candidate);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }
    fail('could not find $path relative to ${Directory.current.path}');
  }

  final script = readRepoFile('.zcode/workflows/gh-issue-sweep.dwf.ts');

  /// The named helper's body, from its `const name =` line to the next
  /// top-level `const`/`// ---` marker, so assertions stay scoped to it.
  String helperBody(String name, String until) {
    final start = script.indexOf('const $name =');
    expect(start, greaterThan(-1), reason: 'helper $name is missing');
    final end = script.indexOf(until, start);
    expect(end, greaterThan(-1), reason: 'helper $name has no end marker');
    return script.substring(start, end);
  }

  group('the sweep script pushes only through checked helpers (issue #88)', () {
    test('every git push and commit lives inside commitAndPush', () {
      // Exactly one push site in the whole script: the helper. A second
      // bare push is precisely how the review-round bug shipped — its exit
      // code went unchecked, so a rejected push looked like success.
      expect(RegExp(r'world\.run\("git", \["push"').allMatches(script),
          hasLength(1),
          reason: 'git push must appear exactly once, inside commitAndPush');
      expect(RegExp(r'world\.run\("git", \["commit"').allMatches(script),
          hasLength(1),
          reason: 'git commit must appear exactly once, inside commitAndPush');
    });

    test('commitAndPush tolerates only the clean-tree nothing-to-commit', () {
      final body = helperBody('commitAndPush', 'interface CiVerdict');

      // A non-zero commit is only survivable when the tree is verifiably
      // clean; any other commit failure (hook, lockfile, identity) leaves
      // uncommitted changes that must stop the sweep.
      expect(body, contains('world.run("git", ["status", "--porcelain"])'));
      expect(body, contains(r'status.stdout.trim() !== ""'));
      expect(body, contains('push.exitCode !== 0'),
          reason: 'a rejected push must hard-fail with its stderr');
      expect(body, contains('world.run("git", ["rev-parse", "HEAD"])'),
          reason: 'the helper must report the head it landed for the merge pin');
    });

    test('awaitCi verifies the head on the PR before watching checks', () {
      final body = helperBody('awaitCi', 'const CODER_PERSONA');

      // Booking check: gh must report the pushed sha as the PR head, or
      // the watch below would judge (and the merge ship) the wrong head.
      expect(body, contains('--json", "headRefOid'));
      expect(body, contains('expectedHead'));
      expect(body, contains('"--watch", "--interval", "30"'));
    });

    test('CI is awaited after the PR is created and after every fix push',
        () {
      expect(script, contains('awaitCi(prNumber, landed.head)'),
          reason: 'phase 5 must CI the head it opened the PR with');
      expect(script, contains('awaitCi(prNumber, landedFix.head)'),
          reason: 'each review-round push must re-CI its new head');
    });

    test('the merge is pinned to the head CI passed', () {
      expect(script, contains('"--match-head-commit", verifiedHead'),
          reason: 'gh must refuse the merge if the branch moved after CI');

      // verifiedHead may only ever be a head that awaitCi watched green:
      // seeded from the PR-creating push, advanced after a green fix CI.
      expect(script, contains('let verifiedHead = landed.head'));
      expect(script, contains('verifiedHead = landedFix.head'));
      expect(
          RegExp('verifiedHead = (?!landed\\.head|landedFix\\.head)')
              .allMatches(script),
          isEmpty,
          reason: 'verifiedHead must not be assigned from anything but a '
              'head that went through awaitCi');
    });

    test('a failed fix push or fix CI stops the sweep honestly', () {
      // Both failure paths leave the PR open and say which head CI did
      // cover — the old code merged (or reported green CI) regardless.
      expect(script, contains('could not be pushed to PR'),
          reason: 'a rejected review-fix push must stop before re-review');
      expect(
          script,
          contains(
              'CI on the review-fix head'),
          reason: 'red CI on a fix head must stop before merge');
      expect(script, contains('nothing was merged'));
    });

    test('no CI claim is made without naming the head it passed on', () {
      // The old report said "green CI on the PR" — true only of a head
      // that review-round pushes had already replaced.
      expect(script, isNot(contains('green CI on the PR')));
      expect(script, isNot(contains('"gh pr checks --watch (green CI)"')),
          reason: 'an unpinned green-CI claim must not return');
      expect(RegExp('green CI on head ').allMatches(script).length,
          greaterThanOrEqualTo(3),
          reason: 'merge-failure and final-report claims must name the head');
    });
  });
}
