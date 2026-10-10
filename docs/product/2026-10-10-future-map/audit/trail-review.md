# Cross-model review of the Cab Hustle decision trail

Reviewed the canonical temp trail, the copy on PR #292, Git history, GitHub PRs, issues, milestones, comments, and release runs. At the review point, the temp trail had 24 decision rows through `2026-10-10T01:14:02`, while PR #292 had 22 decision rows through `2026-10-10T01:13:07`.

Verdict: the core GitHub outcomes are real, but the trail is not ready for handback. The committed audit copy is stale, the adversarial-resolution row overstates what was fixed, and the synthesis checkpoint is missing.

Review limit: no run transcript was supplied or found under the workspace or `taxi-pm`. The completeness check can identify gaps exposed by the artifacts and required checkpoints, but it cannot certify that no other decisions are missing.

## 1. Evidence resolution

I checked all 24 current rows. This sample spans more than ten rows and every phase with an external outcome.

| Row | Evidence check |
|---|---|
| `2026-10-10T00:20:33`, `start` | The temp TSV exists and this is its first data row, so "no earlier rows" holds. |
| `2026-10-10T00:21:14`, `frame` | `frame.md` exists and contains the predicate, scope, rigor, phases, defaults, and stated 24-hour window. |
| `2026-10-10T00:21:14`, `review` | The wildcard resolves to six review reports, one for each W1 through W6 slice. |
| `2026-10-10T00:25:28`, `review` | `review/uniqueness-and-submission.md`, `review/first-session-and-feel.md`, and `review/competitors.md` exist and contain the summarized findings. |
| `2026-10-10T00:26:25`, `fix` | Commit `daab300` exists. PR #260 exists and merged as `8f69c94`. Its PR check passed. |
| `2026-10-10T00:26:37`, `review` | The W3 and W6 files exist and contain the summarized progression and risk findings. |
| `2026-10-10T00:44:58`, `fix` | `8f69c94` and docs head `5a309a0` both resolve. PR #261 later merged as `4cb48c6`. |
| `2026-10-10T00:51:38`, `side-unit` | PR #291 exists. Its original head was `54e23b3`, its base was `8f69c94`, and it held eight frame-hygiene commits before the verdict fix. GitHub run `38025503369` shows Analyze and Test succeeded at that head and reports 1,087 tests passed. |
| `2026-10-10T00:52:39`, `release` | Run `38025122783` completed successfully at `8f69c94`; its log shows `UNRESOLVED_ISSUES`, a skipped submit step, and `UPLOAD SUCCEEDED`. |
| `2026-10-10T00:59:15`, `verdict` | Commit `6326ae2` exists and changes the darkness guard from epsilon comparison to exact equality with a cached-versus-fresh regression test. |
| `2026-10-10T01:09:58`, `release` | Run `38025848925` completed successfully at `4cb48c6`; its log shows the same stuck-review decision and successful TestFlight upload. |
| `2026-10-10T01:13:07`, `merge` | PR #291 merged as `b73c2dc`. Issues #250 through #257 are closed. |
| `2026-10-10T01:13:20`, `close` | PR #292 exists and is open at `12876b3`. Its contents do not match the current temp trail. See the blocker below. |

### Findings

- **blocker | `2026-10-10T01:13:20`, `close` | The evidence resolves to an incomplete trail.** PR #292 contains the header plus 22 decisions and ends at the `adjacent` row. The canonical temp trail has 24 decisions and also contains `close` and `hygiene`. The row saying the trail was committed is itself absent from the committed copy. **Fix:** append a superseding row that states the exact row range being published, then update PR #292 with the complete canonical TSV.

- **major | `2026-10-10T00:27:27`, `synthesis` | Neither evidence pointer resolves to the claimed work.** `ses_edbef472c` is not accompanied by a transcript or session artifact, and "synthesis brief on sol" is not a path. The row also omits the existing W1 and synthesis files. **Fix:** append a row pointing to `review/product-audit.md`, `synthesis/product-thesis.md`, and `synthesis/workstream-map.md`; preserve a transcript or error artifact for the failed Opus attempt and Sol substitution.

- **major | `2026-10-10T00:38:42`, `map` | The main roadmap pointers are malformed or incomplete.** "issue URL above" points nowhere. `issue-urls.txt` does not exist at the trail root; the file is `roadmap/issue-urls.txt`. The evidence names no tracker URL or label URL. Milestones #5 through #7 do resolve and contain 13, 13, and 2 open roadmap issues. **Fix:** append exact paths and URLs for `roadmap/issue-urls.txt`, #290, the `roadmap` label, and milestones #5 through #7.

- **minor | `2026-10-10T00:26:25`, `fix` | Two file pointers do not resolve as written.** There is no repository-root `LICENSES.txt` or `credits.dart`. The files are `taxi_game/assets/licenses/LICENSES.txt` and `taxi_game/lib/data/credits.dart`. The commit and PR still prove the fix. **Fix:** append a correction with full repo-relative paths and line ranges.

- **minor | `2026-10-10T00:38:42`, `map` | The failed numeric-milestone attempt has no durable evidence.** "shell output" and `CREATED=28` are prose, not saved output. **Fix:** point to a captured command log or transcript excerpt showing zero creates on the failed attempt and 28 creates on the retry.

- **major | `2026-10-10T00:44:58`, `map` | The evidence points to findings, not to proof that every finding was resolved.** `review-adversarial.md` records the pre-fix findings. It names 16 minor finding IDs, not six, and several remain unaddressed. Generic text saying "issue edits 262-290" is not a resolution record. **Fix:** append a finding-by-finding resolution matrix with exact issue or commit links and mark any accepted omissions explicitly.

- **minor | `2026-10-10T00:49:38`, `verify` | The evidence names the wrong issue for the near-miss claim.** `verify-claims.md` calls its second claim issue #270, while the trail and the actual posted comment correctly use #269. **Fix:** append a corrected pointer and cite the three comment URLs on #266, #269, and #271.

- **minor | `2026-10-10T01:13:07`, `adjacent` | `gh issue list` is not a durable or complete pointer.** It has no repository, filters, output, or timestamp, and the row admits that #40 and #94 were omitted by the limit. **Fix:** cite direct issue URLs or saved JSON for #40, #94, #212, #262 through #290, and #250 through #257.

- **minor | `2026-10-10T01:14:02`, `hygiene` | The pointer proves only the after-state.** Current `git worktree list` shows three worktrees, but it cannot prove that nine named worktrees existed and were removed. **Fix:** save before-and-after `git worktree list --porcelain` output or cite the transcript containing both.

## 2. Completeness

The six-worker fan-out, synthesis model substitution, issue and milestone creation, adversarial pass, verdict FAIL and fix, and local trail-commit row are present. The following run-shaping decisions are missing or incomplete.

- **major | `2026-10-10T00:27:27`, `synthesis` | There is no synthesis-complete checkpoint.** The row ends with `running`; the next row jumps to 28 filed issues. Nothing records that the product thesis and workstream map completed, which choices won, or that they became the issue source. **Fix:** append a synthesis result row with the two synthesis paths, the selected identity, the 28-candidate count, and any rejected alternatives.

- **major | `2026-10-10T00:27:27`, `synthesis` | W1 is the only worker without a result row or evidence path.** The row says W1 reported but records none of its findings and does not cite `review/product-audit.md`. **Fix:** append a W1 result row or include its path and decisive findings in the synthesis-complete row.

- **minor | `2026-10-10T00:21:14`, `frame` | Routing to `figure-it-out` is only implicit.** The `why` cell names Phase A, but no decision says that the run chose that playbook and its phase gates. **Fix:** append a routing clarification tied to `frame.md` or the run transcript.

- **minor | `2026-10-10T00:44:58`, `fix` and `2026-10-10T01:09:58`, `release` | PR #261 has no explicit opened or merged checkpoint.** Its head update and release run imply the lifecycle, but the trail never states that #261 merged as `4cb48c6`. **Fix:** append a direct merge row with the PR URL and merge SHA.

- **minor | `2026-10-10T01:13:07`, `adjacent` | The promised checks of #40 and #94 never receive a row.** Both are in fact open, but "checked next" is followed by `close` and `hygiene`, not a check result. **Fix:** append their direct states and evidence.

- **blocker | `2026-10-10T01:13:20`, `close` and `2026-10-10T01:14:02`, `hygiene` | The audit copy omits the last two decisions.** This also means the last committed row says more checks are coming, while the canonical trail says the run closed and then performed cleanup. **Fix:** publish the canonical file after adding the superseding rows from this review.

- **major | `2026-10-10T00:20:33`, `start` through `2026-10-10T01:14:02`, `hygiene` | The trail does not show a 24-hour run.** It shows a 24-hour deadline window but only 53 minutes and 29 seconds of decisions before cleanup. **Fix:** describe it as a 24-hour timebox completed early, or continue the run to the stated deadline and log the later work. Do not call the observed execution itself 24 hours.

## 3. Contradictions

### Expected state check

The expected repository and GitHub state holds:

- PR #260 is merged as `8f69c94`.
- PR #261 is merged as `4cb48c6`.
- PR #291 is merged as `b73c2dc`, which is GitHub's current main head.
- PR #292 is open at `12876b3`.
- Issues #262 through #289 and tracker #290 are open.
- Issues #40, #94, and #212 are open.
- Issues #250 through #257 are closed.

No trail row falsely claims one of those merges or closures.

### Findings

- **major | `2026-10-10T00:44:58`, `map` | "Every finding resolved" contradicts the current roadmap.** At minimum, #274 still carries `[FS]` despite B-5 saying to remove it; #264 does not own the What's New text from C-1; #278/#283 do not own the tutorial-completion reward from C-2; #282 does not explain garage bars from C-3; launch latency from C-4 is neither owned nor explicitly accepted; and bank-panel crowding and short-phone scrolling from C-5 are neither owned nor accepted. The evidence file also lists 16 minor IDs, while the row says six. **Fix:** resolve or explicitly accept each finding, then append a superseding row with exact links and corrected counts.

- **major | `2026-10-10T01:13:07`, `merge` | "Removes a frame-budget cliff" contradicts the evidence base.** The capability review, product thesis, and PR #291 body all say no profiling was possible and device profiling waits for #286. The merge proves structural allocation cleanup and behavior checks, not a frame-time gain or removal of a cliff. **Fix:** narrow the row to the measured facts, or attach a reproducible device profile with before/after frame-time, allocation, errors, run count, and workload.

- **major | `2026-10-10T00:20:33`, `start` and `2026-10-10T01:13:20`, `close` | A literal 24-hour duration conflicts with the timestamps.** The close comes 52 minutes and 47 seconds after start. **Fix:** call it a 24-hour allowance or timebox that finished early unless later work extends the trail.

- **minor | `2026-10-10T00:44:58`, `map` followed by `2026-10-10T00:44:58`, `fix` | Tracker #290 is stale after the merge.** It still says the provenance fix is "pending merge" and warns not to send until #260 merges, although the next trail row and GitHub show it merged. **Fix:** update the tracker and append a row recording the correction.

- **blocker | `2026-10-10T01:13:20`, `close` | "Trail committed" is true only for an earlier prefix.** The local and committed artifacts disagree about the end of the run. **Fix:** make PR #292 contain the reviewed canonical bytes.

## 4. Weak rows

- **major | `2026-10-10T00:38:42`, `map` | The retry result is a self-report.** No saved output proves the first attempt created nothing or the second created 28. **Independent evidence needed:** captured command output plus issue creation timestamps or an API response list.

- **major | `2026-10-10T00:44:58`, `map` | Resolution is asserted against the review that found the defects.** The cited report cannot prove subsequent edits. **Independent evidence needed:** a resolution matrix linked to issue histories, final bodies, labels, milestones, and docs commit `5a309a0`.

- **minor | `2026-10-10T00:49:38`, `verify` | The local markdown is the only trail evidence for measurement completion.** It includes code arithmetic and pasted output, but it is still authored summary text. **Independent evidence needed:** raw command output, exact commit/file lines, and the three GitHub comment URLs. The comments do independently prove that posting happened.

- **major | `2026-10-10T00:59:15`, `verdict` and `2026-10-10T01:01:52`, `verdict` | The 81,607-byte failure, zero-byte second result, and fail-on-parent proof exist only in `verdict-perf.md`.** Commit `6326ae2` and green CI prove the fix and current test pass, but not those reported probe results or that the new test failed on `54e23b3`. **Independent evidence needed:** saved raw probe output and a CI or archived command log for both commits.

- **major | `2026-10-10T01:13:07`, `merge` | The performance conclusion has no measurement.** A green behavior suite is not a frame benchmark. **Independent evidence needed:** the #286 device profile or removal of the performance claim.

- **minor | `2026-10-10T01:13:07`, `adjacent` | Completion rests on an unspecified command.** The direct GitHub reads performed in this review confirm the states, but the row does not preserve them. **Independent evidence needed:** exact `gh issue view` JSON or direct URLs with states.

- **minor | `2026-10-10T01:14:02`, `hygiene` | The removal count is a self-report.** Three remaining worktrees do not prove nine removals. **Independent evidence needed:** a before-state plus the current after-state.

The review-report rows with result `reported` are not treated as completion rows. They resolve to actual reports, but their product judgments remain desk review unless backed by the source pointers inside each report.

## 5. The start row

- **minor | `2026-10-10T00:20:33`, `start` | Partial hold.** The decision clearly names the run it opens, and "no earlier rows in this log" correctly describes the empty prior range. It does not name this run's session or agent ID in evidence, as the trail format requires, and its local timestamps omit an offset. **Fix:** append a start-row clarification with `prior ts range: none`, the run/session ID, and the timezone offset used by the trail.

## What the trail can sustain

It can sustain that the six reviews exist, 28 roadmap issues plus tracker #290 were created across three milestones, the provenance correction merged, the docs evidence base merged, three claims received measurement comments, the PR #291 verdict artifact recorded a behavior failure that was fixed before merge, the two release runs uploaded to TestFlight and skipped App Review under `UNRESOLVED_ISSUES`, and the expected PR and issue states now hold.

It cannot sustain a literal 24 hours of execution, that every adversarial finding was resolved, that the frame-hygiene merge removed a measured frame-budget cliff, or that PR #292 contains the complete canonical trail.
