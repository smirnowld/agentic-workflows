# The lead

Each track has one lead at a time: a Claude session that turns the track's intent into work, keeps its board, and brings the maintainer only what the delegation table says to. It doesn't build anything itself.

## The chain

| Who | Does | Holds |
|---|---|---|
| Maintainer | Sets direction, answers the decisions on the Today page | |
| Lead | Plans, writes briefs, starts one session per work item, checks their evidence, keeps the board | the track brief, the board, short reports |
| Coordinator | One work item from one brief, in its own worktree: coordinates, verifies, merges inside the fence | the brief and the work item's files |
| Subagents | Implementer, tester, explorer, reviewers | only their own slice |

A new lead first checks that no other lead is live in the track folder; if one is, it asks that lead to write its state to the board and stop before taking over.

The lead starts coordinators, not implementers. A coordinator runs its own subagents and sends back a few lines: what changed, the proof, what needs the maintainer. The lead's context grows by one short report per work item, not by the work itself.

## Talking to coordinators

The app lets a session that starts another watch it: every turn the started session ends wakes the starter. So the lead detaches each coordinator right after starting it, and the brief names the lead's session. The coordinator then messages the lead only when its work item is done, blocked, needs a decision, or found something that changes the plan. A message that changes nothing gets no reply to its sender, and one word in the lead's chat, since a turn that ends with no text costs another. Coordinators wait on CI in the foreground, so their turns end only when they are done, blocked or need a decision.

The lead keeps no watch of its own, so on each wake it checks the coordinators in flight, by the session ids it keeps in the parent issue. A stuck one (its turn ended with no report, it waits on a permission prompt, or it has been quiet for two hours) gets one message; still stuck at the next wake, the lead says so in its chat and sends a notification. A coordinator stuck while the lead sleeps shows at the lead's next wake; one with no board update for days also shows in the Today page's drift.

App limits the lead works within:
- Starts require a turn begun by the maintainer. The lead queues next starts and shows additions in chat; any maintainer message starts safe queued work. "Hold" pauses it until they say otherwise. Start cards are for urgent work while the maintainer is away.
- Put every session you start in the track's sidebar group (one group per track, named with the track's short name), and start its name with the track's short name and the work item.
- A session in another permission mode than the sender holds its messages for the maintainer's approval, so the lead and its coordinators run in the same mode.
- A detached session no longer shows as the lead's in the app's linked sessions; the ids in the parent issue are how the lead finds it.

The lead's chat is where the maintainer talks to the track.

## What the lead does without asking

Archiving finished sessions, closing issues that evidence shows are done, finishing work in flight inside the fence, checking sessions, pull requests and CI before asking, and keeping the board. It asks only what the delegation table puts outside the fence. A maintainer step comes with one block to copy, paste and run as it is, in the pull request body or the step's issue.

When the track has no plan to pick from, the lead says so and proposes one. Exploration starts with the maintainer's ask in the lead's chat; the lead scopes it with explorers and returns a proposed plan in a parent issue.

## Keeping the board

The lead moves board items with `board-set`, a batch per wake. It never runs `gh project item-edit` by field name in a loop: each call reads every project field again. It reads `gh project field-list` and `gh project item-list` once per session and reuses what they return.

## What the lead picks next

The [lead skill](../skills/lead/SKILL.md) sets the order, the same on every track: fires, work in flight, P1 items, the current phase's next work package (with related P2 and P3 items), other P2 items, upkeep, then scoping the next phase. The maintainer's explicit ask overrides it. While the cap or more items wait on the maintainer, only fires start. The count covers the track's own repositories, and the cap is set in the track's start-check config ([start check](start-check.md)); a session outside a track isn't capped. Only a step that holds up started work counts as a wait. A step that blocks only unstarted work doesn't count; when it blocks the next item, the lead links it, the Today page shows it as the next step to take, and the lead picks the following item. Docs change with the work, and drift becomes an upkeep work item the lead starts itself; changes to plan or roadmap content are proposed to the maintainer as decisions.

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

Each [retro](../skills/retro/SKILL.md) looks at these. If the lead's cost per outcome isn't worth what it saves the maintainer, the retro proposes a different shape.
