import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The issue-sweep workflow's push and CI contract (issue #88), its
/// gate-log round trip (issue #97), its branch-safety pins (issues #108
/// and #118), its deploy-verdict pins (issues #124, #128, and #184), its
/// CI-claim wording pins (issue #163 — claims must state what CI really
/// runs; #168 later added a simulator launch, and the pins follow it),
/// and its phase-1 fail-closed pins (issue #176).
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
/// passed, or a remote head that never got the fix at all. The #124 bug
/// was the same shape at the deploy end: the verdict was read off `gh run
/// watch`'s exit code, but the release workflow skips the upload while
/// staying green when the App Store Connect train is closed (issue #119),
/// so a green run with no build was reported — and the issues closed — as
/// a TestFlight deploy. The #128 bug was one layer deeper: the jobs read
/// back from the green run were cast as a bare array, but `gh run view
/// --json jobs` answers `{"jobs":[…]}`, so the lookup threw into the catch
/// and every verdict read as unreadable — no deploy ever recorded. The
/// #184 bug was the red side of the same verdict: a non-zero `gh run
/// watch` exit printed the failure claim off the exit code alone, though
/// the watch exits non-zero both when the run fails and when the watch
/// itself dies — so a run that went red *after* a successful upload step
/// (a later `if: always()` step) left already-deployed issues open, and a
/// dead watch asserted a failure nobody had witnessed.
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

  group('the sweep never commits off its own branch (issues #108, #118)', () {
    // The original bug: the branch name was sha-only, so a leftover
    // branch from a failed prior sweep (same main, same sha) made
    // `git checkout -b` exit non-zero with "already exists" — a result
    // world.run reports rather than throws — and the sweep ignored it,
    // committed everything onto local main, and opened a PR whose diff
    // was the previous attempt's. Three structural pins keep that shape
    // from returning: the name can never collide, the checkout's exit
    // code is checked, and commitAndPush verifies the branch itself
    // before committing anything. #118 tightened the first pin: the
    // f8a3e94 suffix counted only *remote* leftovers, so a local-only
    // leftover (a sweep whose push failed) recomputed the same name and
    // the checked checkout stopped every tick until main moved — honest,
    // but the sweep could never start.
    test('the branch name is the next free suffix on both sides '
        '(issues #108, #118)', () {
      final start = script.indexOf('const branch =');
      expect(start, greaterThan(-1), reason: 'the branch assignment is missing');
      final line = script.substring(start, script.indexOf(';', start));

      // The sha stays in the name so the branch still reads as "sweep of
      // this commit"; both lookups and the final assembly share one
      // prefix constant so they cannot drift out of scope with each
      // other.
      expect(
          script,
          contains(
              '"automation/issue-sweep-" + sha.stdout.trim() + "-"'),
          reason: 'the prefix (sha included) must be built once, shared by '
              'the local lookup, the remote lookup, and the final name');
      expect(line, contains('branchPrefix'),
          reason: 'the final name assembles from the shared prefix');
      expect(line, isNot(contains('Date')),
          reason: 'the runtime forbids clock reads here (f8a3e94) — the '
              'uniqueness must come from the world, not the wall clock');

      // #118: BOTH sides are consulted. A local-only leftover (the
      // failed-push sweep) appears in `git branch --list`; a remote one
      // (the closed-unmerged PR) appears in `ls-remote`. Counting either
      // side alone recomputes a name that already exists.
      expect(script, contains('"branch", "--list"'),
          reason: 'the local leftover branches must be looked up too');
      expect(script, contains('"ls-remote"'),
          reason: 'the remote leftover branches stay looked up');
      expect(script, contains('branchPrefix + "*"'),
          reason: 'both lookups are scoped to this sha\'s own sweep '
              'branches');

      // And the suffix is max(existing)+1, not a count: a count equals a
      // live suffix whenever the existing suffixes are not exactly
      // 0..n-1 (a deleted -0 leaves -1 counted as 1, colliding with the
      // surviving -1). The trailing-number regex reads both line shapes
      // — `git branch --list`'s bare names and ls-remote's
      // `<sha>\t<ref>` pairs.
      expect(script, contains(r'/-(\d+)$/.exec'),
          reason: 'the suffix is parsed off each ref name');
      expect(script, contains('Math.max'),
          reason: 'the highest existing suffix wins, whatever the gaps');
      expect(script, contains('maxSuffix + 1'),
          reason: 'the name takes the next free suffix, not a count that '
              'a gap can turn into a collision');
    });

    test('a failed leftover-branch lookup stops the sweep honestly '
        '(issue #118)', () {
      // The old code never read the ls-remote exit code, so a failed
      // lookup printed nothing, read as suffix 0, and could hand the
      // sweep a name that collides — surfacing only as a rejected push
      // after the whole implementation, or as the checked checkout
      // failing every tick. Both lookups' exit codes are now read, and
      // a failure stops before any edit with the same honest shape as
      // the checkout-failure return: planned issues marked failed, a
      // conclusion that says why, and the lanes that never ran named.
      expect(script, contains('localStale.exitCode !== 0'));
      expect(script, contains('remoteStale.exitCode !== 0'),
          reason: 'the ls-remote exit code must be read, not assumed');
      expect(script, contains('the leftover-branch lookup failed'),
          reason: 'the planned issues are marked failed on the board, not '
              'silently dropped');
      expect(script, contains('no branch was created'),
          reason: 'the stop must name what never ran, as the checkout '
              'failure does');
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

  group('a green release run is only a deploy when the upload step ran '
      '(issue #124)', () {
    // The original bug: the sweep read its deploy verdict off `gh run
    // watch`'s exit code alone, but the release workflow's closed-train
    // gate (issue #119) skips the build and the upload while the run stays
    // green — so issues were closed as deployed-to-TestFlight by a run
    // that uploaded nothing. The verdict must come from the Upload to
    // TestFlight step's own conclusion, read back from the green run's
    // jobs — and a verdict that cannot be read is no deploy.
    test('the green run is read back for the upload step', () {
      expect(script, contains('"run", "view", releaseRunId, "--json", "jobs"'),
          reason: 'the sweep must query the green run\'s jobs — the watch '
              'exit code cannot say whether the upload step ran');
      expect(script, contains('"Build, sign, and upload"'),
          reason: 'the job name is pinned to ios-release.yml');
      expect(script, contains('"Upload to TestFlight"'),
          reason: 'the step name is pinned to ios-release.yml');
    });

    test('deployed is the step conclusion, never the watch exit code', () {
      expect(script, isNot(contains('deployed = release.exitCode === 0')),
          reason: 'a green run whose upload was skipped must not read as '
              'deployed');
      expect(script, contains('deployed = stepConclusion === "success"'),
          reason: 'only the upload step concluding success is a deploy');

      // The skipped verdict is a third state with its own flag, not a
      // flavor of failed: the step (or its whole job) skipped means the
      // gate stood the run down while everything else about the merge
      // succeeded.
      expect(script, contains('let uploadSkipped = false'));
      expect(script, contains('=== "skipped"'),
          reason: 'a skipped job or step must be recognized as skipped');
    });

    test('the skipped case closes the issues with its own honest comment',
        () {
      // Leaving skipped-upload issues open would make the next sweep
      // re-implement already-merged work, so they close — but on a
      // comment that says merged + gate + next upload, never on the
      // deployed one. The deployed text appears exactly once, in its own
      // branch; the skipped branch is a separate arm with its own words.
      expect(
          RegExp('deployed to TestFlight \\(issue-sweep pipeline\\)')
              .allMatches(script),
          hasLength(1),
          reason: 'the deployed close comment belongs to the deployed '
              'branch alone');
      expect(script, contains('else if (uploadSkipped)'),
          reason: 'the skipped verdict has its own close branch');
      expect(script, contains('The TestFlight upload was skipped'),
          reason: 'the skipped comment says what actually happened');
      expect(script, contains('after a version bump'),
          reason: 'the skipped comment says how the merge eventually ships');
    });

    test('no report line claims an upload the step did not make', () {
      // "upload green" is claimed exactly once, and only in the arm that
      // also names the step's success conclusion; the skipped arm denies
      // the upload outright.
      expect(RegExp('TestFlight upload green').allMatches(script),
          hasLength(1),
          reason: 'the upload-green claim must stay branch-scoped');
      expect(
          script,
          contains(
              'TestFlight upload green: the Upload to TestFlight step concluded success'),
          reason: 'the green claim is tied to the step conclusion it '
              'rests on');
      expect(script, contains('no TestFlight upload'),
          reason: 'the skipped arm must deny the upload explicitly');

      // deployLine itself branches three ways after the watch, so a
      // skipped or unreadable step can never inherit the uploaded
      // wording either.
      expect(script, contains('uploaded the build to TestFlight'));
      expect(script,
          contains('stayed green but skipped the Upload to TestFlight step'));
      expect(script, contains('claims no TestFlight upload'));
    });
  });

  group('the run-view payload is read as gh shapes it (issue #128)', () {
    // The #124 fix read the verdict from the right place but cast the
    // payload wrong: `gh <noun> view --json <field>` answers with an
    // object keyed by the requested fields — the same shape
    // `.headRefOid` and `.mergeCommit` are read through elsewhere in the
    // script — and only `gh run list --json` returns a bare array. The
    // miscast `.find` threw into the catch, so stepConclusion and
    // jobConclusion stayed null, `deployed` and `uploadSkipped` were
    // both false, and every merged fix rode the leave-open failed path.
    // The behavioral truth table — a real-shaped {"jobs":[…]} payload
    // walked through the step-success, skipped, and other-conclusion
    // outcomes — ran against the snippet bench when the fix landed;
    // these pins keep the parse shape from regressing.
    test('the parse casts the run-view stdout as {jobs: […]}', () {
      expect(
        RegExp(r'JSON\.parse\(releaseJobs\.stdout\) as \{\s*jobs:')
            .hasMatch(script),
        isTrue,
        reason: 'gh run view --json jobs answers {"jobs":[…]}, so the '
            'cast must name the jobs key, not assume an array',
      );
      expect(
        script,
        contains('runView.jobs.find'),
        reason: 'the upload job is looked up inside the parsed object\'s '
            'jobs array',
      );
    });

    test('the bare-array cast on run-view stdout is gone', () {
      expect(
        RegExp(r'JSON\.parse\(releaseJobs\.stdout\) as \{\s*name: string;')
            .hasMatch(script),
        isFalse,
        reason: 'casting the object payload as a bare array is the #128 '
            'bug: .find throws into the catch and the verdict is always '
            'unreadable, so no deploy is ever recorded',
      );
    });

    test('the command still asks gh for the fields, not a jq projection',
        () {
      // Projecting with `--jq .jobs` would also fix the shape, but it
      // needlessly rewrites the command the #124 pin holds to — and a
      // projection silently answering [] (a gh/jq hiccup) would read as
      // "no such job" instead of failing loudly. The raw field query is
      // the contract; the shape is the script's to know.
      expect(script, isNot(contains('"--jq"')),
          reason: 'the jobs query must keep asking for the raw field');
    });
  });

  group('a red or dead watch is not a verdict about the run (issue #184)',
      () {
    // The #124 fix taught the *green* arm to read the upload step's own
    // conclusion; the red arm still read its verdict off the watch exit
    // code alone. But `gh run watch --exit-status` exits non-zero both
    // when the run concludes failure and when the watch itself dies, and
    // a run can go red *after* a successful upload step (a later
    // `if: always()` step in ios-release.yml) — so the sweep left
    // already-deployed issues open, or asserted the failure claim
    // without knowing the run's outcome at all. The step read now runs
    // after every watch outcome, and a red watch asks the run itself
    // before claiming either direction.
    test('a thrown watch is recorded as a red one, not an error', () {
      // world.run reports command failures as exit codes, but its
      // timeoutMs-expiry behavior is undocumented (the issue marks it
      // inferred) — a throw used to error the sweep after the merge,
      // losing the verdict entirely. It is caught and shaped like a
      // non-zero exit so the red-watch handling owns it.
      expect(script, contains('catch (watchError)'));
      expect(
          script,
          contains(
              'release = { exitCode: -1, stdout: "", stderr: String(watchError) }'),
          reason: 'a dead watch must ride the red-watch path, not error '
              'the sweep with the merge already on main');
    });

    test('the upload-step read runs after any watch outcome', () {
      // The jobs read is hoisted out of the green-only arm — an upload
      // that succeeded before a later red step or before a dead watch is
      // still a deploy — and the run-state read happens only on a red
      // watch, after that unconditional read.
      final jobsReadAt = script.indexOf('"--json", "jobs"');
      final redGuardAt = script.indexOf('if (!watchGreen)');
      final stateReadAt = script.indexOf('"--json", "status,conclusion"');
      expect(jobsReadAt, greaterThan(-1));
      expect(redGuardAt, greaterThan(-1));
      expect(stateReadAt, greaterThan(-1));
      expect(jobsReadAt, lessThan(redGuardAt),
          reason: 'the step read must not depend on the watch being green');
      expect(stateReadAt, greaterThan(redGuardAt),
          reason: 'the run-state read belongs to the red-watch branch');

      // The watch's own exit code is bound once, as a fact about the
      // watch — never again as the verdict.
      expect(script, contains('const watchGreen = release.exitCode === 0'));
    });

    test('the run-state read is exit-code checked and object-shaped', () {
      // The #128 lesson applied to the second read: `gh run view --json
      // status,conclusion` answers an object keyed by the fields, and a
      // failed gh is an exit code with empty stdout — parse only after
      // the check, and only a parsed read may establish green or red.
      final exitAt = script.indexOf('runState.exitCode !== 0');
      final parseAt = script.indexOf('JSON.parse(runState.stdout)');
      expect(exitAt, greaterThan(-1));
      expect(parseAt, greaterThan(-1));
      expect(exitAt, lessThan(parseAt),
          reason: 'a failed state read is an unknown outcome, not a '
              'SyntaxError on empty stdout');
      expect(script, contains('runStateRead'),
          reason: 'green and red are derivable only from a parsed read');
      expect(script, contains('runConclusion === "success"'),
          reason: 'known-green is the watch or a read-back success');
      expect(script, contains('runConclusion !== "success"'),
          reason: 'known-red is a completed run with another conclusion');
    });

    test('a skipped upload step only reads as the gate on a known-green '
        'run', () {
      // A red run skips its upload step for mundane reasons — an earlier
      // job failed and the upload never ran — and reading that as the
      // closed-train gate would close issues on a gate that never spoke.
      expect(script, contains('!deployed && runKnownGreen'),
          reason: 'uploadSkipped must be gated on the run being known '
              'green, not just on a skipped conclusion');
    });

    test('the unknown outcome claims neither direction', () {
      // Still running when the watch gave up, or a state that could not
      // be read: no deploy is claimed (nothing says the upload ran), no
      // failure either (nothing says it did not) — and the board says
      // unknown, not failed.
      expect(script,
          contains('claims neither a TestFlight deploy nor a failed one'));
      expect(script, contains('the deploy outcome is unknown'),
          reason: 'the board note must not claim a failure that was '
              'never established');
    });

    test('the failure claim is made only on a run known red', () {
      // Exactly once in the script, inside the arm that has read the
      // run's own conclusion — never again off the watch exit code.
      expect(RegExp('TestFlight did not get a build').allMatches(script),
          hasLength(1),
          reason: 'the failure claim must stay inside the known-red arm');
      final phraseAt = script.indexOf('TestFlight did not get a build');
      final redArmAt = script.indexOf('else if (runKnownRed)');
      expect(redArmAt, greaterThan(-1),
          reason: 'the known-red arm must exist as its own branch');
      expect(phraseAt, greaterThan(redArmAt),
          reason: 'the claim may only follow an established conclusion');
      expect(script, isNot(contains('FAILED — the merge is on main')),
          reason: 'the old exit-code-only red arm must not return');
    });

    test('a verdict kept against a red watch names the watch itself', () {
      // Whenever a deploy or a gate-skip is still claimed after the watch
      // went red, the report appends the watch's exit code and a tail of
      // its output, so a human can see what was — and was not — trusted.
      expect(script, contains('gh run watch exited " + release.exitCode'));
      expect(script, contains('tail(release.stderr || release.stdout)'),
          reason: 'the caveat carries a tail of the watch output');
      expect(script, contains('watchCaveat'),
          reason: 'the caveat is appended to the verdicts kept against a '
              'red watch');
    });
  });

  group('the phase-1 gh guards fail closed (issue #176)', () {
    // The original bug: the one-sweep-at-a-time guard read only
    // `openPrs.stdout`, and world.run reports a failed gh as an exit code
    // with empty stdout (the #88/#108/#118 lesson — it does not throw),
    // so a failed `gh pr list` read as "no sweep PR open" while one sat
    // awaiting a human, and the sweep started a second one over it. One
    // call later, the same unread exit code dropped a failed
    // `gh issue list` into JSON.parse on empty stdout — a SyntaxError
    // that errored the workflow instead of an honest skip. Both guards
    // now stop the sweep before anything is created, in the exact shape
    // of the `git pull --ff-only` sync guard above them.
    test("gh pr list's exit code is checked before the open-PR match", () {
      expect(script, contains('openPrs.exitCode !== 0'),
          reason: 'a failed listing must skip the sweep, not read as an '
              'empty one');

      // Ordering: the exit-code check must precede the stdout match it
      // guards — after it, a failed listing has already been treated as
      // "no sweep PR open".
      final exitAt = script.indexOf('openPrs.exitCode !== 0');
      final matchAt = script.indexOf('openPrs.stdout.includes');
      expect(exitAt, greaterThan(-1));
      expect(matchAt, greaterThan(-1));
      expect(exitAt, lessThan(matchAt),
          reason: 'the guard must run before the match it fails closed '
              'for');
    });

    test("gh issue list's exit code is checked before the JSON parse", () {
      expect(script, contains('issuesRun.exitCode !== 0'),
          reason: 'a failed issue listing must be an honest skip, not a '
              'SyntaxError on empty stdout');

      final exitAt = script.indexOf('issuesRun.exitCode !== 0');
      final parseAt = script.indexOf('JSON.parse(issuesRun.stdout)');
      expect(exitAt, greaterThan(-1));
      expect(parseAt, greaterThan(-1));
      expect(exitAt, lessThan(parseAt),
          reason: 'the guard must precede the parse it protects');
    });

    test('the skip conclusions name the failure and its exit code', () {
      // Both reports say what failed and with which exit code, in the
      // sync guard's shape — and the PR guard says what continuing would
      // have risked, the very regression the issue names. The risk is
      // pinned as the two fragments its TS line-wrapping splits it into,
      // like the #118 pins above.
      expect(script, contains('gh pr list exited'),
          reason: 'the PR-list skip names the command and its exit code');
      expect(script, contains('a second sweep PR over one still'),
          reason: 'the skip says why proceeding was refused — the '
              'one-sweep-at-a-time contract is the thing the guard '
              'protects');
      expect(script, contains('awaiting a human'),
          reason: 'and names whose decision the open sweep PR holds up');
      expect(script, contains('gh issue list exited'),
          reason: 'the issue-list skip names the command and its exit '
              'code');
    });
  });

  group('CI claims match what CI actually runs (issue #163)', () {
    // The sweep's narration and final report claimed an "iOS simulator
    // run" that did not exist when #163 landed: no workflow booted a
    // simulator or launched the app. PR CI (flutter-builds.yml) ran
    // analyze, the test suite on the macOS host, and an unsigned
    // `flutter build ios --no-codesign`; the release pipeline archives
    // against a generic iOS destination. Four spots hard-coded the false
    // claim — the zcode description, the header outline, the phase-5
    // title, and the report's notCovered line. #168 later added a real
    // simulator launch to PR CI (build, boot, install, launch, assert
    // alive), which turned "the app is never launched" into the same lie
    // from the other side — so the pins below follow what CI runs today:
    // the report credits the simulator launch and names the
    // physical-device gap that remains. The negative pin still guards
    // the historical "iOS simulator" phrasing; the positive pins keep
    // the honest replacements from eroding back into vagueness.
    test('the historical "iOS simulator" phrasing stays gone', () {
      // Every #163-era false claim said "iOS simulator". CI does launch
      // on a simulator now (issue #168) — pinned exactly below — and the
      // honest wording says "a simulator", so the stale phrasing has no
      // reason to return.
      expect(script, isNot(contains('iOS simulator')),
          reason: 'the historical false-claim phrasing must not return — '
              'the launch CI really performs is pinned below');
    });

    test('the report credits the simulator launch CI performs', () {
      // #168 moved the ground under this pin: PR CI gained a real
      // simulator launch (flutter-builds.yml builds for the simulator,
      // boots one, installs, launches com.wjdavis5.taxigame, and asserts
      // the process is still alive 8 s later), so "the app was never
      // launched" — this test's old pin — became the lie. The closest
      // check CI really performs is the launch itself; the gap that
      // remains is the physical device.
      expect(script, contains('on-device verification on a physical iPhone'),
          reason: 'the gap named is the real one: no physical device has '
              'ever run the app');
      expect(script, contains('CI compiles the app'),
          reason: 'the compile half of the closest check is credited');
      expect(
          script,
          contains('and launches it on a simulator; a physical device never '
              'ran it'),
          reason: 'the launch half is claimed, with the device gap said '
              'outright');
    });

    test('the phase-5 title and outline name the checks CI really runs', () {
      expect(script, contains('phase("Open the PR and wait for CI'),
          reason: 'the phase title must keep narrating the CI wait');
      expect(
          script,
          contains('analyze, host-run tests, and the unsigned iOS build");'),
          reason: 'the wait is described by checks CI really runs: '
              'analyze, host tests, the unsigned build');
      expect(script, contains('analyze, host tests, unsigned iOS build'),
          reason: 'the header outline carries the same honest list');
      expect(
          script,
          contains('a simulator launch of the built app'),
          reason: 'the zcode description and outline both state the '
              'launch CI performs (issue #168)');
      expect(
          script,
          contains('a physical device never runs it'),
          reason: 'and both name the physical-device gap that remains');
    });
  });
}
