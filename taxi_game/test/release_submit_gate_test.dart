import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iOS release pipeline's submit gate (issues #89 and #93).
///
/// The gate decides "submit for App Store review or TestFlight only" from
/// App Store Connect, queried live by `tools/asc_version_state.rb`. Its
/// predecessor diffed `pubspec.yaml` against `HEAD~1`, so a version bump
/// whose own run died before the Submit step looked "unchanged" to every
/// later push — those runs went green, logged "Version unchanged", and the
/// version was never submitted at all (#89).
///
/// #93 is the opposite failure: the first run of that gate read a version
/// list that came back without the in-review 1.0.0 as `NONE` and tried to
/// submit over a live review, which Apple refused (build 1074). So the gate
/// now asks a second source — `GET /v1/reviewSubmissions?filter[app]=…` —
/// and answers `REVIEW_IN_FLIGHT` whenever a submission actively holds the
/// review slot, overriding everything the version records said; an empty
/// version list is a hard error, because a live app always has versions
/// and "no data" means the query landed wrong, not "nothing submitted".
///
/// #102 split that second source's verdict in two: a submission parked in
/// `UNRESOLVED_ISSUES` (where Apple leaves it after rejecting the version)
/// or `READY_FOR_REVIEW` (created, never confirmed) blocks a new one
/// exactly as a live review does — but no review is running and no push
/// can clear it. The old single "unfinished" verdict answered the
/// post-rejection version bump with a green TestFlight-only run and the
/// same "wait for Apple" message a live review gets, so the bump the docs
/// prescribed never submitted anything. `REVIEW_STUCK` is still
/// TestFlight-only (the 4d35205 policy: deploys stay green while a human
/// untangles App Store Connect) but never silent — the run emits a
/// `::warning::` naming the real recovery.
///
/// The gate lives in YAML and Ruby, so these tests pin its contract two
/// ways: text assertions over the workflow and the script (the exact set
/// of Apple states that may submit, the ordering of the decision branches,
/// the loud-failure rules), and behavioral tests that execute the real
/// script with both HTTP answers injected through its fixture env vars —
/// no network, no credentials. Those need `ruby`, which CI has and a dev
/// box may not; they skip with a reason rather than silently passing.
void main() {
  // flutter test runs with the package directory as the working directory
  // (the same assumption vehicle_sprites_test.dart makes for assets); the
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

  /// The states in which Apple still lets a version be edited AND whose
  /// resubmission needs no human decision. `INVALID_BINARY` is Apple
  /// rejecting the artifact itself, so the fix is a new build and the next
  /// push resubmits it — mechanical recovery, which is why it stayed when
  /// the rejection states were removed in #93.
  const preSubmissionStates = [
    'PREPARE_FOR_SUBMISSION',
    'INVALID_BINARY',
  ];

  /// #93: `REJECTED` and `METADATA_REJECTED` mean a person at Apple sent
  /// reasons someone must read and act on. This repo's automation pushes
  /// about hourly, and the pre-#93 policy auto-resubmitted on every push —
  /// firing unaddressed rejections at Apple with no human involved. Those
  /// states now resubmit only through a deliberate act: a version bump
  /// (new string → NONE) or the manual *Submit for App Store review*
  /// dispatch.
  const humanRejectionStates = [
    'REJECTED',
    'METADATA_REJECTED',
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

  /// Every `state` Apple's OpenAPI spec defines for a reviewSubmission,
  /// verbatim from the spec's `filter[state]` enum (the same seven the
  /// script's header quotes). `appleStates` above holds the parallel enum
  /// for appStoreVersion records; the two are different value sets, and
  /// #102's stuck pair must come from this one.
  const submissionStates = [
    'READY_FOR_REVIEW',
    'WAITING_FOR_REVIEW',
    'IN_REVIEW',
    'UNRESOLVED_ISSUES',
    'CANCELING',
    'COMPLETING',
    'COMPLETE',
  ];

  /// The reviewSubmission states that hold no review slot but will never
  /// clear themselves (issue #102): `UNRESOLVED_ISSUES` is where Apple
  /// parks a submission after rejecting the version — a human must resolve
  /// the rejection in App Store Connect — and `READY_FOR_REVIEW` is a
  /// submission created but never confirmed. Both block a new submission
  /// exactly as a live review does, so both stay TestFlight-only; the
  /// split exists so the run says which one it hit and names the one act
  /// that clears it, instead of the #93-era silence around a bump that
  /// could never submit.
  const stuckSubmissionStates = [
    'UNRESOLVED_ISSUES',
    'READY_FOR_REVIEW',
  ];

  group('the submit gate decides from App Store Connect (issues #89, #93)',
      () {
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
          reason: 'the submit set is exactly the two states whose '
              'resubmission is mechanical (#93 shrank it from four); growing '
              'or shrinking it is a behavior change that needs this test '
              'updated with it');

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

      // The #93 policy: human rejections are real Apple states (so they can
      // and do come back from the query) but sit outside the editable set —
      // routine pushes must not resubmit them.
      for (final state in humanRejectionStates) {
        expect(appleStates, contains(state),
            reason: '$state is not an appStoreState Apple can return');
        expect(editable, isNot(contains(state)),
            reason: '#93: $state carries reviewer reasons a human must '
                'address; resubmit via a version bump or the manual dispatch');
      }
    });

    test('a failed or untrustworthy query fails the run instead of guessing',
        () {
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

      // #93's purest failure mode: this app is live on the store, so an
      // empty version list means the query landed wrong (wrong app, wrong
      // key role, an API change) — an error, never "no version yet".
      expect(script, contains('returned an empty list'),
          reason: 'an empty appStoreVersions list is a broken answer for a '
              'live app; trusting it as NONE is what submitted over a live '
              'review in the build-1074 run');

      // The second source rejects the same broken shapes the first one
      // does (PR #100 review): a missing or JSON-null data array is not
      // "no submissions in flight" — that reading is the one that yields
      // NONE, the submit verdict, from an untrusted answer.
      expect(script, contains('reviewSubmissions returned no data array'),
          reason: 'an untrusted second-source answer must fail the run, '
              'never quietly mean "nothing in flight"');
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

      // One identity across the repo: the app id both queries use must be
      // the one CLAUDE.md's table binds to the App Store record.
      final claude = readRepoFile('CLAUDE.md');
      final appId =
          RegExp(r'App Store app ID \| `(\d+)`').firstMatch(claude)!.group(1);
      expect(script, contains("APP_ID = '$appId'"),
          reason: 'the script must query the app CLAUDE.md names, or it '
              'answers for some other app entirely');
    });

    test('NONE means "no record and nothing in flight", and only that', () {
      // The sentinel is the version-not-in-ASC case that must submit — so
      // it may only be printed after both queries succeeded AND the second
      // source agreed nothing is in flight (#93: a false NONE submitted
      // over a live review).
      expect(script, contains('if matching.empty?'));
      expect(script, contains("puts 'NONE'"));

      // The second source exists and is app-scoped, not version-scoped:
      // "never submit while a review submission is active, whatever
      // appStoreVersions says" is issue #93's requirement verbatim.
      expect(script, contains('/v1/reviewSubmissions?filter[app]='));
      expect(script, contains("puts 'REVIEW_IN_FLIGHT'"));

      // The classification's blocking default survived #102's split: done
      // is COMPLETE alone, the stuck pair is peeled off by name, and
      // everything else — COMPLETING, which fastlane's mirror of the spec
      // still lacks, nil, and the next state Apple invents — stays on the
      // in-flight side of the line. An enumerated *active* list could
      // never guarantee that; only a default can.
      expect(script, contains("== 'COMPLETE'"),
          reason: 'COMPLETE is the single finished state, so the reject '
              'keeps every other state blocking before the stuck pair is '
              'named');

      final decision = stepBlock('Decide whether to submit for review');
      expect(decision, contains(r'[ "$states" = "NONE" ]'),
          reason: 'no App Store Connect record for the version is the '
              'never-yet-submitted case — it must submit');
      expect(
        decision,
        contains(r'elif [ "$states" = "REVIEW_IN_FLIGHT" ]'),
        reason: 'an unfinished review submission must map to TestFlight '
            'only, overriding both NONE and editable-state verdicts',
      );
    });

    test('a stuck submission is its own verdict with its own recovery '
        '(issue #102)', () {
      // The stuck pair is pinned in the greppable %w[...] form, the same
      // way editable_states is: growing or shrinking the set is a behavior
      // change that must update this list with it.
      final match = RegExp(
        r'STUCK_SUBMISSION_STATES = %w\[([^\]]+)\]',
      ).firstMatch(script);
      expect(match, isNotNull,
          reason: 'the script must declare its stuck-state list in the '
              'greppable STUCK_SUBMISSION_STATES = %w[...] form this suite '
              'reads');
      final stuck = match!.group(1)!.split(RegExp(r'\s+'));

      expect(stuck, unorderedEquals(stuckSubmissionStates),
          reason: 'the stuck set is exactly the two states issue #102 '
              'names — a rejection\'s parking state and a never-confirmed '
              'draft');
      // A typo here would never match a real API response and every
      // rejection would silently read as REVIEW_IN_FLIGHT again — the
      // message #102 exists to deliver, lost. Every entry must be a real
      // reviewSubmission state.
      for (final state in stuck) {
        expect(submissionStates, contains(state),
            reason: '$state is not a reviewSubmission state Apple can return');
      }

      expect(script, contains("puts 'REVIEW_STUCK'"));

      final decision = stepBlock('Decide whether to submit for review');
      expect(
        decision,
        contains(r'elif [ "$states" = "REVIEW_STUCK" ]'),
        reason: 'the workflow must handle the stuck verdict as its own '
            'branch, before NONE or the per-record states could read a '
            'bump as submittable',
      );

      // Both blocking verdicts leave submit=false; the difference is that
      // the stuck one may not pass silently — the #102 failure was a
      // green run whose bump never submitted, so the branch must carry a
      // warning annotation that names the recovery.
      expect(
        decision,
        contains('::warning::'),
        reason: 'a bump that cannot submit must not look like a normal '
            'TestFlight-only run',
      );
      final warning =
          RegExp(r'::warning::([^\n]+)').firstMatch(decision)!.group(1)!;
      expect(warning, contains('App Store Connect'),
          reason: 'the recovery is a human act in App Store Connect');
      expect(warning, contains('bump'),
          reason: 'the warning must pre-empt the documented recovery that '
              'does not work while the submission sits there');
      expect(warning.toLowerCase(), contains('issue #102'),
          reason: 'the annotation names the issue that explains the state');
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
      // is the default, not the override. REVIEW_IN_FLIGHT sits between it
      // and NONE: the second source overrides every version-record verdict
      // (#93) but still yields to an explicit human choice. REVIEW_STUCK
      // slots in behind its sibling (#102): a live review is the harder
      // block and wins when both exist, while the stuck pair still
      // overrides the NONE a version bump would otherwise earn.
      final manualAt = decision.indexOf(r'[ "$manual" = "true" ]');
      final flightAt = decision.indexOf(r'[ "$states" = "REVIEW_IN_FLIGHT" ]');
      final stuckAt = decision.indexOf(r'[ "$states" = "REVIEW_STUCK" ]');
      final noneAt = decision.indexOf(r'[ "$states" = "NONE" ]');
      expect(manualAt, greaterThan(-1));
      expect(flightAt, greaterThan(-1));
      expect(stuckAt, greaterThan(-1),
          reason: 'the workflow must branch on REVIEW_STUCK at all');
      expect(noneAt, greaterThan(-1));
      expect(manualAt, lessThan(flightAt),
          reason: 'a ticked manual dispatch must submit regardless of what '
              'Apple reports');
      expect(flightAt, lessThan(noneAt),
          reason: 'REVIEW_IN_FLIGHT must be decided before NONE — a live '
              'submission blocks a new one even when the version list lacks '
              'the version entirely (#93)');
      expect(flightAt, lessThan(stuckAt),
          reason: 'a live review is the harder block: when one submission '
              'is in flight and another stuck, the in-flight verdict wins '
              '(the script decides the same way)');
      expect(stuckAt, lessThan(noneAt),
          reason: 'the stuck submission a rejection left behind overrides '
              'the NONE a version bump would otherwise earn (#102)');
    });

    test('the fixture seam injects both query bodies, no secrets needed', () {
      // The behavioral tests below drive the real script through these two
      // env vars; pin their names so the seam cannot drift silently.
      expect(script, contains('ASC_FIXTURE_APP_STORE_VERSIONS'));
      expect(script, contains('ASC_FIXTURE_REVIEW_SUBMISSIONS'));

      // Credentials are demanded only for queries that will really run, so
      // a fully-injected run works with no ASC_* secrets at all — that is
      // what lets the Dart suite execute the Ruby decision logic offline.
      expect(script, contains('FIXTURES.values.any?'));
    });
  });

  // The script exposes its two HTTP answers as fixture env vars precisely
  // so this group can run the real decision logic end to end: the fixtures
  // are the full JSON bodies, stdout/stderr/exit code come back through
  // Process.runSync, and nothing touches the network or a secret.
  group('the gate script over fixture responses (issues #93, #102)', () {
    /// `ruby --version` output, or null when ruby is not installed. The
    /// behavioral tests need the real interpreter; the pinned-contract
    /// tests above do not.
    String? probeRuby() {
      try {
        final probe = Process.runSync('ruby', ['--version']);
        return probe.exitCode == 0 ? (probe.stdout as String).trim() : null;
      } on ProcessException {
        return null;
      }
    }

    final ruby = probeRuby();

    // Loud, not silent: the skip reason lands in the runner output on any
    // machine without ruby (the primary dev box is Windows and has none),
    // while CI — the ubuntu-latest image behind the verify job's
    // `flutter test` — ships Ruby 3.2.3 and runs these for real.
    final skipWithoutRuby = ruby == null
        ? 'ruby is not installed on this machine, so the real gate script '
            'cannot execute here; these tests run in CI, whose ubuntu-latest '
            'image ships ruby (probe: `ruby --version` failed with '
            'ProcessException)'
        : null;

    /// A minimal appStoreVersions record. A null [state] omits the
    /// attribute entirely — the shape a future Apple change could produce.
    Map<String, Object> versionRecord(
      String id,
      String versionString, [
      String? state,
    ]) {
      return {
        'type': 'appStoreVersions',
        'id': id,
        'attributes': <String, Object>{
          'versionString': versionString,
          if (state != null) 'appStoreState': state,
        },
      };
    }

    /// A minimal reviewSubmissions record; a null [state] omits it, which
    /// the gate must treat as active rather than finished.
    Map<String, Object> submissionRecord(String id, [String? state]) {
      return {
        'type': 'reviewSubmissions',
        'id': id,
        'attributes': <String, Object>{
          'platform': 'IOS',
          if (state != null) 'state': state,
        },
      };
    }

    String body(List<Map<String, Object>> records) =>
        jsonEncode(<String, Object>{'data': records});

    ProcessResult runGate({
      required String versions,
      required String submissions,
      String ask = '1.0.1',
    }) {
      final scriptPath =
          repoFile('tools/asc_version_state.rb').resolveSymbolicLinksSync();
      return Process.runSync(
        'ruby',
        [scriptPath, ask],
        environment: {
          'ASC_FIXTURE_APP_STORE_VERSIONS': versions,
          'ASC_FIXTURE_REVIEW_SUBMISSIONS': submissions,
        },
      );
    }

    test(
      'an empty appStoreVersions list fails the step instead of saying NONE',
      () {
        final result = runGate(
          versions: body([]),
          submissions: body([submissionRecord('s1', 'COMPLETE')]),
        );

        expect(result.exitCode, 1,
            reason: 'a live app always has version records, so an empty '
                'list is a broken answer (#93) — never "no version yet"');
        expect(result.stdout, isNot(contains('NONE')));
        expect(result.stdout, isNot(contains('REVIEW_IN_FLIGHT')));
        expect(result.stderr, contains('empty list'),
            reason: 'the failure must name the broken answer so the CI log '
                'shows what came back');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a version missing from the list plus an active submission is '
      'REVIEW_IN_FLIGHT, never NONE',
      () {
        // The build-1074 scenario itself: the version list came back
        // without the in-review version, and the pre-#93 gate read that as
        // NONE and tried to submit.
        final result = runGate(
          versions: body([versionRecord('v1', '1.0.0', 'WAITING_FOR_REVIEW')]),
          submissions: body([
            submissionRecord('s1', 'WAITING_FOR_REVIEW'),
            submissionRecord('s2', 'COMPLETE'),
          ]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'REVIEW_IN_FLIGHT');
        // The inventory that #93's postmortem was missing: what the list
        // DID contain goes to stderr even though the verdict comes from the
        // second source.
        expect(result.stderr, contains('1.0.0=WAITING_FOR_REVIEW'));
      },
      skip: skipWithoutRuby,
    );

    test(
      'NONE only prints when the second source agrees nothing is in flight',
      () {
        final result = runGate(
          versions: body([versionRecord('v1', '1.0.0', 'READY_FOR_SALE')]),
          submissions: body([submissionRecord('s1', 'COMPLETE')]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'NONE');
        expect(result.stderr, contains('1.0.0=READY_FOR_SALE'),
            reason: 'the no-match path must log the returned inventory so a '
                'wrong-looking NONE is diagnosable from the CI log');
      },
      skip: skipWithoutRuby,
    );

    test(
      'an active submission overrides an editable version state',
      () {
        final result = runGate(
          versions: body([
            versionRecord('v1', '1.0.1', 'PREPARE_FOR_SUBMISSION'),
          ]),
          submissions: body([submissionRecord('s1', 'IN_REVIEW')]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'REVIEW_IN_FLIGHT',
            reason: 'the version record alone would say editable; the '
                'unfinished submission wins');
      },
      skip: skipWithoutRuby,
    );

    test(
      'an editable version with no active submission prints the state itself',
      () {
        final result = runGate(
          versions: body([
            versionRecord('v1', '1.0.1', 'PREPARE_FOR_SUBMISSION'),
          ]),
          submissions: body([submissionRecord('s1', 'COMPLETE')]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'PREPARE_FOR_SUBMISSION',
            reason: 'the one verdict the workflow may submit on');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a submission state the script does not know counts as in flight',
      () {
        // COMPLETING is in Apple's live filter[state] enum but absent from
        // fastlane's mirror of the spec — the exact drift an enumerated
        // active-list would mishandle. The stateless record is the same
        // rule one step further: a shape change must block, not pass.
        final result = runGate(
          versions: body([
            versionRecord('v1', '1.0.1', 'PREPARE_FOR_SUBMISSION'),
          ]),
          submissions: body([
            submissionRecord('s1', 'COMPLETE'),
            submissionRecord('s2', 'COMPLETING'),
            submissionRecord('s3', null),
          ]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'REVIEW_IN_FLIGHT');
        expect(result.stderr, contains('COMPLETING'));
        expect(result.stderr, contains('UNKNOWN'),
            reason: 'a record with no state attribute must be reported as '
                'UNKNOWN, not silently skipped');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a matching record with no appStoreState prints UNKNOWN, never a guess',
      () {
        final result = runGate(
          versions: body([versionRecord('v1', '1.0.1', null)]),
          submissions: body([submissionRecord('s1', 'COMPLETE')]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'UNKNOWN',
            reason: 'UNKNOWN is not in the workflow\'s editable list, so an '
                'unrecognizable state can never trigger a submission');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a broken injected body fails the run rather than guessing',
      () {
        final result = runGate(
          versions: '{not json',
          submissions: body([submissionRecord('s1', 'COMPLETE')]),
        );

        expect(result.exitCode, 1,
            reason: 'the seam is also a parser boundary: unparseable input '
                'is an error, not a default verdict');
        expect(result.stdout, isNot(contains('NONE')));
      },
      skip: skipWithoutRuby,
    );

    test(
      'a missing or null data array on the second source fails the run, '
      'never "nothing in flight"',
      () {
        // The PR #100 review finding: `['data'] || []` read both of these
        // shapes as an empty list — the one answer that yields NONE, the
        // submit verdict — so an untrusted 200 on the second source could
        // still submit over a live review. The version list here is a
        // healthy no-match, which is exactly the pairing where the broken
        // second source used to produce NONE.
        for (final broken in ['{"data": null}', '{}']) {
          final result = runGate(
            versions: body([versionRecord('v1', '1.0.0', 'READY_FOR_SALE')]),
            submissions: broken,
          );

          expect(result.exitCode, 1, reason: 'body $broken');
          expect(result.stdout, isNot(contains('NONE')), reason: 'body $broken');
          expect(result.stderr, contains('no data array'),
              reason: 'body $broken — the failure must name the broken '
                  'shape');
        }
      },
      skip: skipWithoutRuby,
    );

    test(
      'an empty submissions list stays the legal "nothing in flight" answer',
      () {
        // Only missing/null is a broken answer; [] is the healthy state of
        // an app whose every submission has COMPLETEd (or that has never
        // submitted), and the #93 fix must keep submitting on it.
        final result = runGate(
          versions: body([versionRecord('v1', '1.0.0', 'READY_FOR_SALE')]),
          submissions: body([]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'NONE',
            reason: 'the guard must not over-tighten: an empty list really '
                'is "nothing in flight"');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a rejection parked in UNRESOLVED_ISSUES after a bump is REVIEW_STUCK, '
      'never NONE (issue #102)',
      () {
        // The #102 scenario itself: 1.0.0 was rejected, the developer
        // bumped to 1.0.1 exactly as the docs prescribed, and the rejected
        // submission still sits unresolved. The bump earns no NONE while
        // it exists — and the verdict must say what is actually blocking,
        // not the #93-era "unfinished" line that reads as "wait for Apple".
        final result = runGate(
          versions: body([versionRecord('v1', '1.0.0', 'READY_FOR_SALE')]),
          submissions: body([submissionRecord('s1', 'UNRESOLVED_ISSUES')]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'REVIEW_STUCK');
        expect(result.stdout, isNot(contains('NONE')));
        expect(result.stderr, contains('UNRESOLVED_ISSUES'),
            reason: 'the CI log must name the parked state');
        expect(result.stderr, contains('App Store Connect'),
            reason: 'and the one act that clears it — no push can');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a never-confirmed READY_FOR_REVIEW draft blocks an editable version '
      '(issue #102)',
      () {
        final result = runGate(
          versions: body([
            versionRecord('v1', '1.0.1', 'PREPARE_FOR_SUBMISSION'),
          ]),
          submissions: body([submissionRecord('s1', 'READY_FOR_REVIEW')]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'REVIEW_STUCK',
            reason: 'the version record alone would submit; the stuck draft '
                'blocks it exactly as a live review would, and the verdict '
                'must say what kind of block it is');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a live review outranks a stuck one when both exist (issue #102)',
      () {
        // Precedence inside the script mirrors the workflow's branch
        // order: REVIEW_IN_FLIGHT is the harder block — Apple is actively
        // holding the slot — so it wins over REVIEW_STUCK the same way it
        // wins over NONE.
        final result = runGate(
          versions: body([versionRecord('v1', '1.0.0', 'REJECTED')]),
          submissions: body([
            submissionRecord('s1', 'UNRESOLVED_ISSUES'),
            submissionRecord('s2', 'IN_REVIEW'),
          ]),
        );

        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), 'REVIEW_IN_FLIGHT');
      },
      skip: skipWithoutRuby,
    );
  });
}
