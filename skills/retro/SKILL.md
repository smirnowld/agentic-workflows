---
name: retro
description: Run the weekly retro with the maintainer - read the retro notes, the launch log, the sessions, the drift report and the lead's measures, and agree concrete changes to the setup. Use when the maintainer starts a retro.
---

The retro is the one place the process changes. It is a session the maintainer joins, on Fridays; the first one five working days after a lead starts. You prepare, propose and record; the maintainer decides.

## Read

For the week since the last retro (the newest record in `$AGENTIC_RETRO_REPORTS`; with none, since the lead started):
1. **Retro notes**: every file in `$AGENTIC_RETRO_NOTES` for those days. If either variable is unset or empty, say so and stop; don't guess a place.
2. **Launch log**: `${AGENTIC_LOG_DIR:-~/.claude/agentic-workflows}/launch-log.jsonl`. Count denies and refused starts and read why, routes that didn't match, the lead's shell writes, and Codex tokens.
3. **Sessions**: the transcripts of the sessions each note names, and of the track's lead and coordinators, through the app's session tools. Find where the maintainer had to step in: commands they ran, approvals, answers to questions an agent could have settled.
4. **Drift**: the current `board-drift` report for each track's board and repositories (on PATH from the plugin's `bin/`).
5. **Lead measures**: the ones in `docs/lead.md` in this plugin's repository.
6. On the first retro of a month, also the cost review: tokens per merged outcome by track, Codex tokens, and paid CI minutes against the budget.

Use explorers for the reading, one per source, and keep only their conclusions.

## Propose

For each finding: what happened, with links; its cause; and the change to the setup that removes the cause (a rule, a hook, a check, a fence change, a route). A cause found at an earlier retro too means the setup has a gap, not that someone forgot: propose a mechanism, not a reminder. Put the findings in order of what they cost the maintainer.

Ask as numbered questions, each with its options and a proposed default, and discuss before anything is picked.

## Record

1. The decisions taken, in this chat.
2. One proposed session per agreed change, with a brief that names the files and what done looks like, for the maintainer to start.
3. A record at `$AGENTIC_RETRO_REPORTS/YYYY-MM-DD.md`: findings, causes, decisions, the sessions proposed, and the measures read. Nothing goes on the Today page.

Never change the process during the retro yourself, beyond what the maintainer agreed in it.
