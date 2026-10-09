/// Shared extraction helpers for the release workflow's shell guards.
///
/// The submit gate in `.github/workflows/ios-release.yml` carries sibling
/// guards — What's New (issue #199) and the review notes (issue #211,
/// the 4.3(a) guard) — whose refusal branches share the same
/// `echo "::error::"` + `exit 1` shape. A test that greps the whole step
/// for those tokens is satisfied by either guard (issue #224), so the
/// guards are extracted block by block and each refusal is pinned inside
/// its own branch instead.
library;

import 'package:flutter_test/flutter_test.dart';

/// The whole step block, from its `- name:` line to the next step's, so
/// assertions cannot accidentally match text from some other step.
String workflowStepBlock(String workflow, String stepName) {
  final start = workflow.indexOf('- name: $stepName');
  expect(start, greaterThan(-1), reason: 'step "$stepName" is missing');
  final next = workflow.indexOf('\n      - name: ', start + 1);
  return workflow.substring(start, next == -1 ? workflow.length : next);
}

final _ifToken = RegExp(r'\bif\b');
final _fiToken = RegExp(r'\bfi\b');

/// The smallest balanced `if … fi` shell block in [text] that contains
/// [token].
///
/// Each guard nests its missing-file and empty-file checks inside one
/// `if [ "$submit" = "true" ]` block, so the smallest block containing a
/// branch's own token is the refusal branch itself — where `exit 1` must
/// be pinned (issue #224). Shell here only nests `if` inside `if`;
/// `elif`, `else`, `case`, `for`, and `while` do not change the balance.
/// An `if` token that never closes — prose in a comment, like the step's
/// `` `if: always()` `` — is skipped; the `expect` below still fails
/// loudly if no balanced block carries the token.
String shellIfBlock(String text, String token) {
  String? smallest;
  for (final match in _ifToken.allMatches(text)) {
    final block = _balancedIfBlock(text, match.start);
    if (block == null || !block.contains(token)) continue;
    if (smallest == null || block.length < smallest.length) {
      smallest = block;
    }
  }
  expect(smallest, isNotNull,
      reason: 'no balanced if-block containing "$token" was found in:\n'
          '$text');
  return smallest!;
}

/// [text] from the `if` at [start] through its matching `fi`, or null
/// when the block never closes.
String? _balancedIfBlock(String text, int start) {
  var depth = 0;
  var at = start;
  while (at < text.length) {
    final open = _ifToken.matchAsPrefix(text, at);
    if (open != null) {
      depth++;
      at = open.end;
      continue;
    }
    final close = _fiToken.matchAsPrefix(text, at);
    if (close != null) {
      depth--;
      at = close.end;
      if (depth == 0) return text.substring(start, at);
      continue;
    }
    at++;
  }
  return null;
}
