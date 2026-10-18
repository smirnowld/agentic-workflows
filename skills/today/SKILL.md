---
name: today
description: Build and publish the maintainer's Today page from the board and the code host. Run by the scheduled job on weekdays, and by the lead when a decision is urgent.
---

Spec: `docs/today.md` in this plugin's repository. Follow it exactly. Take everything project-specific from the lead folder's `track.md`: repositories, board, Today page URL, parent issues. Hard-code nothing.

## Gather (with `gh`, read-only)

1. **Last build**: the time of the previous publish (read the published page's build time, or fall back to the previous weekday 08:30).
2. **Needs you**: board items whose next actor is the maintainer, oldest first. For each: the effect, the recommendation and who reviewed it, the exact reply line (decisions); a deadline and the link to the instructions (steps); for a fence change, who gains or loses which right with proof before and after, never a diff.
3. **Finished**: pull requests merged and issues closed since the last build, in every repository in `track.md`. One plain line each, saying what changed for the maintainer or their users, with the pull request linked.
4. **Moving, or stuck**: in-progress board items whose last activity is older than the item's expected wait, with what each waits for.
5. **Measures**: one line: merged, reverted, lead tokens per merged outcome, paid minutes used against the month's budget (from the code host, the launch log and the billing usage; say "not available" for what you cannot read).

## Write

One self-contained HTML file: inline CSS, no external requests, phone-first single column, light and dark via `prefers-color-scheme`. Heading first: how many items need the maintainer, how many finished, since when. Then the four sections in the order above; a section with nothing says so in one line.

## Self-check before publishing

The draft must not be what it replaces. Check and fix: not the same text as the last build; no bare numbers standing in for words; no internal labels or ids the maintainer would have to look up; content, not counts; the build is stored (the page is published, not only shown); nothing built on a weekend unless something needs the maintainer.

## Publish

Publish with the Artifact tool to the URL in `track.md`, passing `url` so it is the same URL every time. Send a push notification with the page's link only for a new urgent decision; nothing else pushes. Report in chat the link and the heading's counts.
