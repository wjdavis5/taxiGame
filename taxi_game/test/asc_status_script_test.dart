import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release skill's App Store Connect status helper (issue #115).
///
/// `asc.rb` builds each request's JWT with a kid header naming `ASC_KEY_ID`
/// from `.env`, then signs it with a key file it finds on disk. The old
/// lookup globbed `AuthKey_*.p8` across `~/Downloads` and
/// `~/.appstoreconnect/private_keys` and took the first hit, so a machine
/// with two keys — a stale one sitting in `~/Downloads`, say — signed every
/// request with the wrong key while the header still claimed `ASC_KEY_ID`,
/// and Apple's API answered HTTP 401 to every call. The lookup now derives
/// the one filename the header promises (`AuthKey_<ASC_KEY_ID>.p8`),
/// accepts it from either folder, and aborts naming the file and both
/// folders when no such file exists — before anything is signed.
///
/// The listing check failed silent the same way (issue #162): its three
/// query status codes were assigned and never read, so an API error — an
/// expired JWT answers 401 — returned a body with no `data` key, the
/// `|| []` fallbacks skipped every loop, and the output was a bare
/// `LISTING` header indistinguishable from a checked-and-complete one.
/// And the screenshot side had no EMPTY marker at all: a localization
/// with zero screenshot sets printed nothing, and a set holding zero
/// screenshots printed a bare count. `print_blockers` now aborts on
/// non-200 the way `builds` and `editable_version` always did, and marks
/// every empty state with `*** EMPTY ***`.
///
/// The version report lied the same way (issue #170): all three of its
/// query status codes were assigned and never read, so when Apple's API
/// errored — an expired JWT answers 401 — the build-link query's error
/// body read as "attached build: NONE", the build detail's empty
/// attributes as "attached build:  ()", and the submission's non-200 as
/// "submitted for review: no". Those are the lines the release skill's
/// step 1 reads as authoritative, so `print_version` now aborts on
/// non-200 like `builds` always did — with one carve-out: the submission
/// query's 404 is Apple's own "no submission on record" and still prints
/// no.
///
/// The contract is pinned the same two ways release_submit_gate_test.dart
/// pins the submit gate: text assertions over the script source, which run
/// anywhere, and behavioral tests that execute the real `private_key_path`,
/// `print_blockers`, and `print_version` — the first against a fake HOME
/// laid out by the test, the others against fixture API answers served by
/// a redefined `get`. Those need `ruby`, which CI has and a dev box may
/// not; they skip with a reason rather than silently passing.
void main() {
  // flutter test runs with the package directory as the working directory
  // (the same assumption release_submit_gate_test.dart makes); the script
  // lives one level up under .claude/. Fall back to the working directory
  // itself so running from the repo root still resolves.
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

  final script = readRepoFile('.claude/skills/release/scripts/asc.rb');

  group('the helper signs with the key ASC_KEY_ID names (issue #115)', () {
    test('the filename is derived from ASC_KEY_ID, never globbed', () {
      // The exact name the kid header makes the server check the signature
      // against; anything else signs with one key while claiming another.
      expect(script, contains("AuthKey_#{env.fetch('ASC_KEY_ID')}.p8"),
          reason: 'the signing file must be derived from the same id the '
              'JWT header claims, or Apple answers 401 (issue #115)');

      // The old lookup's mechanism: a Dir[] glob over every key on the
      // machine, then a silent take-the-first. Either half coming back
      // means the wrong key can sign again.
      expect(script, isNot(contains('Dir[')),
          reason: 'a glob over every AuthKey_*.p8 on the machine cannot tie '
              'the file to ASC_KEY_ID - with two keys present, the first '
              'hit signs');
      expect(script, isNot(contains('candidates.first')),
          reason: 'first-hit selection is how the ~/Downloads key won the '
              'glob while ASC_KEY_ID named the other one');
    });

    test('the exact-named key is accepted from either conventional folder',
        () {
      // The two folders xcodebuild and fastlane search by convention (and
      // the ones CI writes the key into), pinned so the lookup cannot
      // drift to a place the release skill never installs to.
      expect(script, contains("File.expand_path('~/Downloads')"));
      expect(script,
          contains("File.expand_path('~/.appstoreconnect/private_keys')"));
    });

    test('a missing key aborts naming the file and both folders', () {
      // Static half of the loud failure: the abort's message interpolates
      // the derived filename and the joined folder list; the behavioral
      // test below checks what a run actually prints.
      expect(script, contains('abort("missing #{name}'));
      expect(script, contains("dirs.join(' or ')"));
    });

    test('the seams the behavioral tests cut along still exist', () {
      // runLookup below feeds ruby everything above `case ARGV[0]` and
      // then calls private_key_path by name; restructure away either and
      // this names what the harness needs updated with it.
      expect(script, contains('def private_key_path'));
      expect(script, contains('case ARGV[0]'));
    });
  });

  group('the listing check fails loud on every gap (issue #162)', () {
    test('each listing query aborts when Apple answers non-200', () {
      // The three queries' codes were assigned and never read, so a 401
      // produced a body without 'data', every loop was skipped, and the
      // output was a bare LISTING header that read as a complete listing.
      // Each now carries the builds/editable_version contract (asc.rb's
      // own lines 74 and 80 when this landed): abort naming the code.
      expect(
          script,
          contains(
              'abort("localizations query failed: HTTP #{code}") unless code == 200'));
      expect(
          script,
          contains(
              'abort("screenshot sets query failed: HTTP #{c2}") unless c2 == 200'));
      expect(
          script,
          contains(
              'abort("screenshots query failed: HTTP #{c3}") unless c3 == 200'));
    });

    test('every empty screenshot state prints a *** EMPTY *** marker', () {
      // The three text fields always had their marker; the screenshot side
      // now does too. Without these, an empty localization list, a
      // localization with no screenshot sets, and a set holding zero
      // screenshots each printed either nothing or a bare count — every
      // one a listing Apple would reject, none a line a reader would stop
      // on.
      expect(script, contains('*** EMPTY *** no localizations'));
      expect(script, contains('*** EMPTY *** no screenshot sets'));
      expect(script, contains("n.zero? ? '*** EMPTY ***' : n.to_s"),
          reason: 'a zero-shot set must carry the marker where its count '
              'used to print');
    });
  });

  group('the version report fails loud on failed queries (issue #170)', () {
    test('the build-link and build-detail queries abort on non-200', () {
      // Both codes were assigned and never read, so an API error's body
      // flowed into the dig chain: no relationships key read as
      // "attached build: NONE" and empty attributes as
      // "attached build:  ()" — fiction the skill's step 1 trusts. Both
      // queries now carry the builds/editable_version contract: abort
      // naming the HTTP code.
      expect(
          script,
          contains('abort("version build link query failed: HTTP #{code}") '
              'unless code == 200'));
      expect(
          script,
          contains(
              'abort("build detail query failed: HTTP #{code}") unless code == 200'));
    });

    test('the submission query reads only 200 and 404 as answers', () {
      // The old ternary folded every non-200 into "no", so a 401 read as
      // "no submission" — the exact wrong answer to give while trusting an
      // expired key. 404 is Apple's own "no submission on record" and
      // stays a readable no; everything else aborts naming the code.
      expect(
          script,
          contains('abort("submission query failed: HTTP #{code}") unless '
              '[200, 404].include?(code)'));
      expect(script, contains("code == 200 ? 'YES' : 'no'"),
          reason: 'a 404 must still print no — the carve-out only stops '
              'errors from wearing the same answer');
    });
  });

  // The real function against a fake HOME: ruby is handed the script's
  // method definitions (not the file itself — its dispatcher fires a live
  // query on load) followed by a call to private_key_path, with HOME
  // pointing at the layout under test and the working directory inside a
  // throwaway git repository whose root holds the `.env` — repo_root
  // resolves through `git rev-parse`, exactly as in a real run.
  group('private_key_path over a fake HOME (issue #115)', () {
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
    // machine without ruby on PATH, while CI — the ubuntu-latest image
    // behind the verify job's `flutter test` — ships Ruby and runs these
    // for real.
    final skipWithoutRuby = ruby == null
        ? 'ruby is not on PATH on this machine, so the real lookup cannot '
            'execute here; these tests run in CI, whose ubuntu-latest image '
            'ships ruby (probe: `ruby --version` failed with '
            'ProcessException)'
        : null;

    /// Lays out [downloads] and [privateKeys] under a fake HOME, writes an
    /// `.env` naming [keyId] at a throwaway repo root, and runs the real
    /// private_key_path there.
    ProcessResult runLookup({
      required String keyId,
      List<String> downloads = const [],
      List<String> privateKeys = const [],
    }) {
      final sandbox = Directory.systemTemp.createTempSync('asc115');
      addTearDown(() {
        if (sandbox.existsSync()) {
          sandbox.deleteSync(recursive: true);
        }
      });

      final home = Directory('${sandbox.path}/home');
      final downloadsDir = Directory('${home.path}/Downloads')
        ..createSync(recursive: true);
      for (final name in downloads) {
        File('${downloadsDir.path}/$name').writeAsStringSync('decoy-key');
      }
      final keysDir = Directory('${home.path}/.appstoreconnect/private_keys')
        ..createSync(recursive: true);
      for (final name in privateKeys) {
        File('${keysDir.path}/$name').writeAsStringSync('real-key');
      }

      // A throwaway repository, not a bare directory: repo_root asks
      // `git rev-parse --show-toplevel`, and in a directory git does not
      // know the script looks for `/.env` at the drive root and aborts
      // before reaching the code under test. rev-parse answers for an
      // empty repo, so no commit is needed; git itself is a safe
      // dependency for a suite that runs inside a checkout.
      final repo = Directory('${sandbox.path}/repo')..createSync();
      File('${repo.path}/.env').writeAsStringSync('ASC_KEY_ID=$keyId\n');
      Process.runSync('git', ['init', '-q'], workingDirectory: repo.path);

      final cut = script.indexOf('case ARGV[0]');
      if (cut == -1) {
        fail('asc.rb no longer has its `case ARGV[0]` dispatcher — this '
            'harness cuts the source there so only the method definitions '
            'run');
      }
      return Process.runSync(
        'ruby',
        ['-e', '${script.substring(0, cut)}\nputs private_key_path'],
        workingDirectory: repo.path,
        environment: {'HOME': home.path},
      );
    }

    test(
      'a decoy that sorts first in ~/Downloads loses to the key ASC_KEY_ID '
      'names',
      () {
        // The issue's machine, replayed: a stale key alphabetically first
        // in the first-searched folder, the key ASC_KEY_ID actually names
        // in the second. The old first-hit glob picked the decoy — the
        // exact header/signing-key mismatch Apple answers 401.
        final result = runLookup(
          keyId: 'REALKEY9',
          downloads: ['AuthKey_AAADECOY.p8'],
          privateKeys: ['AuthKey_REALKEY9.p8'],
        );

        expect(result.exitCode, 0, reason: result.stderr as String);
        final picked = (result.stdout as String).trim().replaceAll('\\', '/');
        expect(
          picked,
          endsWith('.appstoreconnect/private_keys/AuthKey_REALKEY9.p8'),
          reason: 'the file must follow ASC_KEY_ID into whichever folder '
              'holds it',
        );
        expect(picked, isNot(contains('DECOY')),
            reason: 'the decoy sorting first in ~/Downloads is the file the '
                'old lookup signed with');
      },
      skip: skipWithoutRuby,
    );

    test(
      'the only key on the machine, correctly named, is still found',
      () {
        // The single-key machine the old code also served: the
        // exact-named file alone in ~/Downloads must keep working.
        final result = runLookup(
          keyId: 'REALKEY9',
          downloads: ['AuthKey_REALKEY9.p8'],
        );

        expect(result.exitCode, 0, reason: result.stderr as String);
        expect(
          (result.stdout as String).trim().replaceAll('\\', '/'),
          endsWith('Downloads/AuthKey_REALKEY9.p8'),
        );
      },
      skip: skipWithoutRuby,
    );

    test(
      'no file matching ASC_KEY_ID aborts before signing, naming both '
      'folders',
      () {
        // A present-but-wrongly-named key must not satisfy the lookup
        // silently; the failure names the wanted file and both folders it
        // looked in, so the fix on the machine is a rename, not a
        // debugging session.
        final result = runLookup(
          keyId: 'WANTEDKEY',
          downloads: ['AuthKey_AAADECOY.p8'],
        );

        expect(result.exitCode, 1);
        expect(result.stdout, isNot(contains('DECOY')));
        expect(result.stderr, contains('AuthKey_WANTEDKEY.p8'),
            reason: 'the message must name the file ASC_KEY_ID implies');
        expect(result.stderr, contains('Downloads'));
        expect(result.stderr, contains('.appstoreconnect'),
            reason: 'the message must name both folders searched');
      },
      skip: skipWithoutRuby,
    );
  });

  // The real print_blockers against fixture API answers: ruby is handed
  // the script's method definitions (everything above `case ARGV[0]`) with
  // `get` redefined to serve canned [code, body] pairs keyed by a path
  // fragment, then print_blockers is called by name. The fixtures always
  // include the appStoreVersions response editable_version makes first —
  // the listing queries only run once an editable version is found. No
  // credentials and no network are involved: jwt/env/private_key_path are
  // lazy and only the real get ever calls them.
  group('print_blockers over fixture answers (issue #162)', () {
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
    // machine without ruby on PATH, while CI — the ubuntu-latest verify
    // job's `flutter test`, and the macos PR job's — ships Ruby and runs
    // these for real.
    final skipWithoutRuby = ruby == null
        ? 'ruby is not on PATH on this machine, so the real listing check '
            'cannot execute here; these tests run in CI, whose images ship '
            'ruby (probe: `ruby --version` failed with ProcessException)'
        : null;

    /// The appStoreVersions answer print_blockers depends on through
    /// editable_version: one machine-editable version record.
    final versions200 = [
      200,
      '{"data":[{"id":"V1","attributes":{"appStoreState":'
          '"PREPARE_FOR_SUBMISSION","versionString":"1.2.3"}}]}',
    ];

    /// One localization with all three text fields set, so a test's eyes
    /// stay on the screenshot markers rather than the field rows.
    final localization = [
      200,
      '{"data":[{"id":"L1","attributes":{"description":"A taxi game",'
          '"keywords":"taxi","supportUrl":"https://example.com"}}]}',
    ];

    /// Runs the real print_blockers with `get` answering [fixtures] —
    /// path fragment => [code, json body]; the first fragment contained
    /// in the queried path wins. The fake returns the body parsed, the
    /// exact shape the real get hands the code for that answer.
    ProcessResult runBlockers(Map<String, List<Object>> fixtures) {
      final cut = script.indexOf('case ARGV[0]');
      if (cut == -1) {
        fail('asc.rb no longer has its `case ARGV[0]` dispatcher — this '
            'harness cuts the source there so only the method definitions '
            'run');
      }
      final pairs = fixtures.entries
          .map((e) => "'${e.key}' => [${e.value[0]}, '${e.value[1]}']")
          .join(',\n');
      final harness = '''
${script.substring(0, cut)}
FIXTURES = {
$pairs
}
def get(path)
  FIXTURES.each do |marker, (code, body)|
    next unless path.include?(marker)
    return [code, JSON.parse(body)]
  end
  abort('test fixture missing for ' + path)
end
print_blockers
''';
      return Process.runSync('ruby', ['-e', harness]);
    }

    test(
      'a localization with zero screenshot sets says EMPTY, not nothing',
      () {
        // The store page had no screenshot slots at all and the old output
        // printed nothing under the field rows — now the marker names it,
        // the same way a missing description always did.
        final result = runBlockers({
          'appStoreVersions?': versions200,
          'appStoreVersionLocalizations?': localization,
          'appScreenshotSets?': [200, '{"data":[]}'],
        });

        expect(result.exitCode, 0, reason: result.stderr as String);
        expect(result.stdout, contains('keywords'),
            reason: 'the reached localization still prints its field rows');
        expect(result.stdout, contains('*** EMPTY *** no screenshot sets'));
      },
      skip: skipWithoutRuby,
    );

    test(
      'a set holding zero screenshots says EMPTY with its display type',
      () {
        final result = runBlockers({
          'appStoreVersions?': versions200,
          'appStoreVersionLocalizations?': localization,
          'appScreenshotSets?': [
            200,
            '{"data":[{"id":"S1","attributes":{"screenshotDisplayType":'
                '"IPHONE_67"}}]}',
          ],
          '/appScreenshots?': [200, '{"data":[]}'],
        });

        expect(result.exitCode, 0, reason: result.stderr as String);
        expect(result.stdout, contains('IPHONE_67: *** EMPTY ***'),
            reason: 'a zero-shot set is a missing capture, and the marker '
                'must name which display type it is');
      },
      skip: skipWithoutRuby,
    );

    test(
      'an empty localization list cannot read as a complete listing',
      () {
        // A 200 with zero rows used to print a bare LISTING header —
        // byte-identical to a listing whose every field was checked and
        // found set.
        final result = runBlockers({
          'appStoreVersions?': versions200,
          'appStoreVersionLocalizations?': [200, '{"data":[]}'],
        });

        expect(result.exitCode, 0, reason: result.stderr as String);
        expect(result.stdout, contains('*** EMPTY *** no localizations'));
        expect(result.stdout, isNot(contains('description')),
            reason: 'no field rows exist to print, and none may be '
                'invented either');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a failed listing query aborts with the HTTP code',
      () {
        // The issue's own case: an expired JWT answers 401 to every call.
        // The old code never read the status, found no 'data' in the error
        // body, and let the `|| []` skip the loop — a pass.
        final result = runBlockers({
          'appStoreVersions?': versions200,
          'appStoreVersionLocalizations?': [401, '{"errors":[]}'],
        });

        expect(result.exitCode, 1);
        expect(result.stderr, contains('localizations query failed: HTTP 401'),
            reason: 'the abort must name the query and the code, like the '
                'builds and versions aborts');
        expect(result.stdout, isNot(contains('description')),
            reason: 'no field row may print off a failed query');
      },
      skip: skipWithoutRuby,
    );
  });

  // The real print_version against fixture API answers, the same harness
  // shape as print_blockers above: the script's method definitions with
  // `get` redefined to serve canned [code, body] pairs keyed by a path
  // fragment, then print_version called by name. The version-list answer
  // editable_version makes first is always fixture 'appStoreVersions?' —
  // note that fragment cannot collide with the version-detail path
  // (`appStoreVersions/V1?include=build` has a slash, not a question
  // mark), so the detail query gets its own 'include=build' fixture. No
  // credentials and no network are involved: jwt/env/private_key_path stay
  // lazy and only the real get would call them.
  group('print_version over fixture answers (issue #170)', () {
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
    // machine without ruby on PATH, while CI — the ubuntu-latest verify
    // job's `flutter test`, and the macos PR job's — ships Ruby and runs
    // these for real.
    final skipWithoutRuby = ruby == null
        ? 'ruby is not on PATH on this machine, so the real version report '
            'cannot execute here; these tests run in CI, whose images ship '
            'ruby (probe: `ruby --version` failed with ProcessException)'
        : null;

    /// The appStoreVersions answer print_version reaches everything else
    /// through editable_version: one machine-editable version record.
    final versions200 = [
      200,
      '{"data":[{"id":"V1","attributes":{"appStoreState":'
          '"PREPARE_FOR_SUBMISSION","versionString":"1.2.3",'
          '"releaseType":"MANUAL"}}]}',
    ];

    /// The version-detail answer: build B1 is attached to version V1.
    final includeBuild200 = [
      200,
      '{"data":{"id":"V1","relationships":{"build":{"data":{"id":"B1"}}}}}',
    ];

    /// Build B1's detail: build number 1074, processed and ready.
    final buildDetail200 = [
      200,
      '{"data":{"id":"B1","attributes":{"version":"1074",'
          '"processingState":"VALID"}}}',
    ];

    /// Runs the real print_version with `get` answering [fixtures] —
    /// path fragment => [code, json body]; the first fragment contained
    /// in the queried path wins. The fake returns the body parsed, the
    /// exact shape the real get hands the code for that answer.
    ProcessResult runVersion(Map<String, List<Object>> fixtures) {
      final cut = script.indexOf('case ARGV[0]');
      if (cut == -1) {
        fail('asc.rb no longer has its `case ARGV[0]` dispatcher — this '
            'harness cuts the source there so only the method definitions '
            'run');
      }
      final pairs = fixtures.entries
          .map((e) => "'${e.key}' => [${e.value[0]}, '${e.value[1]}']")
          .join(',\n');
      final harness = '''
${script.substring(0, cut)}
FIXTURES = {
$pairs
}
def get(path)
  FIXTURES.each do |marker, (code, body)|
    next unless path.include?(marker)
    return [code, JSON.parse(body)]
  end
  abort('test fixture missing for ' + path)
end
print_version
''';
      return Process.runSync('ruby', ['-e', harness]);
    }

    test(
      'a failed build-link query aborts, never "attached build: NONE"',
      () {
        // The issue's headline: the query's status went unread, its error
        // body had no relationships key, and the report said the version
        // had no build attached — a claim the skill's step 1 reads as
        // ground truth about App Store Connect.
        final result = runVersion({
          'appStoreVersions?': versions200,
          'include=build': [429, '{"errors":[]}'],
        });

        expect(result.exitCode, 1);
        expect(
            result.stderr, contains('version build link query failed: HTTP 429'));
        expect(result.stdout, isNot(contains('attached build: NONE')),
            reason: 'a query Apple throttled must not read as a version '
                'with no build attached');
      },
      skip: skipWithoutRuby,
    );

    test(
      'a failed build-detail query aborts before printing an empty build',
      () {
        // The detail's discarded status left attributes empty, and the
        // line printed both interpolations as nothing:
        // "attached build:  ()".
        final result = runVersion({
          'appStoreVersions?': versions200,
          'include=build': includeBuild200,
          '/v1/builds/': [500, '{"errors":[]}'],
        });

        expect(result.exitCode, 1);
        expect(result.stderr, contains('build detail query failed: HTTP 500'));
        expect(result.stdout, isNot(contains('attached build:  ()')));
      },
      skip: skipWithoutRuby,
    );

    test(
      'a failed submission query aborts, never "submitted for review: no"',
      () {
        // The old ternary folded every non-200 into no, so an expired
        // JWT's 401 read as "no submission" — reassuring fiction on a
        // release day.
        final result = runVersion({
          'appStoreVersions?': versions200,
          'include=build': includeBuild200,
          '/v1/builds/': buildDetail200,
          'appStoreVersionSubmission': [401, '{"errors":[]}'],
        });

        expect(result.exitCode, 1);
        expect(result.stderr, contains('submission query failed: HTTP 401'));
        expect(result.stdout, isNot(contains('submitted for review: no')));
        // The two build lines above it came from 200s and may stand.
        expect(result.stdout, contains('attached build: 1074 (VALID)'));
      },
      skip: skipWithoutRuby,
    );

    test(
      'a 404 from the submission query is Apple saying none, not an error',
      () {
        // No submission on record is a fact the report must be able to
        // state — the carve-out exists so fail-closed did not cost the
        // readable answer.
        final result = runVersion({
          'appStoreVersions?': versions200,
          'include=build': includeBuild200,
          '/v1/builds/': buildDetail200,
          'appStoreVersionSubmission': [404, '{"errors":[]}'],
        });

        expect(result.exitCode, 0, reason: result.stderr as String);
        expect(result.stdout, contains('submitted for review: no'));
      },
      skip: skipWithoutRuby,
    );

    test(
      'the healthy report still pins its build and submission lines',
      () {
        // The good output the skill's step 1 leans on: a processed build
        // attached to the editable version and a live submission on it.
        final result = runVersion({
          'appStoreVersions?': versions200,
          'include=build': includeBuild200,
          '/v1/builds/': buildDetail200,
          'appStoreVersionSubmission': [200, '{"data":[{"id":"S1"}]}'],
        });

        expect(result.exitCode, 0, reason: result.stderr as String);
        expect(result.stdout, contains('attached build: 1074 (VALID)'));
        expect(result.stdout, contains('submitted for review: YES'));
      },
      skip: skipWithoutRuby,
    );
  });
}
