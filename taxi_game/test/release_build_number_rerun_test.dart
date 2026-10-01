import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The build number's re-run contract (issue #137).
///
/// Build numbers come from `github.run_number + 1000`, and `run_number` is
/// stable across re-runs: attempt 2 of run N still reports N, so re-running
/// a run whose upload already succeeded recomputes the same number and
/// Apple refuses the second upload as a duplicate. The release skill used
/// to close its "submit lane failed, upload succeeded" bullet with
/// "Re-running the failed run works too" — advice that can only produce a
/// red re-run, discovered only after paying for the macOS build again.
///
/// The fix is deliberately documentation, not arithmetic. Folding
/// `run_attempt` into the number (`run_number + run_attempt - 1`) would
/// make a re-run of run N mint run N+1's build number, and this repo's
/// automation pushes about hourly — so that newer run has almost always
/// uploaded the number already, trading a rare duplicate (someone re-runs
/// an uploaded run) for an expected one (every re-run collides with the
/// next push). The one re-run that IS safe keeps its advice: a failed
/// state query fails before any upload exists, so re-running it cannot
/// duplicate anything.
///
/// These tests pin that contract the way release_submit_gate_test.dart
/// pins the gate: text assertions over the shipped files — no network, no
/// credentials, exactly the parts of the issue that can be coded.
void main() {
  // flutter test runs with the package directory as the working directory
  // (the same assumption release_submit_gate_test.dart makes); the
  // pipeline files live one level up at the repo root. Fall back to the
  // working directory itself so running from the root still resolves.
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

  final skill = readRepoFile('.claude/skills/release/SKILL.md');
  final claude = readRepoFile('CLAUDE.md');
  final workflow = readRepoFile('.github/workflows/ios-release.yml');

  /// Prose assertions must survive markdown re-wrapping, so compare against
  /// the text with runs of whitespace collapsed to single spaces — a phrase
  /// split across a line break is still the same sentence.
  String flat(String text) => text.replaceAll(RegExp(r'[ \t\r\n]+'), ' ');

  /// The whole step block, from its `- name:` line to the next step's, so
  /// assertions cannot accidentally match text from some other step.
  String stepBlock(String stepName) {
    final start = workflow.indexOf('- name: $stepName');
    expect(start, greaterThan(-1), reason: 'step "$stepName" is missing');
    final next = workflow.indexOf('\n      - name: ', start + 1);
    return workflow.substring(start, next == -1 ? workflow.length : next);
  }

  group('a re-run is not the recovery for a failed submit (issue #137)', () {
    test('the skill no longer claims re-running a failed run works', () {
      // The exact false sentence, so it cannot creep back in a rewrite.
      expect(skill, isNot(contains('Re-running the failed run works too')),
          reason: 'a re-run recomputes the same build number, so this '
              'advice can only end in a duplicate-upload rejection');

      // Its replacement names the mechanism and the working recovery:
      // run_number stability makes the re-run a duplicate, and the next
      // push — not the re-run — is what gets a fresh number.
      final flatSkill = flat(skill);
      expect(flatSkill, contains('`run_number` is stable across re-runs'),
          reason: 'the skill must say WHY the re-run fails, or the advice '
              'reads as arbitrary');
      expect(flatSkill, contains('refuses the upload as a duplicate'),
          reason: 'the failure mode must be named so the red re-run is '
              'recognizable when it happens anyway');
      expect(flatSkill, contains('the next push gets a fresh number'),
          reason: 'the recovery must be the push, never the re-run');
    });

    test('the duplicate-build-number bullet names a re-run as a cause', () {
      // The bullet used to blame manual uploads alone; a re-run of an
      // already-uploaded run is the other way this presents, and knowing
      // it points the operator at the run list instead of hunting for a
      // manual upload that never happened.
      expect(flat(skill), contains('was re-run'),
          reason: 'the duplicate diagnosis must list the re-run cause '
              'alongside the manual-upload one');
      expect(flat(skill), contains('does not change on a re-run'),
          reason: 'and say why a re-run reproduces the same number');
    });

    test('the safe re-run advice — a failed state query — survives', () {
      // Over-correction guard: the state-query failure happens before any
      // upload exists, so re-running THAT run cannot duplicate anything.
      // Deleting the advice wholesale would trade working recovery for
      // nothing. (The wording lives in the state-query bullet, issue #93.)
      expect(
          flat(skill), contains('App Store Connect outage (a re-run fixes it)'),
          reason: 'a query failure precedes the upload, so that re-run is '
              'the one case where re-running is correct advice');
    });

    test('CLAUDE.md carries the same caveat on its build-number sentence', () {
      // CLAUDE.md's publishing section is the manual reference; without
      // the caveat it re-teaches the re-run as harmless.
      final flatClaude = flat(claude);
      expect(flatClaude, contains('`run_number` is stable across re-runs'),
          reason: 'the caveat must live where the run_number + 1000 rule is '
              'stated');
      expect(flatClaude, contains('never by re-running the failed run'),
          reason: 'the recovery direction must match the skill\'s');
    });

    test('the workflow comment pins the arithmetic it refuses to change', () {
      final resolve = stepBlock('Resolve build and version numbers');

      // The computation itself is unchanged: the run counter plus the
      // offset, nothing else. This is the line every downstream consumer
      // (altool upload, deliver attach, artifact names) keys off.
      expect(resolve,
          contains(r'build_number=$(( ${{ github.run_number }} + 1000 ))'),
          reason: 'the build number must stay run_number + 1000 — the fix '
              'for #137 is documentation, not arithmetic');

      // run_attempt may explain itself in comments but must never reach an
      // expression: attempt-aware numbering would make a re-run of run N
      // mint run N+1's number, which this repo's hourly pushes have almost
      // always uploaded already.
      final expressions = RegExp(r'\$\{\{([^}]*)\}\}')
          .allMatches(resolve)
          .map((match) => match.group(1)!);
      for (final expression in expressions) {
        expect(expression, isNot(contains('run_attempt')),
            reason: 'run_attempt must stay out of the build number — folding '
                'it in trades a rare duplicate for an expected one (#137)');
      }

      // The comment that keeps the next editor from "fixing" this: the
      // stability claim and the deliberate exclusion, at the step itself.
      expect(resolve, contains('re-run-stable'),
          reason: 'the step must document run_number\'s re-run stability '
              'where the number is computed');
      expect(resolve, contains('deliberately not folded in'),
          reason: 'and record that excluding run_attempt is a decision, not '
              'an oversight');
      expect(resolve, contains('altool refuses it as a duplicate'),
          reason: 'the failure the comment predicts must match the failure '
              'the skill documents');
    });
  });
}
