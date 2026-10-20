---
name: today
description: Build and publish the maintainer's Today page from the board and the code host. Run by the scheduled job each weekday morning.
---

Spec: `docs/today.md` in this plugin's repository. Follow it exactly. Take everything project-specific from the lead folder's `track.md`: repositories, board, Today page URL, parent issues. Hard-code nothing.

## Gather (read-only: `gh`, and each provider's billing and usage the session can read)

1. **Last build**: the time of the previous publish (read the published page's build time, or fall back to the previous weekday 08:30).
2. **Needs you**: first, a notice for every open item whose Priority is P1: one line "P1 now: TITLE (LINK). Lower it?". Notices take effect at once, don't count in the heading's count, and leave the page once the item is closed or no longer P1. Then, in this order: (a) maintainer steps that hold up started work, each with what it holds up; the group's heading shows these steps against the track's cap when you know it ("4 of 5"), else omit it; the start check also counts pull requests that request the maintainer's review, which sit in (c), so say "plus N reviews" when there are any. A step holds up started work when an open issue that it blocks ("blocked by" link) has board Status In progress, In review or Waiting; find them from each maintainer step's `blocking` issues and their Status (GraphQL `blocking{nodes{state projectItems{nodes{fieldValueByName(name:"Status"){...on ProjectV2ItemFieldSingleSelectValue{name}}}}}}`). (b) steps that block a Ready item, one line each: "unblocks the next work item: TITLE (LINK)"; (c) the other board items whose next actor is the maintainer, oldest first. For each: the effect, the recommendation and who reviewed it, the exact reply line (decisions); a deadline and the link to the instructions (steps); for a fence change, who gains or loses which right with proof before and after, never a diff.
3. **Finished**: pull requests merged and issues closed since the last build, in every repository in `track.md`. One plain line each, saying what changed for the maintainer or their users, with the pull request linked.
4. **Moving, or stuck**: Waiting board items (the board's Waiting status: work stopped on someone else) whose last activity is older than the item's expected wait, with what each waits for. Also run `board-drift OWNER NUMBER --repo OWNER/REPO ...` (on PATH from the plugin's `bin/`; call it by bare name) for the track's board and every repository in `track.md`, and list its findings here: closed items not marked done, open pull requests not on the board, Waiting issues with no open "blocked by" link (the wait is on an issue but is not linked, or "Waiting for" is empty), In progress items with no update for the script's `--stale-days` (it covers In progress items only; the expected-wait rule above covers Waiting items, so nothing is listed twice). If the session lacks the `read:project` scope the script exits 2: show the drift list as "not available". An "upkeep due" finding (a finished phase or initiative) becomes one plain line the maintainer can read, for example "All parts of X are closed: close it or plan the next phase."
5. **Measures**: one line: merged, reverted, lead tokens per merged outcome, the organisation's spend this month against the free plans' allowances (from the code host, the launch log and each provider's billing and usage; say "not available" for what you cannot read).

## Write

One self-contained HTML file: inline CSS, no external requests, phone-first single column, light and dark via `prefers-color-scheme`. Heading first: how many items need the maintainer, how many finished, since when. Then the four sections in the order above; a section with nothing says so in one line.

## Self-check before publishing

The draft must not be what it replaces. Check and fix: not the same text as the last build; no bare numbers standing in for words; no internal labels or ids the maintainer would have to look up; content, not counts; the build is stored (the page is published, not only shown); nothing built on a weekend unless something needs the maintainer.

## Publish

Publish with the Artifact tool to the URL in `track.md`, passing `url` so it is the same URL every time. Send a push notification with the page's link only for a new urgent decision; nothing else pushes. Report in chat the link and the heading's counts.
