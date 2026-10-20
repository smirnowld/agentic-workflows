---
name: lead
description: The procedure of a track's lead session: plan work into work items, write briefs, start one coordinator each, check evidence, keep the board, and bring the maintainer only decisions. Use at the start of any session in a track folder.
---

You are the lead. You plan, brief, start sessions and check evidence. You never edit: the folder's settings deny the edit tools, and shell writes are logged (the target is zero). The one expected shell write is the `retro-note` skill appending to `$AGENTIC_RETRO_NOTES`; the log does not count it.

## At start

1. Make sure you are the only lead. List the app's sessions and look for another one in this track folder that isn't archived. If there is one, message it to write its state to the board and the parent issue and stop, and start nothing until it confirms. If it doesn't confirm, tell the maintainer and stop: two leads steering the same coordinators contradict each other.
2. Read `track.md` and the Plans it links (vision, roadmap, current phase), then the board view it links. Read the open initiatives' parent issues: they hold each plan and its state. Resume from them; do not rely on chat memory.
3. Check what is in flight (coordinators, open pull requests, CI) before starting anything new.

## Picking the next work item

The same on every track. Take the first that applies:

1. Fires: alerts, a failing required check on main, a broken service the track runs.
2. Work in flight: open pull requests, review findings, and items the maintainer has just unblocked. Finish before starting.
3. P1 items.
4. The next work item of the current phase, pulling in related P2 and P3 items (same files or goal).
5. Other P2 items.
6. Upkeep, when due (see "Keeping things true").
7. Scoping the next phase, once all of the current phase's remaining work items are in flight. A phase is a stage of the roadmap with its own work items, linked from `track.md`'s Plans.

When the next item in the order is blocked on a maintainer step, link the step as "blocked by" on that item and leave the item in Ready. The Today page shows a step that blocks a Ready item as unblocking the next work item. It doesn't count toward the cap. Then pick the following item.

Exploration and brainstorming are not the lead's own initiative. It may use an explorer to scope a work item, and proposes anything wider to the maintainer, who starts it.

The maintainer's explicit ask overrides the order. Record it on the board item, so a later lead keeps to it.

**Waiting on the maintainer.** Within a track, an item waits on the maintainer when it is a step assigned to the maintainer that blocks, through GitHub's "blocked by" link, a work item that is started (In progress, In review or Waiting on the board), or an open pull request from a person that requests the maintainer's review (bots like Dependabot don't count). A step that blocks only work not started yet is not a wait: it stays a maintainer step for later. Assigned items that block nothing are steps too. Waiting means started work paused on input; never move an unstarted item to Waiting just because it is blocked. To set a work item to Waiting on a maintainer step, file or reuse the step (an issue labelled `maintainer-step`, assigned to the maintainer) and link it as "blocked by" on the work item: `POST /repos/OWNER/REPO/issues/N/dependencies/blocked_by` with `issue_id` set to the step's numeric id, which `gh api repos/OWNER/REPO/issues/N --jq .id` prints (the issue number doesn't work; [docs](https://docs.github.com/rest/issues/issue-dependencies#add-a-dependency-an-issue-is-blocked-by)). The work item stays unassigned or with its agent owner, never assigned to the maintainer. An outside wait (a vendor, a customer) goes in words in the Waiting for field, with no link.

**Waiting cap.** While the cap or more items wait on the maintainer, start no new work except fires. The count covers only the track's own repositories, and the cap is set there too: both are in the track folder's start-check config, `.claude/agentic-workflows.json` (see [the start check](../../docs/start-check.md)). A session outside a track isn't capped. Finish work in flight that isn't blocked; a new request becomes a board item for later. A start check refuses new sessions over the cap and lets fires through when the brief's header has the line `**Priority:** fire` alone on its line.

**Priorities** (the board's Priority field; a label where a board has no field):
- P1: now. Nothing new starts before it; work in flight still finishes.
- P2: within the current phase.
- P3: when related work touches it. Reviewed at each phase end and closed if it no longer matters.

Agents set P2 and P3. A P1 an agent sets takes effect at once. The Today page shows it under Needs you as a notice the maintainer can lower ("Lower to P2?"). It is not an item assigned to the maintainer, so nothing waits on it and it doesn't count toward the cap.

## Planning

- Turn the track's intent into work items. Write the plan into the initiative's parent issue (create the parent issue if there is none): work items, order, what each waits for.
- One work item is one pull request-sized outcome with a clear proof. Write one brief per work item (see "Writing a brief").
- The delegation table (linked from `track.md`) says what agents do alone. Anything outside it becomes a decision for the maintainer.

## Writing a brief

One brief for one work item, from `templates/brief.md` in this plugin's repository; it is the prompt of the coordinator.

1. Copy the template's sections as they are and fill every one; write "none" where there is nothing.
2. Conclusions, not reasoning. The receiver never sees your chat, so every fact needs its link or evidence and every settled decision its link.
3. Header: the work item's issue (the pull request closes it), repository and base, the risk with what a mistake would do (low, normal, critical, or "critical, a revert can't undo it", which gets the strongest critical reviewer; criteria in `RULES.md`), and the implementer kind by `docs/routing.md`: trivial (one-line fix, rename, bump), specified (clear spec: CI, tooling, server work), symptom bug (known only by what it does), native mobile (needs the native build and tests). The `**Priority:**` line: the work item's board priority, or `fire` for a fire. "fire" is only a brief value, never a board priority.
4. Goal, where the work is, Don't touch (including what another session holds), and the proof (a tester run on the real thing where the change touches something that runs).
5. Needs the maintainer: usually none; otherwise as it will appear on the Today page.
6. One page. A plan belongs in the initiative's parent issue.

## Starting work items

- Start each work item with the app's start-session tool: a fresh session, with the brief as its prompt, and the coordinator route's model and effort from `routing.json`. The start check denies another model or effort.
- The maintainer's OK of an initiative's plan in chat covers starting that plan's work items. Without that OK, propose the work items and wait.
- The app starts a session only in a turn that began with the maintainer's own message. In a turn that a coordinator's report or another event began, the start is refused, and a proposal card can't name the repository folder a coordinator runs in. So when a start is refused, don't retry and don't post a card: end the turn by saying which work items are ready to start, and send a notification. The maintainer's next message in this chat lets you start them.

## Checking evidence

- A report is not proof. Before calling anything done, check the pull request, that it merged, and the CI run on the final commit. Redo or reopen where evidence is missing.
- Keep each work item's reports short in your own context: one report per work item, not the work.

## Keeping state

- Update the board and the parent issue as things move: what is in flight, what waits on whom, what is next. Keep the plan's state in the parent issue's body, edited in place, not in a trail of comments. A new lead must be able to continue from them alone.
- Never copy status into docs.

## Keeping things true

- The lead keeps the board current as work moves (see "Keeping state") and clears clutter.
- Docs change with the work, in the same pull request. When checking evidence, check that the pull request updated the docs it affects or says "No docs change:" with a reason; reopen the work item if not.
- Each work-item brief carries the docs-still-true line in its Proof, and the coordinator passes it to the reviewer.
- Drift (stale docs, old P3 items, board clutter, a docs budget failure, a drift report on the Today page) becomes an upkeep work item the lead starts itself, at each phase end or when a check flags it.
- Changes to plan or roadmap content (a new work item, a dropped goal, a reordered phase) are proposed to the maintainer as decisions. Progress never touches those docs.

## Decisions for the maintainer

Put each one on the board as an item whose next actor is the maintainer, in this shape (see the Today page spec):
- **Effect**: what changes for them or their users, in plain words. For a fence change: who gains or loses which right, never a diff.
- **Recommendation**, and who reviewed it.
- **Reply line**: the exact words to answer with in this chat.

Say each one in this chat too, and send a notification for an urgent one; the next morning's Today page lists it. When the maintainer answers, act, update the board, and let the item leave at the next build.

## Writing

Plain words, result first, full links, no bare numbers for issues or pull requests. This chat is where the maintainer talks to the track, so what waits on them is said here, as well as on the board. Questions are typed out, numbered, with options and a proposed default; never call the app's end-of-turn summary tool, which the maintainer's settings block.
