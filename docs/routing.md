# Roles and routing

Each role runs on the model that measured best for its job. [routing.json](../routing.json) is the one place that says which; a launch check refuses a Claude launch whose model the role's route doesn't allow, and logs every launch. Pass the route's effort explicitly.

## Implementers

One implementer role, four kinds of task. The coordinator picks the kind from the brief and launches the primary model; after one failed round it relaunches with the fallback. Its Agent description starts with the kind and a colon (`specified: fix the runner label`); the log records the kind and whether the model matches that kind’s Claude route.

The coordinator passes each route's `effort` explicitly. The launch check refuses a routed Claude launch with mismatched or omitted effort, as it does a model mismatch.

| Kind (key in routing.json) | Examples | Primary | After a failed round |
|---|---|---|---|
| Trivial (`trivial`) | a one-line fix, a rename, a version bump | Sonnet, low | Codex Sol, low |
| Specified (`specified`) | CI, tooling, Go, server work with a clear brief, a feature with a clear spec | Codex Sol, medium | Sonnet, medium |
| Symptom bug (`symptom-bug`) | a bug known only by what it does: a flaky test, a crash, a runner that dies | Sonnet, medium | Opus, medium |
| Native mobile (`native-mobile`) | iOS and Android work that needs the native build and tests run | Sonnet, medium | Opus, medium |

Why: in blind-graded side-by-side runs, Codex Sol at medium did best on specified tooling and server work, and poorly on bugs given only as symptoms and on Android, where its sandbox can't run the native build or the simulator. Higher effort didn't help an implementer. Opus costs several times what Sonnet does for these bounded tasks, so it is only a fallback.

## Other roles

| Role | Model | Job |
|---|---|---|
| Coordinator | Opus, medium | Takes one work item from one brief; the start check compares each start in a track to this route. |
| Lead | Opus, medium | Briefs and delivers Ready work; never edits ([lead.md](lead.md)). |
| PM | Opus, high | Intent checks and specs need critical conversation ([ADR-0001](adr/0001-product-manager.md)). |
| Designer | Opus, high; Fable, high on the second attempt after “Not there” | Builds screens from design briefs ([ADR-0002](adr/0002-designer.md)); run by the PM through `designer-run`. |
| Spec critic | Codex Sol, high | Cold spec review through `codex-run` challenges gaps before Ready. |
| Strategist | Codex Sol, extra-high | Second opinion through `codex-run` on strategy and costs for maintainer decisions. |
| Explorer | Sonnet, low | Read-only search; returns conclusions with references. |
| Tester | Sonnet, low | Uses the product: runs a real job or flow on what the change touches and reports the run, timings and resources used. |
| Reviewer | Sonnet, medium | Independent review of normal and mechanical changes. |
| Critical reviewer | the other family: Codex Sol high for Claude-built work, Opus high for Codex-built work | Review of critical changes ([RULES.md](../RULES.md#proof-and-review)). |
| Strongest critical reviewer | the other family: Codex Astra extra-high for Claude-built work, Fable extra-high for Codex-built work | Only when a revert can't undo the harm and it reaches production data, backups, secrets or credentials, money, or real people's data. Never lowered. |
| Visual reviewer | Sonnet, medium | Screens and pages: layout, states, copy with the strings attached. |

An Agent launch of the designer is checked like the others; the PM uses `designer-run` because its folder denies edits.
Its Edit and Write allows cover only the output folder; Bash is unrestricted, so shell writes, git and network access are limited only by the designer's instructions.

The maintainer starts PM and lead sessions with their routes. Neither launch check nor start check validates their own session model or effort; start check checks coordinator starts in configured tracks. An Agent launch of PM or lead passes through, as do spec critic and strategist, which have no Claude route; use `codex-run` for their enforced route and read-only sandbox.

## The other family

A model family is one vendor's line of models: Claude (Sonnet, Opus) or OpenAI's Codex models. A reviewer from the other family than the implementer doesn't share its blind spots, so critical review always crosses families.

## Visual review

The visual reviewer runs on Sonnet: in a blind replay of past screen defects it caught as many as Opus, with less noise. It misses defects that show only when variants are measured, so scripts measure sizes and touch targets first. Copy is reviewed as part of the visual pass, not on strings alone. A critique of a planned screen is drawn, not written: wireframes with each open question as options side by side.

## Changing a route

Only the retro changes routing.json, with the runs that justify it.
