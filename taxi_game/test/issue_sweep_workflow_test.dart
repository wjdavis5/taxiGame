import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The issue-sweep workflow's push and CI contract (issue #88), its
/// gate-log round trip (issue #97), and its branch-safety pins
/// (issue #108).
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

  group('the flutter gate helper round-trips one log path (issue #97)', () {
    // The gate helper captures failed analyze/test output to a temp file
    // and reads it back — the write is cmd, the read is PowerShell, and
    // the path between them must be built once or the two shells can
    // name different files. The original bug was an escaping bug: a lone
    // `\s` inside a JS/TS string literal is not an escape sequence and
    // collapses to a plain `s`, so the write targeted
    // `%TEMP%sweep_flutter.log` (a file in temp's parent) while the read
    // evaluated the unset `$env:TEMPsweep_flutter` to `$null` — every
    // failed gate round reached the coder with an empty log.
    test('the write and the read build the path from one shared constant',
        () {
      final body = helperBody('flutter', 'const sleepSeconds');

      // The suffix lives in exactly one correctly escaped constant —
      // top-level, just above the helper — and the source-level `\\`
      // evaluates to a single backslash at runtime.
      expect(script, contains(r'const flutterLog = "\\sweep_flutter.log"'),
          reason: 'the path suffix must be defined once, escaped');

      // Both commands interpolate that constant — never a private copy
      // of the path, which is how writer and reader diverged.
      expect(body, contains(r'" > %TEMP%" + flutterLog'),
          reason: 'the cmd write must redirect through the constant');
      expect(body, contains(r'$env:TEMP" + flutterLog'),
          reason: 'the PowerShell read must read through the constant');
    });

    test('the collapsed single-backslash form appears nowhere', () {
      // The bug's source form: `%TEMP%` or `$env:TEMP` directly glued to
      // a single-backslash `\sweep_flutter.log`. Neither shell may ever
      // see it again — with the backslash lost, cmd wrote to temp's
      // parent and PowerShell read a null path.
      expect(script, isNot(contains(r'%TEMP%\sweep_flutter.log')));
      expect(script, isNot(contains(r'$env:TEMP\sweep_flutter.log')));
    });
  });

  group('the sweep never commits off its own branch (issue #108)', () {
    // The original bug: the branch name was sha-only, so a leftover
    // branch from a failed prior sweep (same main, same sha) made
    // `git checkout -b` exit non-zero with "already exists" — a result
    // world.run reports rather than throws — and the sweep ignored it,
    // committed everything onto local main, and opened a PR whose diff
    // was the previous attempt's. Three structural pins keep that shape
    // from returning: the name can never collide, the checkout's exit
    // code is checked, and commitAndPush verifies the branch itself
    // before committing anything.
    test('the branch name is unique beyond the sha', () {
      final start = script.indexOf('const branch =');
      expect(start, greaterThan(-1), reason: 'the branch assignment is missing');
      final line = script.substring(start, script.indexOf(';', start));

      expect(line, contains('sha.stdout.trim()'),
          reason: 'the sha stays in the name so the branch still reads '
              'as "sweep of this commit"');
      // The beyond-the-sha suffix counts this sha's leftover remote
      // branches rather than reading the clock. The original #108 fix
      // used Date.now(); the workflow runtime forbids clock reads and a
      // tick that called one errored outright, so f8a3e94 moved to the
      // count — the deterministic, replay-safe form of the same
      // guarantee: a failed prior sweep that pushed leaves N remote
      // branches for this sha, so this attempt names suffix N and
      // collides with none of them. (A leftover that never pushed is
      // invisible to ls-remote; the checked checkout below is the
      // backstop that catches it honestly.)
      expect(line, contains('staleCount'),
          reason: 'a beyond-the-sha suffix is the only thing that makes a '
              'leftover branch from a failed prior sweep unable to collide');
      expect(line, isNot(contains('Date')),
          reason: 'the runtime forbids clock reads here (f8a3e94) — the '
              'uniqueness must come from the world, not the wall clock');
      // And the count is derived from the remote branch list a leftover
      // would actually appear in, scoped to this sha's own sweep
      // branches — counting anything else would not name the next free
      // suffix.
      expect(script, contains('"ls-remote"'));
      expect(
          script,
          contains('"automation/issue-sweep-" + sha.stdout.trim() + "-*"'),
          reason: 'the counted pattern is this sha\'s own sweep branches');
    });

    test('the checkout result is captured and exit-code checked', () {
      // Exactly one branch-creation site, and its result is bound to a
      // name and branched on — the bare
      // `await world.run("git", ["checkout", "-b", …])` form is gone.
      expect(
          RegExp(r'world\.run\("git", \["checkout", "-b"').allMatches(script),
          hasLength(1),
          reason: 'branch creation must appear exactly once');
      expect(
          script,
          contains(
              'const checkout = await world.run("git", ["checkout", "-b", branch])'),
          reason: 'the checkout result must be captured, not discarded');
      expect(script, contains('checkout.exitCode !== 0'),
          reason: 'a failed checkout must stop the sweep before any edit');
      expect(script, contains('creating the sweep branch failed'),
          reason: 'the planned issues are marked failed on the board, not '
              'silently dropped');
    });

    test('commitAndPush verifies the current branch before committing', () {
      final body = helperBody('commitAndPush', 'interface CiVerdict');

      // The backstop: even if some future checkout failure slips past
      // the exit-code check, the script's single commit site must refuse
      // to run while HEAD is anywhere but the sweep branch.
      expect(body, contains('world.run("git", ["branch", "--show-current"])'));
      expect(body, contains('on.stdout.trim() !== branch'),
          reason: 'local main, a detached HEAD, or any other branch must '
              'be refused before the commit');

      // And the guard runs first, before anything is staged — a check
      // after the add would already have touched the wrong branch's index.
      final guardAt = body.indexOf('"--show-current"');
      final addAt = body.indexOf('world.run("git", ["add", "-A"])');
      expect(guardAt, lessThan(addAt),
          reason: 'the branch verification precedes the staging');
    });
  });
}
