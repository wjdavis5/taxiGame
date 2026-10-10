# Worktree snapshot, hygiene pass 2026-10-10T01:14:02 -04:00

Before (transcribed from the run transcript of the cleanup pass), 12 worktrees:

    C:/git/repos/taxiGame                 087918d [main]
    C:/git/repos/taxiGame-cycle3          ca517c3 [review/cycle3-20261009]
    C:/git/repos/taxiGame-fix-invariants  83812e8 [fix/cycle3-invariants-20261009]
    C:/git/repos/taxiGame-fix-perf        6326ae2 [fix/cycle3-perf-20261009]
    C:/git/repos/taxiGame-fix-ux          f33c023 [fix/cycle3-ux-20261009]
    C:/git/repos/taxiGame-fix228          724cc76 [fix/228-idempotent-init-20261009]
    C:/git/repos/taxiGame-fix49           e4dd4f8 [fix/49-engine-audio-storm]
    C:/git/repos/taxiGame-pm              daab300 [product/future-map-20261010]
    C:/git/repos/taxiGame-pm-docs         12876b3 [docs/run-trail-20261010]
    C:/git/repos/taxiGame-review-sweep    4284ff7 [fix/review-sweep-20261008]
    C:/git/repos/taxiGame-review2-runtime 4d5ae6f [fix/review2-runtime-20261009]
    C:/git/repos/taxiGame-review2-tests   4404bd4 [fix/review2-tests-20261009]

Removed (9): review-sweep, review2-tests, review2-runtime, fix228, fix-ux, fix-invariants, fix49, pm, fix-perf. All were clean; none had unmerged work.

After (`git worktree list` at capture time), 3 remain:

    C:/git/repos/taxiGame         087918d [main]
    C:/git/repos/taxiGame-cycle3  ca517c3 [review/cycle3-20261009]
    C:/git/repos/taxiGame-pm-docs 12876b3 [docs/run-trail-20261010]

The main checkout holds the user-side sweep state (local main 087918d, modified CLAUDE.md, untracked AGENTS.md and .opencode) and was deliberately left untouched.
