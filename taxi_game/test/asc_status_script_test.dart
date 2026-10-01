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
/// The contract is pinned the same two ways release_submit_gate_test.dart
/// pins the submit gate: text assertions over the script source, which run
/// anywhere, and behavioral tests that execute the real `private_key_path`
/// against a fake HOME laid out by the test. Those need `ruby`, which CI
/// has and a dev box may not; they skip with a reason rather than silently
/// passing.
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
}
