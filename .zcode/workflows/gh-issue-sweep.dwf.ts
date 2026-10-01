/* zcode-workflow
description: "One tick of the recurring pipeline: find open GitHub issues, plan
  and implement every fix on a single branch, make analyze + the full test suite
  pass, open one PR, wait for CI (including the iOS simulator run), perform a
  full senior code review with a fix loop where every fix is pushed, verified
  on the PR and re-CI'd, plus an independent final approval, then merge exactly
  the head CI passed, watch the iOS Release pipeline deploy to TestFlight, and
  close the issues."
whenToUse: "Run on a schedule (every 30 minutes) or on demand whenever you want all open GitHub issues in wjdavis5/taxiGame triaged, implemented in one PR, code-reviewed at a senior level, merged, and deployed to TestFlight automatically."
args: {}
*/
/* gh-issue-sweep — one tick of the recurring pipeline.
   Open GitHub issues → plan → implement on one branch → analyze + full tests →
   PR → CI (incl. iOS simulator) → senior review + fix loop (each fix pushed,
   head-verified and re-CI'd — issue #88) + independent approval → merge the
   CI-green head (--match-head-commit) → TestFlight deploy → close issues.
   Runs from the repo root; the Flutter project is the taxi_game/ subdirectory.
   Flutter must run through cmd /c "cd taxi_game && flutter …" on this host. */

interface GhIssue {
  number: number;
  title: string;
}

interface IssuePlan {
  /** Issue number. */
  number: number;
  /** Issue title. */
  title: string;
  /** "implement" — plan a change; "close-as-done" — already shipped, close with evidence. */
  resolution: "implement" | "close-as-done";
  /** 2-4 sentences: the chosen approach, or what already satisfies the issue. */
  approach: string;
  /** Workspace-relative files the fix touches, or the files that are the evidence. */
  files: string[];
}

interface DoneCheck {
  /** True only when the evidence was personally re-read in the code. */
  confirmed: boolean;
  /** What was actually seen: files and symbols. */
  evidence: string;
}

interface Finding {
  /** Workspace-relative path, with a line when it applies. */
  where: string;
  /** One sentence: what is wrong. */
  what: string;
  /** Reserve "high" for data loss, a crash, or a wrong result. */
  severity: "low" | "medium" | "high";
}

interface ReviewVerdict {
  approved: boolean;
  /** Blocking problems — empty when approved. */
  blocking: Finding[];
  /** One-paragraph overall judgement. */
  summary: string;
}

interface WorkflowReport {
  /** Two or three sentences answering what the user asked for. */
  conclusion: string;
  findings: Finding[];
  /** What the run checked and how. */
  verified: string[];
  /** What the run did not look at or could not check, and why. */
  notCovered: string[];
}

artifact.board("issues", {
  key: "issue",
  status: "status",
  columns: ["planned", "implemented", "merged", "closed", "failed"],
  cardTitle: "title",
  detail: [{ field: "note", label: "Note" }],
});

const tail = (s: string) => (s.length > 4000 ? "...\n" + s.slice(-4000) : s);
// The log-path suffix from `%TEMP%` / `$env:TEMP` down to the file, built
// once so the write and the read below can never name different files.
// The backslash is doubled at the source level: in a JS/TS string literal
// a lone `\s` is not an escape and collapses to a plain `s`, which wrote
// the log to `…\Tempsweep_flutter.log` while the read-back evaluated the
// unset `$env:TEMPsweep_flutter` — every failed gate round reached the
// coder with an empty log (issue #97).
const flutterLog = "\\sweep_flutter.log";
const flutter = async (what: string, timeoutMs: number) => {
  // The full suite's output can exceed world.run's stdout cap, which
  // errored a whole sweep mid-gates: capture to a temp file instead and
  // hand back only a tail, and only when the command failed.
  const run = await world.run(
    "cmd",
    ["/c", "cd taxi_game && flutter " + what + " > %TEMP%" + flutterLog + " 2>&1"],
    { timeoutMs },
  );
  if (run.exitCode === 0) return { exitCode: 0, output: "" };
  const log = await world.run(
    "cmd",
    ["/c", "powershell -NoProfile -Command Get-Content -Tail 200 $env:TEMP" + flutterLog],
  );
  return { exitCode: run.exitCode, output: log.stdout };
};
// The sweep runs on this Windows host, where world.run has no shell
// built-in sleep — PowerShell's Start-Sleep is the reliable wait. Shared
// by the CI-registration and release-run polls so they pace their probes
// (30 × 5 s ≈ 2.5 min each) instead of firing 30 back-to-back round
// trips that finish long before GitHub has booked anything (issue #61).
const sleepSeconds = (s: number) =>
  world.run(
    "powershell",
    ["-NoProfile", "-Command", "Start-Sleep -Seconds " + s],
    { timeoutMs: (s + 30) * 1000 },
  );

// ---- landing changes and re-CI (issue #88) ------------------------------
// world.run reports failures as exit codes instead of throwing, so a bare
// git push through it swallows a rejected push (network, auth,
// non-fast-forward) as if it had succeeded. Both push sites used to
// do exactly that: the review loop would then re-read a stale PR diff and
// block forever on a fix that was never uploaded (the PR #84 failure), or
// — if the reviewer judged the files on disk — the merge shipped the
// remote head, which never had the fix. Every push now goes through
// commitAndPush, and every newly pushed head is confirmed on the PR and
// re-CI'd by awaitCi before anything merges against it.

interface Landed {
  ok: boolean;
  /** False when there was nothing to commit — no new head, no CI to await. */
  pushed: boolean;
  /** Full local HEAD after the commit; meaningful only when ok. */
  head: string;
  /** Why the changes never landed; empty when ok. */
  error: string;
}

const commitAndPush = async (message: string): Promise<Landed> => {
  // The branch wall (issue #108): world.run reports git failures as exit
  // codes, not throws, and the one call that still ignored its result was
  // `checkout -b` — a leftover branch from a failed prior sweep (same
  // main, same sha) made it die with "already exists" while the sweep
  // carried on committing straight onto local main and opening a PR
  // whose diff was the previous attempt's. The checkout is now exit-code
  // checked where it happens (phase 3); this guard is the backstop for
  // any future failure that slips past a check — nothing may ever commit
  // while HEAD sits anywhere but the sweep branch. `--show-current`
  // prints the branch name, or nothing on a detached HEAD; either way it
  // must equal `branch` or the commit refuses to run at all.
  const on = await world.run("git", ["branch", "--show-current"]);
  if (on.exitCode !== 0 || on.stdout.trim() !== branch) {
    const where = on.exitCode !== 0
      ? "an unreadable branch (git branch --show-current exited " + on.exitCode + ")"
      : on.stdout.trim() === ""
        ? "a detached HEAD"
        : "'" + on.stdout.trim() + "'";
    return {
      ok: false,
      pushed: false,
      head: "",
      error:
        "refusing to commit: HEAD is on " + where +
        ", not the sweep branch '" + branch + "' — committing here would land " +
        "changes on a branch with no PR, no CI, and no review (issue #108)",
    };
  }
  await world.run("git", ["add", "-A"]);
  const commit = await world.run("git", ["commit", "-m", message]);
  if (commit.exitCode !== 0) {
    // "Nothing to commit" is the one tolerable commit failure — an empty
    // review round — and only when the tree really is clean. Any other
    // non-zero commit (hook, lockfile, identity) leaves changes behind
    // that must stop the sweep, not ride along unpushed.
    const status = await world.run("git", ["status", "--porcelain"]);
    if (status.exitCode !== 0 || status.stdout.trim() !== "") {
      return {
        ok: false,
        pushed: false,
        head: "",
        error:
          "git commit exited " + commit.exitCode + " with changes still " +
          "uncommitted, so the fixes never became a commit:\n" +
          tail(commit.stderr || commit.stdout),
      };
    }
  }
  const head = await world.run("git", ["rev-parse", "HEAD"]);
  if (head.exitCode !== 0) {
    return {
      ok: false,
      pushed: false,
      head: "",
      error:
        "git rev-parse HEAD exited " + head.exitCode + ": " + tail(head.stderr),
    };
  }
  // The push runs even after a nothing-to-commit: it is a no-op then, and
  // it also repairs a push that failed on an earlier round.
  const push = await world.run("git", ["push", "-u", "origin", branch]);
  if (push.exitCode !== 0) {
    return {
      ok: false,
      pushed: false,
      head: "",
      error:
        "git push exited " + push.exitCode + " — the commit exists only on " +
        "this machine and the PR will not contain it:\n" +
        tail(push.stderr || push.stdout),
    };
  }
  return {
    ok: true,
    pushed: commit.exitCode === 0,
    head: head.stdout.trim(),
    error: "",
  };
};

interface CiVerdict {
  ok: boolean;
  /** Why CI cannot be claimed green; empty when ok. */
  error: string;
}

// GitHub can take a minute to register checks after a push, and
// `gh pr checks` exits 1 printing "no checks reported" on STDERR while
// none exist — a state to wait out, not a failure. The first live sweep
// false-failed exactly there and left a good PR stranded. So a probe
// only counts as a verdict when it is one: exit 0 (all green), 8
// (pending — gh pr checks' documented extra code), or 1 naming a failed
// check. Exit 1 with "no checks" means wait; any other exit (2
// cancelled, 4 auth, …) is gh itself failing and must be reported with
// its stderr — not swallowed into the watch below, where it surfaces as
// a bogus "CI red". Probes sit 5 s apart, so registration gets ~2.5
// minutes instead of 30 instant round trips (issue #61).
const waitChecksRegistered = async (
  prNumber: number,
): Promise<{ registered: boolean; failure: string }> => {
  let checksRegistered = false;
  let probeFailure = "";
  for (
    let attempt = 0;
    attempt < 30 && !checksRegistered && probeFailure === "";
    attempt++
  ) {
    if (attempt > 0) await sleepSeconds(5);
    const probe = await world.run(
      "gh",
      ["pr", "checks", String(prNumber)],
      { timeoutMs: 60000 },
    );
    if (probe.exitCode === 0 || probe.exitCode === 8) {
      checksRegistered = true;
    } else if (
      probe.exitCode === 1 &&
      !(probe.stdout + probe.stderr).includes("no checks")
    ) {
      checksRegistered = true; // a red check — CI's verdict, judged by the watch below
    } else if (probe.exitCode !== 1) {
      probeFailure =
        "gh pr checks exited " + probe.exitCode + ": " +
        tail(probe.stderr || probe.stdout);
    }
  }
  return { registered: checksRegistered, failure: probeFailure };
};

// Wait until gh books expectedHead as the PR's head, then wait for checks
// to register and watch them to green — for that exact head. Returns ok
// only when the watch went green on expectedHead, so callers can pin the
// merge (gh pr merge --match-head-commit) to a head CI actually passed
// (issue #88: the old flow CI'd the PR once, then merged whatever head
// later review-round pushes produced).
const awaitCi = async (
  prNumber: number,
  expectedHead: string,
): Promise<CiVerdict> => {
  // Booking check: a push that exited 0 without landing, or a commit
  // someone else added to the branch, reads as a mismatch here instead
  // of letting the watch below judge — and the merge later ship — the
  // wrong head.
  let booked = false;
  let bookingError = "";
  for (let attempt = 0; attempt < 30 && !booked && bookingError === ""; attempt++) {
    if (attempt > 0) await sleepSeconds(5);
    const view = await world.run(
      "gh",
      ["pr", "view", String(prNumber), "--json", "headRefOid"],
      { timeoutMs: 60000 },
    );
    if (view.exitCode !== 0) {
      bookingError =
        "gh pr view exited " + view.exitCode + ": " + tail(view.stderr || view.stdout);
    } else if (
      (JSON.parse(view.stdout) as { headRefOid: string }).headRefOid === expectedHead
    ) {
      booked = true;
    }
  }
  if (!booked) {
    return {
      ok: false,
      error: bookingError !== ""
        ? bookingError
        : "the PR's remote head never became " + expectedHead.slice(0, 10) +
          " after the push — the commit did not land on the PR",
    };
  }
  const probe = await waitChecksRegistered(prNumber);
  if (probe.failure !== "" || !probe.registered) {
    return {
      ok: false,
      error: probe.failure !== ""
        ? probe.failure
        : "checks never registered on the PR after ~2.5 minutes of paced polling",
    };
  }
  const checks = await world.run(
    "gh",
    ["pr", "checks", String(prNumber), "--watch", "--interval", "30"],
    { timeoutMs: 2700000 },
  );
  if (checks.exitCode !== 0) {
    return {
      ok: false,
      error:
        "gh pr checks --watch exited " + checks.exitCode + " on head " +
        expectedHead.slice(0, 10) + ":\n" + tail(checks.stdout + checks.stderr),
    };
  }
  return { ok: true, error: "" };
};

const CODER_PERSONA =
  "You are a senior Flutter/Dart engineer implementing fixes in this repository " +
  "(a Flutter + Flame game; the project lives in taxi_game/). Read CLAUDE.md at the " +
  "repo root first and follow its conventions exactly: dense explanatory comments in " +
  "the house style, tests for every behavior change, the fully-offline guarantee is " +
  "never violated, and ios/project.pbxproj + Info.plist keep their CRLF endings. " +
  "Work only on the current branch and never commit — the orchestrator runs the gates " +
  "and commits. If a request is impossible or instructions conflict, escalate and say " +
  "so plainly rather than working around it.";

const REVIEWER_PERSONA =
  "You are a principal-level engineer performing the final code review before merge " +
  "into main of a shipped iOS game. You read the actual diff and the files it touches " +
  "and judge: correctness, regressions and edge cases, test coverage of changed " +
  "behavior, cost inside the 60fps game loop, Flame component lifecycle (leaks, " +
  "missing removal), consistency with the repo's conventions, and any threat to the " +
  "fully-offline guarantee. You do not edit any file. Approving takes evidence you " +
  "actually read; when in doubt, block with a concrete finding. If the instructions " +
  "cannot be satisfied honestly, escalate.";

// ---------------------------------------------------------------- phase 1
phase("Check for open GitHub issues");
const dirty = await world.run("git", ["status", "--porcelain"]);
if (dirty.stdout.trim() !== "") {
  return {
    conclusion:
      "Skipped this sweep: the working tree is not clean, so the sweep refused to touch it.",
    findings: [],
    verified: ["git status --porcelain (clean-tree guard)"],
    notCovered: ["issue triage — no changes were made"],
  } as WorkflowReport;
}
await world.run("git", ["checkout", "main"]);
const pull = await world.run("git", ["pull", "--ff-only"]);
if (pull.exitCode !== 0) {
  return {
    conclusion:
      "Skipped this sweep: git pull --ff-only failed, so main could not be synced safely.",
    findings: [],
    verified: ["git pull --ff-only (sync guard)"],
    notCovered: ["issue triage — no changes were made"],
  } as WorkflowReport;
}
const openPrs = await world.run(
  "gh",
  ["pr", "list", "--state", "open", "--json", "headRefName", "--limit", "30"],
);
if (openPrs.stdout.includes("automation/issue-sweep")) {
  return {
    conclusion:
      "Skipped this sweep: a previous sweep's PR is still open — it needs a human decision before automation continues.",
    findings: [],
    verified: ["gh pr list (one-sweep-at-a-time guard)"],
    notCovered: ["issue triage — a sweep PR is already awaiting review"],
  } as WorkflowReport;
}
const issuesRun = await world.run(
  "gh",
  ["issue", "list", "--state", "open", "--json", "number,title,labels", "--limit", "100"],
);
// Issues labeled "assigned" are being worked outside this pipeline (a
// tagged worktree agent, or a human) — the sweep never touches them.
const allIssues = JSON.parse(issuesRun.stdout) as (GhIssue & {
  labels: { name: string }[];
})[];
const issues = allIssues.filter(
  (i) => !i.labels.some((l) => l.name === "assigned"),
);
if (allIssues.length > issues.length) {
  log(
    "Skipping " + (allIssues.length - issues.length) +
    " issue(s) labeled 'assigned' — they are being worked outside this pipeline.",
  );
}
if (issues.length === 0) {
  return {
    conclusion: allIssues.length === 0
      ? "No open GitHub issues — nothing to do this sweep."
      : "All open issues are labeled 'assigned' (worked outside this pipeline) — nothing for this sweep.",
    findings: [],
    verified: ["gh issue list --state open (empty)"],
    notCovered: [],
  } as WorkflowReport;
}
log(
  "Found " + issues.length + " open issue(s): " +
    issues.map((i) => "#" + i.number).join(", "),
);

// ---------------------------------------------------------------- phase 2
phase("Plan each issue in parallel and verify any already-done claims");
const plans = await Promise.all(
  issues.map((issue) =>
    agent("issue-" + issue.number + " planner", {
      system:
        "You are a senior Flutter/Dart game engineer who reads an issue and the code " +
        "and returns a precise, minimal plan. You do not edit any file. Judge from the " +
        "code, not the issue's optimism; if the issue is unclear or impossible, escalate.",
    }).ask<IssuePlan>(
      "GitHub issue #" + issue.number + " \u201C" + issue.title + "\u201D.\n" +
      "1. Run: gh issue view " + issue.number + " --json title,body,comments and read it fully.\n" +
      "2. Read the relevant code (Flutter project: taxi_game/ subdirectory; conventions: CLAUDE.md at the repo root).\n" +
      "3. Return a plan. If the issue is already implemented in the codebase, return resolution \u201Cclose-as-done\u201D " +
      "naming the files and symbols that implement it — a tracking epic whose items have all shipped is close-as-done. " +
      "Otherwise return \u201Cimplement\u201D with a minimal approach and the files you expect to touch.",
    )
  ),
);
for (const p of plans) {
  report(
    { issue: p.number, title: p.title, status: "planned", note: p.resolution },
    "issues",
  );
}

const claimedDone = plans.filter((p) => p.resolution === "close-as-done");
const doneChecks = await Promise.all(
  claimedDone.map((p) =>
    agent("issue-" + p.number + " verifier", {
      system:
        "You confirm claims against code. You never edit anything. Confirmed=true " +
        "requires that you personally re-read the evidence in the source.",
    }).ask<DoneCheck>(
      "A planner claims issue #" + p.number + " is already implemented:\n" +
      JSON.stringify(p) +
      "\nConfirm or refute from the code alone: read the named files and check the " +
      "described behavior actually exists and is wired into the game.",
    )
  ),
);
const closeable: { plan: IssuePlan; evidence: string }[] = [];
const toImplement: IssuePlan[] = plans.filter((p) => p.resolution === "implement");
claimedDone.forEach((p, idx) => {
  const check = doneChecks[idx];
  if (check && check.confirmed) {
    closeable.push({ plan: p, evidence: check.evidence });
  } else {
    toImplement.push({
      ...p,
      resolution: "implement",
      approach:
        "A close-as-done claim was refuted (" +
        (check ? check.evidence : "could not verify") +
        "), so implement it properly. Original notes: " + p.approach,
    });
  }
});

const closeDoneIssues = async () => {
  for (const done of closeable) {
    await world.run("gh", [
      "issue", "close", String(done.plan.number), "--comment",
      "Closing as already implemented. Independently verified evidence: " + done.evidence,
    ]);
    report(
      { issue: done.plan.number, title: done.plan.title, status: "closed", note: "verified already-done" },
      "issues",
    );
  }
};

if (toImplement.length === 0) {
  phase("Close the issues verified as already done");
  await closeDoneIssues();
  return {
    conclusion:
      "All " + closeable.length + " open issue(s) were verified as already implemented and closed with evidence — no code change was needed, so no PR was created.",
    findings: [],
    verified: closeable.map(
      (d) => "issue #" + d.plan.number + " close-as-done claim confirmed by an independent verifier reading: " + d.evidence,
    ),
    notCovered: [],
  } as WorkflowReport;
}

// ---------------------------------------------------------------- phase 3
phase("Implement every fix on one branch");
const sha = await world.run("git", ["rev-parse", "--short", "HEAD"]);
// The name carries a beyond-the-sha uniqueness suffix (issues #108 and
// #118): the sha alone collides with a leftover branch from a failed
// prior sweep — same main, same sha — and `git checkout -b` then dies
// with "already exists". Deleting the stale branch instead would be
// worse: the leftover can also live on the remote (a closed-unmerged
// PR), where removing only the local ref turns this sweep's later push
// into a non-fast-forward rejection that wedges every subsequent sweep.
//
// The suffix must be replay-safe: Date.now() is unique but the workflow
// runtime forbids it, and a journal replay has to regenerate the same
// name from the same world. Taking the highest suffix already used on
// this sha's leftover branches, plus one, does both — deterministic
// from journaled world.run results alone, and fresh against every
// leftover. #118 fixed two things the f8a3e94 remote count got wrong:
// it never looked at local refs, so a leftover whose push failed (and
// so never reached the remote) recomputed the same name and the
// checked checkout stopped every tick until main moved; and a count is
// not a free index — a deleted -0 among live suffixes makes the count
// name a branch that exists. Both sides are now listed — `git branch
// --list` for the local leftovers, `ls-remote` for the remote ones —
// and the suffix is max(existing)+1 over the union, gaps and all. (The
// checkout guard below and commitAndPush's branch wall still backstop
// any residual collision.)
const branchPrefix = "automation/issue-sweep-" + sha.stdout.trim() + "-";
const localStale = await world.run("git", ["branch", "--list", branchPrefix + "*"]);
const remoteStale = await world.run(
  "git",
  [
    "ls-remote",
    "--heads",
    "origin",
    branchPrefix + "*",
  ],
);
// A failed lookup is not "no leftovers": unread exit codes made an
// empty ls-remote read as suffix 0, handing the sweep a name that may
// collide — surfacing as the checked checkout failing every tick, or
// worse as a rejected push after the whole implementation. Both exit
// codes are read, and a failure stops the sweep before a single edit
// with the same honest shape as the checkout failure below: the tree is
// still clean, so stopping loses nothing.
if (localStale.exitCode !== 0 || remoteStale.exitCode !== 0) {
  const failures: string[] = [];
  if (localStale.exitCode !== 0) {
    failures.push("git branch --list exited " + localStale.exitCode);
  }
  if (remoteStale.exitCode !== 0) {
    failures.push(
      "git ls-remote exited " + remoteStale.exitCode + ": " +
      tail(remoteStale.stderr || remoteStale.stdout),
    );
  }
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "the leftover-branch lookup failed" }, "issues");
  }
  return {
    conclusion:
      "The sweep stopped before implementing anything: the leftover-branch lookup failed (" +
      failures.join("; ") +
      "), so the sweep could not prove which branch names are already taken. Guessing a name anyway " +
      "risks git checkout -b colliding with a leftover branch (issue #118) — continuing would have " +
      "committed the fixes onto local main with no PR, no CI, and no review.",
    findings: [],
    verified: ["the leftover-branch lookups (exit-code checked — issue #118)"],
    notCovered: ["implementation, gates, review, merge and deploy — no branch was created"],
  } as WorkflowReport;
}
// Both outputs feed one max: branch --list prints bare names (possibly
// `* `-prefixed), ls-remote prints `<sha>\t<ref>` — the trailing-number
// regex reads either shape, and any line without a trailing number is
// ignored rather than guessed at.
let maxSuffix = -1;
for (
  const line of localStale.stdout.split("\n").concat(
    remoteStale.stdout.split("\n"),
  )
) {
  const suffix = /-(\d+)$/.exec(line.trim());
  if (suffix) maxSuffix = Math.max(maxSuffix, Number(suffix[1]));
}
const branch = branchPrefix + (maxSuffix + 1);
// The checkout's exit code is checked before a single edit happens
// (issue #108, applying issue #88's world.run lesson to the one git call
// that still ignored it): on failure the tree is still clean, so
// stopping loses nothing — and, crucially, nothing can be committed
// onto local main by mistake. commitAndPush re-verifies the branch as a
// backstop for any future slip past this check.
const checkout = await world.run("git", ["checkout", "-b", branch]);
if (checkout.exitCode !== 0) {
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "creating the sweep branch failed" }, "issues");
  }
  return {
    conclusion:
      "The sweep stopped before implementing anything: git checkout -b " + branch +
      " exited " + checkout.exitCode + ", so there was no branch to work on — " +
      "continuing would have committed the fixes onto local main with no PR, " +
      "no CI, and no review.\n" + tail(checkout.stderr || checkout.stdout),
    findings: [],
    verified: ["git checkout -b (exit-code checked — issue #108)"],
    notCovered: ["implementation, gates, review, merge and deploy — no branch was created"],
  } as WorkflowReport;
}
const coder = agent("the coder", { system: CODER_PERSONA });
for (const plan of toImplement) {
  await coder.ask(
    "Implement GitHub issue #" + plan.number + " \u201C" + plan.title +
    "\u201D on the current branch.\nPlan: " + JSON.stringify(plan) +
    "\nFollow CLAUDE.md exactly. Update or add tests for every behavior change. " +
    "You may run a single targeted test file to iterate, but leave the full suite " +
    "to the orchestrator. Do not commit.",
  );
  report(
    { issue: plan.number, title: plan.title, status: "implemented", note: "code on the sweep branch" },
    "issues",
  );
}
const changes = await world.run("git", ["status", "--porcelain"]);
if (changes.stdout.trim() === "") {
  await world.run("git", ["checkout", "main"]);
  await world.run("git", ["branch", "-D", branch]);
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "no changes produced" }, "issues");
  }
  return {
    conclusion:
      "The sweep produced no code changes for " + toImplement.map((p) => "#" + p.number).join(", ") +
      " — the branch was discarded and the issues left open.",
    findings: [],
    verified: ["git status --porcelain (no-change guard)"],
    notCovered: ["gates, review, merge and deploy — nothing to run them on"],
  } as WorkflowReport;
}

// ---------------------------------------------------------------- phase 4
phase("Make analyze and the full test suite pass");
let gatesOk = false;
let gatesNote = "";
for (let round = 1; round <= 3; round++) {
  const analyze = await flutter("analyze", 300000);
  if (analyze.exitCode !== 0) {
    gatesNote = "flutter analyze round " + round;
    await coder.ask(
      "flutter analyze failed:\n" + tail(analyze.output) + "\nFix the findings.",
    );
    continue;
  }
  const tests = await flutter("test", 900000);
  if (tests.exitCode === 0) {
    gatesOk = true;
    break;
  }
  gatesNote = "flutter test round " + round;
  await coder.ask(
    "flutter test failed:\n" + tail(tests.output) +
    "\nFix the causes. Never delete or weaken a test to make it pass — if a test is " +
    "genuinely wrong, fix it and say why in your report.",
  );
}

// ---------------------------------------------------------------- phase 5
phase("Open the PR and wait for CI, including the iOS simulator run");
const numbers = toImplement.map((p) => "#" + p.number).join(" ");
const prTitle = "fix: resolve open issues " + numbers + " (issue sweep)";
const prBody = [
  "Automated issue-sweep PR resolving " + numbers + ".",
  "",
  "## Plans implemented",
  ...toImplement.map(
    (p) => "### #" + p.number + " " + p.title + "\n" + p.approach + "\nFiles: " + p.files.join(", "),
  ),
  ...(closeable.length > 0
    ? [
        "",
        "## Verified already-done (closed separately)",
        ...closeable.map((d) => "- #" + d.plan.number + ": " + d.evidence),
      ]
    : []),
  "",
  "Gates: flutter analyze + full flutter test suite run by the workflow before this PR was opened.",
].join("\n");
const landed = await commitAndPush(prTitle);
if (!landed.ok || !landed.pushed) {
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "landing the sweep branch failed" }, "issues");
  }
  return {
    conclusion:
      "The sweep implemented the fixes on " + branch + " but could not land them on the remote — " +
      (landed.ok
        ? "no commit was produced even though changes were detected earlier"
        : landed.error) +
      ". The fixes exist only on this machine; no PR was opened.",
    findings: [],
    verified: gatesOk ? ["flutter analyze", "flutter test"] : ["gates did not pass: " + gatesNote],
    notCovered: ["CI, review, merge and deploy — the branch never reached the remote"],
  } as WorkflowReport;
}
const pr = await world.run("gh", [
  "pr", "create", "--base", "main", "--head", branch,
  "--title", prTitle, "--body", prBody,
  ...(gatesOk ? [] : ["--draft"]),
]);
if (pr.exitCode !== 0) {
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "gh pr create failed" }, "issues");
  }
  return {
    conclusion:
      "The sweep implemented the fixes on " + branch + " but gh pr create failed:\n" + tail(pr.stderr),
    findings: [],
    verified: gatesOk ? ["flutter analyze", "flutter test"] : ["gates did not pass: " + gatesNote],
    notCovered: ["CI, review, merge and deploy — the PR could not be opened"],
  } as WorkflowReport;
}
const prUrl = pr.stdout.trim();
const prNumber = Number(prUrl.split("/").pop() ?? "0");
if (!gatesOk) {
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "gates not green — draft PR " + prUrl }, "issues");
  }
  return {
    conclusion:
      "Gates did not pass after 3 fix rounds (" + gatesNote + "), so the sweep opened DRAFT PR " + prUrl +
      " for a human instead of merging. Issues stay open.",
    findings: [],
    verified: ["flutter analyze (failed rounds fed to the coder)", "flutter test (failed rounds fed to the coder)"],
    notCovered: ["CI, review, merge and deploy — blocked by the gates"],
  } as WorkflowReport;
}
log("PR opened: " + prUrl + " — waiting for CI");
const firstCi = await awaitCi(prNumber, landed.head);
if (!firstCi.ok) {
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "CI did not pass on " + prUrl }, "issues");
  }
  return {
    conclusion:
      "CI did not pass on PR " + prUrl + " — " + firstCi.error +
      ". The PR is left open for a human; nothing was merged.",
    findings: [],
    verified: [
      "flutter analyze + full flutter test suite (green locally before the push)",
      "awaitCi on head " + landed.head.slice(0, 10) +
        ": remote-head booking, check registration, gh pr checks --watch — never reached green",
    ],
    notCovered: ["review, merge and deploy — blocked by CI"],
  } as WorkflowReport;
}
// The head that every later claim — re-CI, review, the merge pin, the
// report — names as CI-green. Advanced by each review-round push that
// re-CI'd green (issue #88).
let verifiedHead = landed.head;

// ---------------------------------------------------------------- phase 6
phase("Senior review of the whole diff, fix what it blocks");
const reviewer = agent("code reviewer", { system: REVIEWER_PERSONA });
const reviewAsk = (a: Agent, fresh: boolean) =>
  a.ask<ReviewVerdict>(
    (fresh
      ? "You are the final, independent approval before merge — you have seen nothing of how this change was made. "
      : "") +
    "Perform the full pre-merge review of PR #" + prNumber + " (" + prUrl + "). " +
    "Run 'gh pr diff " + prNumber + "' and read every file the diff touches, plus CLAUDE.md. " +
    "Judge correctness, regressions, edge cases, test coverage of changed behavior, 60fps-loop cost, " +
    "Flame component lifecycle, convention consistency, and any threat to the fully-offline guarantee. " +
    "Do not edit any file.",
  );
let verdict = await reviewAsk(reviewer, false);
for (let round = 1; round <= 2 && !verdict.approved; round++) {
  log("Review round " + round + " blocked: " + verdict.summary);
  await coder.ask(
    "The senior review blocked PR #" + prNumber + ". Fix every blocking finding:\n" +
    JSON.stringify(verdict.blocking),
  );
  const reAnalyze = await flutter("analyze", 300000);
  if (reAnalyze.exitCode !== 0) {
    await coder.ask("After the review fixes, flutter analyze regressed:\n" + tail(reAnalyze.output) + "\nRepair it.");
  }
  const reTests = await flutter("test", 900000);
  if (reTests.exitCode !== 0) {
    await coder.ask("After the review fixes, flutter test regressed:\n" + tail(reTests.output) + "\nRepair it.");
  }
  // Land the fixes on the PR before re-review (the PR #84 lesson):
  // without this push the reviewer reads a stale PR diff and blocks again
  // on a fix that already exists in the working tree — three blocked
  // rounds over an uncommitted one-liner. Since issue #88 the push is
  // checked and the new head is re-CI'd before anything merges: a
  // rejected push stops the sweep honestly instead of leaving the re-
  // review to read a diff that lacks the fix, and CI runs on the exact
  // head the reviewer judges and the merge later pins. An empty round
  // (nothing to commit) pushes no new head, so verifiedHead's green CI
  // still covers the head under re-review.
  const landedFix = await commitAndPush(
    "fix: address senior-review round " + round + " (issue sweep)",
  );
  if (!landedFix.ok) {
    for (const p of toImplement) {
      report({ issue: p.number, title: p.title, status: "failed", note: "pushing the review fixes failed on " + prUrl }, "issues");
    }
    return {
      conclusion:
        "The sweep stopped before merging: the review-round fixes could not be pushed to PR " + prUrl +
        " — " + landedFix.error + " The fixes exist only on this machine; the PR is left open on head " +
        verifiedHead.slice(0, 10) + " (the CI-green head, which does not include these fixes) for a human.",
      findings: [...verdict.blocking],
      verified: [
        "flutter analyze + full flutter test suite (green locally after the review fixes)",
        "gh pr checks --watch — green CI on head " + verifiedHead.slice(0, 10) +
          ", which predates the unpushed fixes",
      ],
      notCovered: ["re-review, merge and deploy — the fixes never reached the PR"],
    } as WorkflowReport;
  }
  if (landedFix.pushed) {
    const fixCi = await awaitCi(prNumber, landedFix.head);
    if (!fixCi.ok) {
      for (const p of toImplement) {
        report({ issue: p.number, title: p.title, status: "failed", note: "CI did not pass on the review-fix head of " + prUrl }, "issues");
      }
      return {
        conclusion:
          "The sweep stopped before merging: CI on the review-fix head " + landedFix.head.slice(0, 10) +
          " of PR " + prUrl + " did not pass — " + fixCi.error +
          " The PR is left open on that head for a human; nothing was merged.",
        findings: [...verdict.blocking],
        verified: [
          "flutter analyze + full flutter test suite (green locally — CI caught what they could not)",
          "gh pr checks --watch on the review-fix head " + landedFix.head.slice(0, 10) + " — not green",
        ],
        notCovered: ["re-review of the fix head, merge and deploy — blocked by CI"],
      } as WorkflowReport;
    }
    verifiedHead = landedFix.head;
  }
  verdict = await reviewAsk(reviewer, false);
}
const finalGates = await flutter("analyze", 300000);
const finalTests = finalGates.exitCode === 0 ? await flutter("test", 900000) : finalGates;
const gatesGreen = finalGates.exitCode === 0 && finalTests.exitCode === 0;
const independent = agent("independent reviewer", { system: REVIEWER_PERSONA });
const fresh = await reviewAsk(independent, true);
if (!verdict.approved || !gatesGreen || !fresh.approved) {
  const why = !verdict.approved
    ? "the senior reviewer did not approve: " + verdict.summary
    : !gatesGreen
      ? "gates were not green after the review fixes: " +
        tail(finalGates.exitCode !== 0 ? finalGates.output : finalTests.output)
      : "the independent reviewer did not approve: " + fresh.summary;
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "review blocked on " + prUrl }, "issues");
  }
  return {
    conclusion:
      "The sweep stopped before merging: " + why + ". PR " + prUrl + " is left open for a human; issues stay open.",
    findings: [...verdict.blocking, ...fresh.blocking],
    verified: [
      "flutter analyze + full flutter test suite after the review fixes",
      "senior review by the code reviewer" + (verdict.approved ? " (approved)" : " (blocked)"),
      "independent final review" + (fresh.approved ? " (approved)" : " (blocked)"),
    ],
    notCovered: ["merge and deploy — blocked by review"],
  } as WorkflowReport;
}
log("Review approved: " + fresh.summary);

// ---------------------------------------------------------------- phase 7
phase("Merge, deploy to TestFlight, and close the issues");
// The merge is pinned to the exact head CI and both reviews passed
// (issue #88): awaitCi confirmed gh books this sha as the PR head and
// watched it green, and nothing commits locally after that, so a
// mismatch means the branch moved some other way — and gh refuses the
// merge rather than shipping an untested head.
const merge = await world.run("gh", [
  "pr", "merge", String(prNumber), "--squash", "--delete-branch", "--subject", prTitle,
  "--match-head-commit", verifiedHead,
]);
if (merge.exitCode !== 0) {
  return {
    conclusion:
      "Review approved but gh pr merge failed — PR " + prUrl + " is open with green CI and both approvals on head " +
      verifiedHead.slice(0, 10) + "; the merge was pinned to that head (--match-head-commit), so if the branch has " +
      "moved since, the new head has had neither CI nor review. A human should merge it.\n" + tail(merge.stderr),
    findings: [],
    verified: [
      "flutter analyze + full flutter test suite (green)",
      "gh pr checks --watch — green CI on head " + verifiedHead.slice(0, 10),
      "senior review approved",
      "independent final review approved",
    ],
    notCovered: ["merge and deploy — the merge command failed"],
  } as WorkflowReport;
}
for (const p of toImplement) {
  report({ issue: p.number, title: p.title, status: "merged", note: "squash-merged to main" }, "issues");
}
await world.run("git", ["checkout", "main"]);
await world.run("git", ["pull", "--ff-only"]);

// Identify THIS sweep's release run by its commit: the squash commit
// GitHub recorded for the PR. The old query — "newest iOS Release run on
// main" — happily returned the previous sweep's already-completed run,
// and the sweep then closed its issues as "deployed to TestFlight"
// before its own build existed at all (issue #61). A run whose headSha
// is this merge commit is unambiguous; until that run appears, deployed
// stays false and the issues stay open. Every gh call is exit-code
// checked before JSON.parse, and a missing run is a wait, not an error.
let deployed = false;
let deployLine = "the iOS Release pipeline did not register a run";
let releaseRunId: string | null = null;
let commitSha: string | null = null;
let commitError = "";
for (let attempt = 0; attempt < 6 && commitSha === null; attempt++) {
  if (attempt > 0) await sleepSeconds(5);
  const view = await world.run(
    "gh",
    ["pr", "view", String(prNumber), "--json", "mergeCommit"],
    { timeoutMs: 60000 },
  );
  if (view.exitCode !== 0) {
    commitError =
      "gh pr view exited " + view.exitCode + ": " +
      tail(view.stderr || view.stdout);
    continue;
  }
  commitError = "";
  commitSha =
    (JSON.parse(view.stdout) as { mergeCommit: { oid: string } | null })
      .mergeCommit?.oid ?? null;
}
if (commitSha === null) {
  deployLine =
    "the PR's merge commit could not be read" +
    (commitError !== ""
      ? " — " + commitError
      : " (gh reports no merge commit for the PR yet)") +
    ", so the sweep refused to guess which release run was its own";
} else {
  const shortSha = commitSha.slice(0, 10);
  deployLine =
    "the iOS Release pipeline never registered a run for merge commit " +
    shortSha + " within ~2.5 minutes of the merge — the sweep refused " +
    "to watch an older run and close the issues on someone else's build";
  let runListError = "";
  for (let attempt = 0; attempt < 30 && releaseRunId === null; attempt++) {
    if (attempt > 0) await sleepSeconds(5);
    const runList = await world.run(
      "gh",
      [
        "run", "list", "--workflow", "iOS Release", "--commit", commitSha,
        "--json", "databaseId,headSha",
      ],
      { timeoutMs: 60000 },
    );
    if (runList.exitCode !== 0) {
      runListError =
        "gh run list --commit exited " + runList.exitCode + ": " +
        tail(runList.stderr || runList.stdout);
      break;
    }
    const found = JSON.parse(runList.stdout) as {
      databaseId: number;
      headSha: string;
    }[];
    // --commit already pins results to the merge commit; the headSha
    // match is a cheap assertion that never hurts (a re-run shares the
    // commit, and list order gives the newest run first).
    if (found.length > 0 && found[0].headSha === commitSha) {
      releaseRunId = String(found[0].databaseId);
    }
  }
  if (releaseRunId === null && runListError !== "") {
    deployLine = "looking up this sweep's release run failed — " + runListError;
  }
  if (releaseRunId !== null) {
    log(
      "Watching the iOS Release pipeline (run " + releaseRunId +
      ", commit " + shortSha + ") deploy to TestFlight",
    );
    const release = await world.run(
      "gh",
      ["run", "watch", releaseRunId, "--exit-status", "--interval", "60"],
      { timeoutMs: 2700000 },
    );
    deployed = release.exitCode === 0;
    deployLine = deployed
      ? "the iOS Release pipeline (run " + releaseRunId + ", commit " + shortSha + ") uploaded the build to TestFlight"
      : "the iOS Release pipeline (run " + releaseRunId + ", commit " + shortSha + ") FAILED — the merge is on main but TestFlight did not get a build";
  }
}
await closeDoneIssues();
if (deployed) {
  for (const p of toImplement) {
    await world.run("gh", [
      "issue", "close", String(p.number), "--comment",
      "Resolved in " + prUrl + " and deployed to TestFlight (issue-sweep pipeline).",
    ]);
    report({ issue: p.number, title: p.title, status: "closed", note: "merged + deployed" }, "issues");
  }
} else {
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "merged but deploy failed" }, "issues");
  }
}

await artifact.markdown(
  "sweep-report",
  [
    "# Issue sweep report",
    "",
    "- PR: " + prUrl + " (" + prTitle + ")",
    "- Review: " + verdict.summary,
    "- Independent review: " + fresh.summary,
    "- Deploy: " + deployLine,
    "- Issues resolved: " + numbers,
    ...(closeable.length > 0
      ? ["- Issues closed as already implemented: " + closeable.map((d) => "#" + d.plan.number).join(", ")]
      : []),
  ].join("\n"),
  { title: "Issue sweep report", description: "What the sweep resolved, reviewed, and deployed.", primary: true },
);

return {
  conclusion: deployed
    ? "Resolved " + numbers + " in " + prUrl + ", passed senior + independent review, merged to main, and " + deployLine + "."
    : "Resolved " + numbers + " in " + prUrl + " and merged to main, but " + deployLine + "; issues were left open for the next sweep or a human.",
  findings: [],
  verified: [
    "flutter analyze — clean",
    "flutter test — full suite green",
    "gh pr checks --watch — green CI on head " + verifiedHead.slice(0, 10) +
      " (analyze, the full test suite, and the unsigned iOS build) — the head the merge was pinned to (--match-head-commit, issue #88)",
    "senior review approved: " + verdict.summary,
    "independent final review approved: " + fresh.summary,
    deployed
      ? "gh run watch (iOS Release run " + releaseRunId + ", pinned to the PR's merge commit — issue #61) — TestFlight upload green"
      : "release-run identification pinned to the PR's merge commit (issue #61): " + deployLine,
  ],
  notCovered: [
    "on-device verification on a physical iPhone — the iOS simulator in CI is the closest check that ran",
  ],
} as WorkflowReport;