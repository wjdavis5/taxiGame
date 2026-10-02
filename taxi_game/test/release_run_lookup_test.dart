import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release run lookup's identity contract (issue #153).
///
/// Every push to `main` triggers ios-release.yml, and its `ios-release`
/// concurrency group queues rather than cancels (`cancel-in-progress:
/// false`), so at any moment a newer run can belong to another push. Step 6
/// of the release skill used to sleep a fixed 20 s and take the newest run
/// (`gh run list --limit 1`, no commit filter) — whenever another push
/// registered in that window, the skill watched that push's run and reported
/// its result and build number as the release's. The issue sweep workflow
/// got this fix first (.zcode/workflows/gh-issue-sweep.dwf.ts polls
/// `gh run list --commit <merge sha>`); the skill kept the broken recipe.
///
/// The fix is deliberately documentation, not code: pin the lookup to the
/// pushed SHA (`git rev-parse HEAD` is the pushed head — step 2 verified a
/// clean tree on main and step 5 just pushed, for both release types), poll
/// up to ~2.5 minutes for a run on that exact commit, and refuse — stop and
/// report — rather than fall back to the newest run. Everything downstream
/// (`gh run watch "$ID"`, `--log-failed`, the run-number lookup behind the
/// reported build number) keys off `$ID`, so it is correct untouched once
/// `$ID` is the right run.
///
/// These tests pin that contract the way release_build_number_rerun_test.dart
/// pins the build-number one: text assertions over the shipped skill file —
/// no network, no credentials, exactly the parts of the issue that can be
/// coded.
void main() {
  // flutter test runs with the package directory as the working directory
  // (the same assumption release_submit_gate_test.dart makes); the skill
  // lives one level up at the repo root. Fall back to the working directory
  // itself so running from the root still resolves.
  File repoFile(String path) {
    for (final candidate in ['../$path', path]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file;
      }
    }
    fail('could not find $path relative to ${Directory.current.path}');
  }

  final skill = repoFile('.claude/skills/release/SKILL.md').readAsStringSync();

  /// Prose assertions must survive markdown re-wrapping, so compare against
  /// the text with runs of whitespace collapsed to single spaces — a phrase
  /// split across a line break is still the same sentence.
  String flat(String text) => text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');

  group('the skill watches the run for the pushed commit (issue #153)', () {
    test('the lookup is scoped to the pushed SHA, not to recency', () {
      // The pushed head is captured before any polling: step 2 verified a
      // clean tree on main and step 5 just pushed, so HEAD is the commit the
      // release run will carry — for a TestFlight-only push no less than a
      // version bump.
      expect(skill, contains('SHA=\$(git rev-parse HEAD)'),
          reason: 'the lookup needs the pushed commit, and HEAD is it');

      // The exact commit-scoped lookup, with jq silenced on a miss
      // (`// empty`): plain '.[0].databaseId' prints the string "null",
      // which is non-empty, and the poll loop would exit on the first
      // attempt holding a bogus id.
      expect(
          skill,
          contains(
              "--commit \"\$SHA\" --json databaseId --jq '.[0].databaseId // empty'"),
          reason: 'the run must be found by its commit, never by recency');

      // The poll replaces the fixed sleep: registration can lag the push,
      // so the lookup retries — 30 attempts at 5-second spacing, ~2.5
      // minutes, the same budget the issue sweep's lookup allows.
      expect(skill, contains('for i in \$(seq 1 30)'),
          reason: 'the lookup must poll, not sleep-and-hope');
      expect(skill, contains('sleep 5'),
          reason: 'the poll needs spacing between attempts');

      // Downstream stays keyed on the pinned id: once $ID is the right run,
      // the watch, the failed-log read, and the build-number lookup (run
      // number + 1000) are automatically about this release.
      expect(skill, contains('gh run watch "\$ID"'),
          reason: 'the watch must consume the commit-scoped id, so a '
              'correct lookup makes every downstream step correct');
    });

    test('the fixed sleep and the newest-run lookup are gone', () {
      // The exact old lines, so they cannot creep back in a rewrite.
      expect(skill, isNot(contains('sleep 20')),
          reason: 'a fixed sleep cannot know when the run registers, and '
              'waiting longer does not make the newest run the right one');
      expect(
          skill,
          isNot(contains(
              'ID=\$(gh run list --repo wjdavis5/taxiGame --workflow=ios-release.yml --limit 1 --json databaseId --jq \'.[0].databaseId\')')),
          reason: 'the unscoped --limit 1 lookup is the defect itself — '
              'with every push to main firing the workflow, the newest run '
              'is whichever push landed last (issue #153)');
    });

    test('the skill refuses to fall back to the newest run', () {
      // The refusal guidance: an empty $ID must stop the release, not
      // broaden the search. Every push to main triggers the workflow and
      // the ios-release concurrency group queues rather than cancels, so
      // "the newest run" is very often another push's.
      final flatSkill = flat(skill);
      expect(flatSkill, contains('no run registered for the pushed commit'),
          reason: 'the failure must be named so the operator reports it '
              'instead of improvising a broader lookup');
      expect(flatSkill, contains('never fall back to the newest run'),
          reason: 'the fallback IS the defect — the newest run is easily '
              'another push\'s, and reporting its result and build number '
              'as the release\'s is the failure of #153');
      expect(flatSkill, contains('issue #153'),
          reason: 'the citation keeps the rationale findable from the doc');
    });
  });
}
