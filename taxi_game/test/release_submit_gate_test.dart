import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS release pipeline's submit gate (issue #89).
///
/// The gate decides "submit for App Store review or TestFlight only" from the
/// version's state in App Store Connect, queried live by
/// `tools/asc_version_state.rb`. Its predecessor diffed `pubspec.yaml`
/// against `HEAD~1`, so a version bump whose own run died before the Submit
/// step looked "unchanged" to every later push — those runs went green,
/// logged "Version unchanged", and the version was never submitted at all.
///
/// The gate lives in YAML and Ruby, languages this suite cannot execute, so
/// these tests pin its contract by reading the two files: the regression
/// markers of the old diff gate, the exact set of Apple states that may
/// submit, and the loud-failure rule that a failed query must never be
/// quietly read as "TestFlight only" — the precise silence the issue is
/// about. The truth table itself (which state combinations submit) was
/// additionally exercised against the real shell fragment when the gate was
/// written; these assertions keep it from drifting afterwards.
void main() {
  // flutter test runs with the package directory as the working directory
  // (the same assumption vehicle_sprites_test.dart makes for assets); the
  // pipeline files live one level up at the repo root. Fall back to the
  // working directory itself so running from the root still resolves.
  String readRepoFile(String path) {
    for (final candidate in ['../$path', path]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
    }
    fail('could not find $path relative to ${Directory.current.path}');
  }

  final workflow = readRepoFile('.github/workflows/ios-release.yml');
  final script = readRepoFile('tools/asc_version_state.rb');

  /// The whole step block, from its `- name:` line to the next step's, so
  /// assertions cannot accidentally match text from some other step.
  String stepBlock(String stepName) {
    final start = workflow.indexOf('- name: $stepName');
    expect(start, greaterThan(-1), reason: 'step "$stepName" is missing');
    final next = workflow.indexOf('\n      - name: ', start + 1);
    return workflow.substring(start, next == -1 ? workflow.length : next);
  }

  /// Every `appStoreState` value Apple's spec defines, verbatim from
  /// fastlane's mirror of the App Store Connect API spec
  /// (spaceship/lib/spaceship/connect_api/models/app_store_version.rb) —
  /// including legacy values the live API may never return, because the
  /// gate must classify anything Apple *could* send, not just what it has.
  const appleStates = [
    'ACCEPTED',
    'DEVELOPER_REJECTED',
    'DEVELOPER_REMOVED_FROM_SALE',
    'IN_REVIEW',
    'INVALID_BINARY',
    'METADATA_REJECTED',
    'PENDING_APPLE_RELEASE',
    'PENDING_CONTRACT',
    'PENDING_DEVELOPER_RELEASE',
    'PREORDER_READY_FOR_SALE',
    'PREPARE_FOR_SUBMISSION',
    'PROCESSING_FOR_APP_STORE',
    'READY_FOR_REVIEW',
    'READY_FOR_SALE',
    'REJECTED',
    'REMOVED_FROM_SALE',
    'REPLACED_WITH_NEW_VERSION',
    'WAITING_FOR_EXPORT_COMPLIANCE',
    'WAITING_FOR_REVIEW',
    'NOT_APPLICABLE',
  ];

  /// The states in which Apple still lets a version be edited — no live
  /// submission exists for it. This is the issue's rule ("submit when no
  /// version is already submitted, in review or approved") plus the two
  /// rejection states, where resubmitting the same string is the standard
  /// same-version recovery path.
  const preSubmissionStates = [
    'PREPARE_FOR_SUBMISSION',
    'REJECTED',
    'METADATA_REJECTED',
    'INVALID_BINARY',
  ];

  /// States that carry (or may carry) a live submission and must never
  /// auto-submit. DEVELOPER_REJECTED is deliberately here: it is an explicit
  /// human withdrawal, not a pipeline failure to recover from.
  const handledStates = [
    'WAITING_FOR_REVIEW',
    'IN_REVIEW',
    'PENDING_APPLE_RELEASE',
    'PENDING_DEVELOPER_RELEASE',
    'PROCESSING_FOR_APP_STORE',
    'READY_FOR_SALE',
    'DEVELOPER_REJECTED',
    'DEVELOPER_REMOVED_FROM_SALE',
    'REMOVED_FROM_SALE',
  ];

  group('the submit gate decides from App Store Connect (issue #89)', () {
    test('the gate queries Apple, never the previous commit', () {
      expect(workflow, contains('tools/asc_version_state.rb'),
          reason: 'the decision step must ask App Store Connect for the '
              'version state');

      // The old gate's exact mechanism. If any of these reappear, a bump
      // whose own run failed before Submit is unsubmitted forever again.
      expect(workflow, isNot(contains('HEAD~1')));
      expect(workflow, isNot(contains('git show')));
      expect(workflow, isNot(contains('Version unchanged')),
          reason: '"Version unchanged" was the silent TestFlight-only verdict '
              'that lost the submission');
      expect(workflow, contains('fetch-depth: 1'),
          reason: 'no step reads git history any more, so checking out the '
              'previous commit would be cost without purpose');
    });

    test('only Apple-editable states may submit; everything else cannot', () {
      final match = RegExp(r'editable_states="([^"]+)"').firstMatch(workflow);
      expect(match, isNotNull,
          reason: 'the workflow must declare its editable-state list in the '
              'greppable editable_states="..." form this suite reads');
      final editable = match!.group(1)!.split(RegExp(r'\s+'));

      expect(editable, unorderedEquals(preSubmissionStates),
          reason: 'the submit set is exactly the four pre-submission states; '
              'growing it is a behavior change that needs this test updated '
              'with it');

      // A typo in the list would never match a real API response, so every
      // run would quietly classify its version as handled — the #89 silence
      // in the other direction. Every entry must be a real Apple value.
      for (final state in editable) {
        expect(appleStates, contains(state),
            reason: '$state is not an appStoreState Apple can return');
      }

      // The handled set is the documented complement (the workflow's shell
      // sends anything not editable to TestFlight-only), and it is held to
      // the same spelling standard — REMOVED_FROM_STORE, for instance, is a
      // plausible misspelling of the real REMOVED_FROM_SALE that would
      // never match anything Apple actually returns.
      for (final state in handledStates) {
        expect(appleStates, contains(state),
            reason: '$state is not an appStoreState Apple can return');
        expect(editable, isNot(contains(state)),
            reason: '$state has a live submission; Apple rejects a second '
                'submission for the same version string');
      }
    });

    test('a failed query fails the run instead of guessing', () {
      final decision = stepBlock('Decide whether to submit for review');

      // The substitution's exit status propagates through set -e only when
      // nothing swallows it — so the exact assignment matters: no `|| true`,
      // no `|| echo NONE`, no default that would turn an API outage into a
      // green TestFlight-only run.
      expect(decision, contains('set -euo pipefail'));
      expect(
        decision,
        contains(r'states="$(ruby tools/asc_version_state.rb "$current")"'),
        reason: 'a fallback appended to this line is how a query failure '
            'would silently become "TestFlight only"',
      );

      // The script's half of the contract: every failure path exits 1.
      expect(script, contains('def fail!'));
      expect(script, contains('exit 1'),
          reason: 'failures must exit non-zero for set -e to see them');
      expect(script, contains('unless response.code.to_i == 200'),
          reason: 'a non-200 answer from Apple is a failure, not "NONE"');
    });

    test('the query signs from the environment and targets this app', () {
      final decision = stepBlock('Decide whether to submit for review');
      for (final secret in [
        'ASC_KEY_ID: ',
        'ASC_ISSUER_ID: ',
        'ASC_PRIVATE_KEY: ',
      ]) {
        expect(decision, contains(secret),
            reason: 'the query step must be handed the ASC secrets; it runs '
                'before the step that installs the .p8 key file');
      }

      // A key-file lookup would break the step ordering the gate depends
      // on: this query deliberately runs before any key file exists on
      // disk, so it must read everything from the environment. (The paths
      // checked are the two asc.rb searches for an installed key.)
      expect(script, contains("ENV.fetch('ASC_PRIVATE_KEY')"));
      expect(script, isNot(contains('private_keys')));
      expect(script, isNot(contains('Downloads')));

      // One identity across the repo: the app id the script queries must be
      // the one CLAUDE.md's table binds to the App Store record.
      final claude = readRepoFile('CLAUDE.md');
      final appId =
          RegExp(r'App Store app ID \| `(\d+)`').firstMatch(claude)!.group(1);
      expect(script, contains("APP_ID = '$appId'"),
          reason: 'the script must query the app CLAUDE.md names, or it '
              'answers for some other app entirely');
    });

    test('NONE means "no record yet", and only that', () {
      // The sentinel is the version-not-in-ASC case that must submit — so
      // it may only be printed after a successful, fully-received query.
      expect(script, contains('if matching.empty?'));
      expect(script, contains("puts 'NONE'"));

      final decision = stepBlock('Decide whether to submit for review');
      expect(decision, contains(r'[ "$states" = "NONE" ]'),
          reason: 'no App Store Connect record for the version is the '
              'never-yet-submitted case — it must submit');
    });

    test('the submit step fires on the gate output; dispatch overrides', () {
      final decision = stepBlock('Decide whether to submit for review');
      expect(
        decision,
        contains(r'echo "submit=$submit" >> "$GITHUB_OUTPUT"'),
      );
      expect(
        workflow,
        contains("if: steps.review.outputs.submit == 'true'"),
        reason: 'the submit lane must stay gated on the decision step\'s '
            'output',
      );

      // Manual dispatch is the human escape hatch (force a submission
      // regardless of state), so it must be checked first — the state gate
      // is the default, not the override.
      final manualAt = decision.indexOf(r'[ "$manual" = "true" ]');
      final noneAt = decision.indexOf(r'[ "$states" = "NONE" ]');
      expect(manualAt, greaterThan(-1));
      expect(noneAt, greaterThan(-1));
      expect(manualAt, lessThan(noneAt),
          reason: 'a ticked manual dispatch must submit regardless of the '
              'state Apple reports');
    });
  });
}
