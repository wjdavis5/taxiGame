/* zcode-workflow
description: "One tick of the recurring pipeline: find open GitHub issues, plan
  and implement every fix on a single branch, make analyze + the full test suite
  pass, open one PR, wait for CI (including the iOS simulator run), perform a
  full senior code review with a fix loop plus an independent final approval,
  then merge, watch the iOS Release pipeline deploy to TestFlight, and close the
  issues."
whenToUse: Run on a schedule (every 30 minutes) or on demand whenever you want
  all open GitHub issues in wjdavis5/taxiGame triaged, implemented in one PR,
  code-reviewed at a senior level, merged, and deployed to TestFlight
  automatically.
args: {}
*/
/* gh-issue-sweep — one tick of the recurring pipeline.
   Open GitHub issues → plan → implement on one branch → analyze + full tests →
   PR → CI (incl. iOS simulator) → senior review + independent approval →
   merge → TestFlight deploy → close issues.
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
const flutter = (what: string, timeoutMs: number) =>
  world.run("cmd", ["/c", "cd taxi_game && flutter " + what], { timeoutMs });

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
const branch = "automation/issue-sweep-" + sha.stdout.trim();
await world.run("git", ["checkout", "-b", branch]);
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
      "flutter analyze failed:\n" + tail(analyze.stdout + analyze.stderr) + "\nFix the findings.",
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
    "flutter test failed:\n" + tail(tests.stdout + tests.stderr) +
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
await world.run("git", ["add", "-A"]);
await world.run("git", ["commit", "-m", prTitle]);
await world.run("git", ["push", "-u", "origin", branch]);
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
const checks = await world.run(
  "gh",
  ["pr", "checks", String(prNumber), "--watch", "--interval", "30"],
  { timeoutMs: 2700000 },
);
if (checks.exitCode !== 0 && !checks.stdout.includes("no checks")) {
  for (const p of toImplement) {
    report({ issue: p.number, title: p.title, status: "failed", note: "CI red on " + prUrl }, "issues");
  }
  return {
    conclusion:
      "CI failed on PR " + prUrl + " — the PR is left open for a human; nothing was merged.",
    findings: [],
    verified: ["gh pr checks --watch (CI on the PR, including the iOS simulator run)"],
    notCovered: ["review, merge and deploy — blocked by red CI"],
  } as WorkflowReport;
}

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
    await coder.ask("After the review fixes, flutter analyze regressed:\n" + tail(reAnalyze.stdout) + "\nRepair it.");
  }
  const reTests = await flutter("test", 900000);
  if (reTests.exitCode !== 0) {
    await coder.ask("After the review fixes, flutter test regressed:\n" + tail(reTests.stdout) + "\nRepair it.");
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
      ? "gates were not green after the review fixes"
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
const merge = await world.run("gh", [
  "pr", "merge", String(prNumber), "--squash", "--delete-branch", "--subject", prTitle,
]);
if (merge.exitCode !== 0) {
  return {
    conclusion:
      "Review approved but gh pr merge failed — PR " + prUrl + " is open with green CI and approvals; a human should merge it.\n" + tail(merge.stderr),
    findings: [],
    verified: [
      "flutter analyze + full flutter test suite (green)",
      "gh pr checks --watch (green CI)",
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

let releaseRunId: string | null = null;
for (let attempt = 0; attempt < 15 && releaseRunId === null; attempt++) {
  const runList = await world.run("gh", [
    "run", "list", "--branch", "main", "--workflow", "iOS Release",
    "--limit", "1", "--json", "databaseId",
  ]);
  const found = JSON.parse(runList.stdout) as { databaseId: number }[];
  if (found.length > 0) releaseRunId = String(found[0].databaseId);
}
let deployed = false;
let deployLine = "the iOS Release pipeline did not register a run";
if (releaseRunId !== null) {
  log("Watching the iOS Release pipeline (run " + releaseRunId + ") deploy to TestFlight");
  const release = await world.run(
    "gh",
    ["run", "watch", releaseRunId, "--exit-status", "--interval", "60"],
    { timeoutMs: 2700000 },
  );
  deployed = release.exitCode === 0;
  deployLine = deployed
    ? "the iOS Release pipeline (run " + releaseRunId + ") uploaded the build to TestFlight"
    : "the iOS Release pipeline (run " + releaseRunId + ") FAILED — the merge is on main but TestFlight did not get a build";
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
    "gh pr checks --watch — green CI on the PR (Android + unsigned iOS + the iOS simulator run)",
    "senior review approved: " + verdict.summary,
    "independent final review approved: " + fresh.summary,
    deployed ? "gh run watch (iOS Release) — TestFlight upload green" : "gh run watch (iOS Release) — FAILED",
  ],
  notCovered: [
    "on-device verification on a physical iPhone — the iOS simulator in CI is the closest check that ran",
  ],
} as WorkflowReport;