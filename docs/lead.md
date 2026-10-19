# The lead

Each track has one lead: a Claude session that turns the track's intent into work, keeps its board, and brings the maintainer only what the delegation table says to. It doesn't build anything itself.

## The chain

| Who | Does | Holds |
|---|---|---|
| Maintainer | Sets direction, answers the decisions on the Today page | |
| Lead | Plans, writes briefs, starts one session per work item, checks their evidence, keeps the board | the track brief, the board, short reports |
| Coordinator | One work item from one brief, in its own worktree: coordinates, verifies, merges inside the fence | the brief and the work item's files |
| Subagents | Implementer, tester, explorer, reviewers | only their own slice |

The lead starts coordinators, not implementers. A coordinator runs its own subagents and sends back a few lines: what changed, the proof, what needs the maintainer. The lead's context grows by one short report per work item, not by the work itself.

## What the lead picks next

The [lead skill](../skills/lead/SKILL.md) sets the order, the same on every track: fires, work in flight, P1 items, the current phase's next work package (with related P2 and P3 items), other P2 items, upkeep, then scoping the next phase. The maintainer's explicit ask overrides it. While the cap or more items wait on the maintainer, only fires start. The count covers the track's own repositories, and the cap is set in the track's start-check config ([start check](start-check.md)); a session outside a track isn't capped. Docs change with the work, and drift becomes an upkeep work item the lead starts itself; changes to plan or roadmap content are proposed to the maintainer as decisions.

## The track folder

The folder lives outside any repository, so the lead has no checkout to edit. A session started in it is that track's lead. Nothing needs typing: the folder's instructions and settings make it so.

```
TRACK/
  CLAUDE.md               # "You are the lead of TRACK": loads the lead skill, reads track.md
  .claude/settings.json   # denies the edit tools; turns on this plugin
  track.md                # intent (scope, projects, limits), plans, repositories, links: delegation table, runbooks, board, parent issues
```

The track's repositories are added as read-only directories, the main checkouts at their main branches. The lead has no worktree. Its settings deny the edit tools, which the app enforces. A shell write is still possible, so the launch log counts the lead's writes from day one; the target is zero.

[templates/track/](../templates/track/) holds a starting copy.

## How long a lead runs

Not by the clock, and not by a budget. The lead writes its state to the board and the initiative's parent issue as it goes: what's in flight, what waits on whom, what's next. So it compacts like any other session and loses little, and work that runs into the next day just continues. A fresh lead starts only when the maintainer starts one, and it starts from the board.

The Today page ([today.md](today.md)) is built by a separate scheduled job, so it doesn't depend on the lead ending a day cleanly.

## Measures

- Lead tokens per merged outcome.
- How often the maintainer had to step in on tactics.
- What waking the lead costs: cache rebuilds after idle time.
- The lead's own edits and shell writes: the target is zero.

The first retro looks at these, and again after five working days. If the lead's cost per outcome isn't worth what it saves the maintainer, the retro proposes a different shape.
