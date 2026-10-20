# The Today page

The maintainer's feed and inbox in one: a private page at a fixed address that says what needs them, what finished and what is stuck. It's computed from the board and the code host, so nobody maintains it, and the board stays the source.

## When it's built

Once each weekday, at 8:30, by a scheduled job running the `today` skill. The page is that morning's snapshot, the state the lead bases its day on, and it isn't rebuilt during the day. What comes up later is said in the lead's chat, where the maintainer talks to the track, and is on the board, so the next morning's page lists it. An urgent item also sends a push notification. Nothing else pushes.

The page covers everything since it was last built, so a missed day loses nothing. Each build records its time on the page, and the next build reads it from there.

## What's on it

A heading that counts: how many items need the maintainer, how many finished, since when.

**Needs you.** Only the maintainer's decisions and steps. In this order:

1. P1 notices (below).
2. Steps that hold up started work, each with what it holds up. The group's heading shows these steps against the track's cap ("4 of 5") when the page knows it. The start check also counts pull requests that request the maintainer's review (group 4), so its count can be higher. A step holds up started work when an open issue it blocks ("blocked by" link) has board Status In progress, In review or Waiting.
3. Steps that block a Ready item: "unblocks the next work item: TITLE (LINK)". Such a step unblocks the lead's next work item; it does not hold up started work.
4. Other items whose next actor is the maintainer, oldest first.

The page finds groups 2 and 3 from each maintainer step's `blocking` issues and their board Status (GraphQL `blocking{nodes{state projectItems{nodes{fieldValueByName(name:"Status"){...on ProjectV2ItemFieldSingleSelectValue{name}}}}}}`).

- A P1 notice: every open item whose Priority is P1 shows first, as one line, "P1 now: TITLE (LINK). Lower it?". Notices take effect at once, don't count in the heading's count, and leave the page once the item is closed or no longer P1.

- A decision shows the effect, the recommendation with who reviewed it, and the exact line to reply with.
- A fence change shows who gains or loses which right and the proof before and after, never a diff.
- A step (something only the maintainer can do, like placing a secret) shows a deadline and links to the item with the instructions.

**Finished.** One line per item, in plain words, saying what changed for the maintainer or their users, with the pull request a click away. No numbers standing in for words.

**Moving, or stuck.** Only what has waited longer than expected, with what it waits for. It also lists the findings of `board-drift` for the track's board and repositories: closed items not marked done, open pull requests not on the board, Waiting issues with no open "blocked by" link and no outside wait written in words in "Waiting for" (the start check can only count linked blockers), and In progress items with no update for the script's `--stale-days`. That setting covers In progress items only; the expected-wait rule covers Waiting items, so nothing is listed twice. Without the `read:project` scope the script exits 2 and the list shows as "not available". An open issue whose sub-issues are all closed (a finished phase or initiative) is worded as one plain line: all its parts are closed, close it or plan the next phase.

**Measures.** One line: merged, reverted, lead tokens per merged outcome, paid minutes used against the month's budget.

## How it's answered

The maintainer answers in the lead's chat, on the laptop or on the phone. The lead acts, updates the board, and the item leaves the page at the next build.

## Where its data comes from

| Section | Source |
|---|---|
| Needs you | Board items whose next actor is the maintainer: decisions and maintainer steps |
| Finished | Pull requests merged and issues closed since the last build, in the track's repositories |
| Moving, or stuck | Waiting board items whose last activity is older than the item's expected wait; the findings of `board-drift` |
| Measures | The code host's merges and reverts, the launch log, the billing usage |

## Checks before publishing

The `today` skill checks its own draft before it publishes: no text repeated from the last build without a change, no bare numbers standing in for items, no internal labels, counts never in place of content, every item linkable later, nothing built on a weekend unless something needs the maintainer.
