# The lead

Each track has one lead: a Claude session that turns the track's intent into work, keeps its board, and brings the maintainer only what the delegation table says to. It doesn't build anything itself.

## The chain

| Who | Does | Holds |
|---|---|---|
| Maintainer | Sets direction, answers the decisions on the Today page | |
| Lead | Plans, writes briefs, starts one session per work package, checks their evidence, keeps the board | the track brief, the board, short reports |
| Package session | One work package from one brief, in its own worktree: coordinates, verifies, merges inside the fence | the brief and the package's files |
| Subagents | Implementer, tester, explorer, reviewers | only their own slice |

The lead starts package sessions, not implementers. A package session runs its own subagents and sends back a few lines: what changed, the proof, what needs the maintainer. The lead's context grows by one short report per package, not by the work itself.

## The track folder

A session started in the track's folder is that track's lead. Nothing needs typing: the folder's instructions and settings make it so.

```
TRACK/
  CLAUDE.md               # "You are the lead of TRACK": loads the lead skill, reads track.md
  .claude/settings.json   # denies the edit tools; turns on this plugin
  track.md                # intent, repositories, links: delegation table, runbooks, board, parent issues
```

The track's repositories are added as read-only directories, at their main branches. The lead has no worktree. Its settings deny the edit tools, which the app enforces. A shell write is still possible, so the launch log counts the lead's writes from day one; the target is zero.

[templates/track/](../templates/track/) holds a starting copy.

## How long a lead runs

Not by the clock, and not by a budget. The lead writes its state to the board and the initiative's parent issue as it goes: what's in flight, what waits on whom, what's next. So it compacts like any other session and loses little, and work that runs into the next day just continues. A fresh lead starts only when the maintainer starts one, and it starts from the board.

The Today page ([today.md](today.md)) is built by a separate scheduled job, so it doesn't depend on the lead ending a day cleanly.

## Measures

- Lead tokens per merged outcome, compared with the previous setup's coordination for the same kind of work.
- How often the maintainer had to step in on tactics.
- What waking the lead costs: cache rebuilds after idle time.
- The lead's own edits and shell writes: the target is zero.

The first retro looks at these, and again after five working days. If the lead costs more than the old coordination for no gain, the retro proposes a different shape.
