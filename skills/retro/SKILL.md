---
name: retro
description: Run a retro with the maintainer - read the retro notes, the launch log, the sessions, the drift report and the lead's measures, check last retro's decisions, review costs once a month, and agree concrete changes to the setup. Use when the maintainer starts a retro.
---

The retro is the one place the process changes. It is a session the maintainer joins. You prepare, propose and record; the maintainer decides. When it runs is not this skill's business.

## Window

From the end of the last retro's window (the newest record in `$AGENTIC_RETRO_REPORTS`) to now; with no record, from the launch log's first line. If `AGENTIC_RETRO_REPORTS` or `AGENTIC_RETRO_NOTES` is unset or empty, say so and stop; don't guess a place. Say the window in the first line.

## Read

Use explorers for the reading, one per source, and keep only their conclusions.

1. **Retro notes**: every file in `$AGENTIC_RETRO_NOTES` in the window. No note for two weeks or more is a finding: notes may be taken where the variable is unset.
2. **Launch log**: `${AGENTIC_LOG_DIR:-~/.claude/agentic-workflows}/launch-log.jsonl`. Count each decision and read why: `deny` (a refused launch or start), `error` (a check that failed open), `rules-late` and `not-configured`, implementer launches with `route_ok` false, and `lead-write` (the lead's shell writes).
3. **Sessions**: the transcripts of the sessions each note names, and of the track's lead and coordinators, through the app's session tools. Find where the maintainer had to step in: commands they ran, approvals, answers to questions an agent could have settled, and turns a session spent on news that changed nothing.
4. **Drift**: the current `board-drift` report for each track's board and repositories (on PATH from the plugin's `bin/`). Count findings by kind and compare with the counts in the last records: a kind that keeps coming back is a gap.
5. **Lead measures**: the ones in [docs/lead.md](../../docs/lead.md).
6. **Reviews the maintainer took**: pull requests that went to the maintainer as a loosening ([docs/delegation.md](../../docs/delegation.md)), and whether the maintainer changed the outcome, from each pull request's reviews, commits after the request and the merge. Never changing it is a finding: propose moving those to agents.
7. **Last retro's decisions**: for each one in the last record, its measure and the figure now: met, not met (with the likeliest reason), or too early (in effect for less than a week).

## Cost review

At the first retro of each month, also review costs, over the month just ended:

- tokens per merged outcome, by track and by role;
- Codex tokens, from the launch log;
- what waking the lead costs: cache rebuilds after idle time;
- paid CI minutes against each track's budget, with the month's projection;
- the costliest sessions and what drove them (compactions, long idle, repeated reads);
- the levers: what would save the most, each with a rough saving and options, "leave it" among them. A route that should change is a lever with the runs that justify it.

Figures come from the launch log, the local transcripts and the code host's billing. One you cannot compute is written "not computed", with why; don't estimate it. A track with no budget is a finding.

## Propose

For each finding: what happened, with links; its cause; and the change to the setup that removes the cause (a rule, a hook, a check, a fence change, a route, a budget). A cause found at an earlier retro too means the setup has a gap, not that someone forgot: propose a mechanism, not a reminder. Put the findings in order of what they cost the maintainer.

Ask as numbered questions, each with its options and a proposed default, and discuss before anything is picked. A change to `routing.json` or a budget is always a question, never a default you apply.

## Record

1. The decisions taken, in this chat.
2. One proposed session per agreed change, with a brief that names the files and what done looks like, for the maintainer to start.
3. A record at `$AGENTIC_RETRO_REPORTS/YYYY-MM-DD.md` (the window's last day): the window; findings, causes and decisions; for each decision, the measure that shows it worked and the figure that counts as met; the drift counts by kind; the measures read, and in a month's first retro the cost figures, so the next retro compares. Nothing goes on the Today page.

Only the retro changes `routing.json`, and only as the maintainer agreed in it. Never change the process during the retro yourself, beyond what the maintainer agreed.
