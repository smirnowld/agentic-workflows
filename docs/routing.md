# Roles and routing

Each role runs on the model that measured best for its job. [routing.json](../routing.json) is the one place that says which; a launch check compares every launch with it and logs any difference.

## Implementers

One implementer role, four kinds of task. The package session picks the kind from the brief and launches the primary model; after one failed round it relaunches with the fallback.

| Kind (key in routing.json) | Examples | Primary | After a failed round |
|---|---|---|---|
| Trivial (`trivial`) | a one-line fix, a rename, a version bump | Sonnet, low | Codex Sol, low |
| Specified (`specified`) | CI, tooling, Go, server work with a clear brief, a feature with a clear spec | Codex Sol, medium | Sonnet, medium |
| Symptom bug (`symptom-bug`) | a bug known only by what it does: a flaky test, a crash, a runner that dies | Sonnet, medium | Opus, medium |
| Native mobile (`native-mobile`) | iOS and Android work that needs the native build and tests run | Sonnet, medium | Opus, medium |

Why: in 39 side-by-side runs, blind-graded, Codex Sol at medium did best on specified tooling and server work, and poorly on bugs given only as symptoms and on Android, where its sandbox can't run the native build or the simulator. Higher effort bought nothing on any kind. Opus costs several times what Sonnet does for these bounded tasks, so it is only a fallback; its mobile fallback rests on past pull requests and hasn't been rerun yet.

## Other roles

| Role | Model | Job |
|---|---|---|
| Lead | Opus, medium | Plans and briefs; never edits ([lead.md](lead.md)). |
| Explorer | Sonnet, low | Read-only search; returns conclusions with references. |
| Tester | Sonnet, low | Uses the product: runs a real job or flow on what the change touches and reports the run, timings and resources used. |
| Reviewer | Sonnet, medium | Independent review of normal and mechanical changes. |
| Critical reviewer | the other family: Codex Sol medium for Claude-built work, Opus medium for Codex-built work | Review of critical changes ([RULES.md](../RULES.md#proof-and-review)). |
| Visual reviewer | Sonnet, medium | Screens and pages: layout, states, copy with the strings attached. |

## The other family

A model family is one vendor's line of models: Claude (Sonnet, Opus) or OpenAI's Codex models. A reviewer from the other family than the implementer doesn't share its blind spots, so critical review always crosses families.

Codex hasn't yet been measured as a reviewer. A blind replay of past pull requests whose real defects are known scores both families in the first week. If Codex misses much more than Claude, Claude-built work goes back to a Claude critical reviewer.

## Visual review

A replay of seven past screen defects found the visual reviewer worth keeping on the fast tier: it caught 14 of 23, as many as the standard tier, with less noise. It missed defects that show only when variants are measured, so scripts measure sizes and touch targets first. Copy review on strings alone added little, so copy is part of the visual pass. A critique of a planned screen is drawn, not written: wireframes with each open question as options side by side.

## Changing a route

Only the retro changes routing.json, with the runs that justify it.
