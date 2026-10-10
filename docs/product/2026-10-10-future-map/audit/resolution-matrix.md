# Resolution matrix: every adversarial finding, disposed

Source report: `review-adversarial.md` (adversarial pass, 2026-10-10). This matrix records the disposition of every finding ID so no "resolved" claim rests on prose alone. Issue links point at the final bodies.

| ID | Finding | Disposition | Evidence |
|---|---|---|---|
| M-1 | #262 presumed an art capability the repo lacks | Fixed | #262 body now names art production, new pipeline, an art owner, and `needs-human`; size L |
| M-2 | #266/#268 cite non-resolving paths | Fixed | #266/#268 bodies now cite `lib/game/components/player_vehicle.dart` and `lib/game/components/virtual_stick.dart` |
| M-3 | #263 acceptance item already satisfied | Fixed | #263 body dropped the capture-command bullet |
| M-4 | #277 invented a fourth pacing figure | Fixed | #277 body restates the catalog wallet figures as one stale base among three |
| M-5 | No false quotes found | No action | Recorded as clean |
| M-6 | Worktree label drift in the review brief | Accepted with note | Reviews ran at c514609; the map was validated against c514609 plus PR #260's three-file delta; no review claim is invalidated |
| C-1 | Store What's New identity text unowned | Fixed | #264 acceptance: What's New names the two modes in the same voice |
| C-2 | Tutorial completion earns nothing | Fixed | #283 acceptance: rung ten earns a visible reward and a record |
| C-3 | Garage bars unexplained | Fixed | #282 acceptance: the garage explains what the bars change |
| C-4 | Launch latency and canvas accessibility unrecorded | Accepted | Tracker "Deliberately out of scope for now": latency parked until the #286 profile; accessibility needs its own design pass |
| C-5 | Bank-panel crowding and short-phone scroll unowned | Fixed | #270 acceptance: bank prompt and settlement panel fit the smallest supported iPhone |
| B-1 / X-1 | Map shipped traffic sprites it called the strongest clone signal | Fixed | Map amended at docs commit 5a309a0: hero cab is the submitted-build stage (P0, #262), fleet migration follows (#275, P1) |
| B-2 / X-2 | Tracker reported the provenance fix done while its PR was open | Fixed, then merged | Tracker marked it pending; PR #260 has since merged as 8f69c94; tracker now says merged and clears the #212 reply |
| B-3 | #271/#272 sat in the submission milestone | Fixed | Both moved to the Next milestone and marked P1 in their bodies |
| B-4 | #274 claimed it would supply the #40 artifact | Fixed | Acceptance conditioned: only if the crash reproduces during a pass |
| B-5 | #274 carried [FS] | Fixed | Flags are now [RS] [OPERATOR] |
| B-6 | In-milestone sequencing unstated | Fixed | Tracker annotates #279 before #278 and #287 before #280 |
| S-1 | #285 dispatcher had no production owner | Fixed | #285 acceptance adds a named owner and recording plan; `needs-human` applied |
| S-2 | #276/#277 order unstated in the tracker | Fixed | Tracker marks #277 blocked by #276 |
| X-3 | #262 missing `needs-human` | Fixed | Label applied |
| X-4 | #278 said six cars against a seven-car fleet | Fixed | Body says six purchasable cars |
| X-5 | Two different counts of 28 | Fixed | Tracker "Two counts of 28" note explains the substitution and the split |
| X-6 | #284 read as removing the coin pops | Fixed | Body states the pops stay; the count and credit moment are the fix |

## Trail-review findings (trail-review.md), disposed

| Finding | Disposition | Evidence |
|---|---|---|
| Committed copy stale (22 vs 24+ rows) | Fixed | The final canonical TSV is pushed to PR #292; the publish row states the row range |
| Synthesis completion unrecorded | Fixed | Trail rows: synthesis complete with paths and the W1 result; routing row for figure-it-out |
| Adversarial "every finding resolved" overstated | Fixed | This matrix, plus the six late issue edits, plus the correction rows |
| No 24-hour execution in timestamps | Clarified | Trail row: 24-hour timebox with the mapping predicate met in the first hour |
| "Removed a frame-budget cliff" unmeasured | Corrected | Trail row withdraws the measurement claim; #286 owns the device profile |
| Malformed/weak evidence pointers | Corrected | Correction rows for milestones/URLs, issue-state snapshot, worktree snapshot, comment URLs, proof files |
| verify-claims mislabeled #269 as #270 | Fixed | Correction appended in `verify-claims.md` before it was committed |
| Start row incomplete | Clarified | Trail row: prior range none, session identity, UTC-04:00 |
| Failed first milestone attempt lacks durable proof | Accepted with note | The failure left zero creates, proven by the 28 issues' `created_at` window 2026-10-10T04:37:41Z to 04:38:19Z; the failed attempt itself exists only in the run transcript |
| Probe results only in the verdict file | Fixed | Raw test outputs committed: `proof-parent.txt` (new test fails on the fix's parent) and `proof-head.txt` (passes on merged main) |

## Repo state at handback

- Main: `b73c2dc` (PR #291). Merged today: #260 (`8f69c94`), #261 (`4cb48c6`), #291 (`b73c2dc`).
- Closed: #250 through #257. Open: #40, #94, #212, #262 through #290.
- The roadmap's operator-gated items: #262 (art owner), #268/#272/#274 (device), #286 (profile), #212 (App Store Connect).
