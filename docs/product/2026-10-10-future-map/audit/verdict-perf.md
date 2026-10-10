# FAIL

Reviewed PR #291 at `54e23b3f0a77d9af3fb5a9bf39388d3e93c16f33` against merge base `8f69c945170c553ec6de1984cb0e44a3c554b45c` (`origin/main`). The frame-caching series is not behavior-identical.

## Findings

1. **major: Background paint caching returns output for the wrong darkness**
   - **Code:** `taxi_game/lib/game/components/background.dart:122`
   - `_syncPaints()` returns whenever the new `darkness` is within `1e-3` of the value used to build the paints. The pre-PR renderer recomputed the sky, star, building, and window colors from the current value every render, so the new output depends on the preceding frame.
   - **Proof:** after rendering one instance at `0.37` and then `0.3705`, a fresh instance rendered at `0.3705` differed from the reused instance in **81,607 RGBA byte positions**.
   - **Weak test:** `taxi_game/test/background_cache_test.dart:48` requires the two history-dependent renders to be equal. It never compares the epsilon-hit result with a fresh component at the same final darkness, despite the file's stated pixel-identity contract.
   - **Smallest fix:** invalidate on every value change (`if (darkness == _shadedDarkness) return;`) and replace the epsilon test with a cached-versus-fresh comparison at the same final darkness.

## Coverage and notes

- No additional behavior, draw-order, determinism, or RNG-consumption change was found in the other caches.
- Road pictures, pending fares, traffic/contact snapshots, overlay paints, glyph/marker/cone paints, camera Y, vehicle size, shake state, and weather samples have matching dependency keys or lifecycle invalidation in the reviewed source.
- The pending-fare test checks reuse but not index/fold invalidation; source inspection confirms both keys at `taxi_game/lib/game/systems/endless_fare_controller.dart:98-109`.
- The #258 reset/daily-rollover and #259 navigation/re-entry changes do not leave any reviewed cache alive across the affected lifecycle boundaries.

## Validation

- `flutter test --no-pub test/background_cache_test.dart` passed, demonstrating that the committed test does not catch the divergence.
- A temp-only fresh-baseline probe passed and reported `DIFFERING_RGBA_BYTES=81607`; the full suite was not run.
- `git diff --check origin/main...HEAD` passed, and the reviewed worktree remained clean.

## Round 2

**Verdict: PASS**

Re-verified commit `6326ae222942b8d11f29f6c3706afaa9a3e981b2`, whose parent is the previously reviewed `54e23b3f0a77d9af3fb5a9bf39388d3e93c16f33`.

- The exact-equality guard fixes the finding. A temp-only fresh-baseline probe rendered one instance at `0.37` then `0.3705` and a fresh instance at `0.3705`; it reported `SMALL_STEP_DIFFERING_RGBA_BYTES=0`.
- The result is history-independent for documented finite darkness values: every changed value rebuilds all darkness-dependent paints before drawing, while an equal value reuses paints already built for that same value. The geometry is fixed and the star draw threshold reads the current value directly.
- The replacement regression test is pinned correctly. It passed at `6326ae2`. In an isolated temporary copy of parent `54e23b3` containing the new test but the old epsilon guard, the named test failed with the first mismatch at RGBA byte 0 (`90` versus `91`) and exited 1.
- A temp probe verified the NaN sentinel builds the first frame by checking the known midday sky bytes, a repeated render at darkness `0` remains byte-identical to both its first render and a fresh render, and the sequence `0 -> 1 -> 0.37` ends byte-identical to a fresh `0.37` render.
- `flutter test --no-pub test/background_cache_test.dart` passed all 3 tests. `git diff --check 54e23b3..6326ae2` passed. The isolated parent copy was removed, and the review worktree remained clean.
- I did not repeat the already-reported full 1,087-test suite or `flutter analyze` during this targeted round.
