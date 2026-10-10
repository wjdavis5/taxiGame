# Cab Hustle future map. Run frame, 2026-10-10T00:20:33 local. Deadline 2026-10-11T00:20:33.

## Predicate, the definition of done

The GitHub issues of wjdavis5/taxiGame hold a complete, evidence-backed product roadmap by the deadline.

- One tracker issue plus child issues covering every area of the coverage matrix: uniqueness and submission, first-session hook, core-loop fun, difficulty and fairness, content variety, progression and retention, feel and polish, capability and stability.
- Every child issue names its acceptance criteria, a priority, a size, and the evidence that motivates it. Code claims cite repo path and line. Market claims cite a URL. Numbers come from the repo's own simulators or a named command.
- A second model family has adversarially reviewed the roadmap, and every finding is resolved or explicitly accepted with a reason.

## Scope, quantified

- Review: the whole shipped game, lib plus assets plus docs plus the current issue set. A competitor scan of about ten titles with citations. Measurements from the existing simulators. A uniqueness audit against the 4.3(a) rejection.
- Mapping: new milestones plus roughly 15 to 30 execution-ready issues.
- Out of scope: implementing the roadmap, which takes a separate go. App Store Connect actions, which stay the operator's item on #212. Anything network-dependent, which the app by design never ships.

## Rigor

High for every claim attached to an issue. Each number comes from a named command or a cited source. The competitor scan is desk research with URLs. Prototypes are reserved for a specific fork that stays unsettled after review and is cheap to settle.

## Phases

- A. Ground and frame. Done at 00:20.
- B. Review fan-out, six workers in parallel, this hour.
- C. Synthesis into a product thesis.
- D. Map into milestones and issues.
- E. Adversarial review of the map by a second model family.
- F. Window continuation. Deepen thin areas, run the cheap measurements, harden the issues.
- G. Close with the predicate check, the trail audit, and the cross-model trail review.

## Defaults and tradeoffs

- Default: this window maps and validates. Execution of the mapped plan waits for a separate go. If the operator wants execution inside the window instead, one plain sentence switches the run.
- No device on this machine, so on-device feel claims stay labeled as static analysis or design intent.
- No analytics exist and none can ship without changing the privacy claims, so fun is validated by simulators, code evidence, and operator playtests, never live metrics.
- The prior sweep's last unit, the frame-hygiene batch for #250 to #257, is still in flight. Its report gets handled as it lands, alongside this run.
