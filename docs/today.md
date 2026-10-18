# The Today page

The maintainer's feed and inbox in one: a private page at a fixed address that says what needs them, what finished and what is stuck. It's computed from the board and the code host, so nobody maintains it, and the board stays the source.

## When it's built

- At 8:30 on weekdays, by a scheduled job running the `today` skill.
- Whenever something new needs the maintainer: the lead runs the skill when it puts an item on the board. An urgent item also sends a push notification with the page's link. Nothing else pushes.
- On weekends only when something needs the maintainer.

The page covers everything since it was last built, so a missed day loses nothing. Each build records its time on the page, and the next build reads it from there.

## What's on it

A heading that counts: how many items need the maintainer, how many finished, since when.

**Needs you.** Only the maintainer's decisions and steps, oldest first.

- A decision shows the effect, the recommendation with who reviewed it, and the exact line to reply with.
- A fence change shows who gains or loses which right and the proof before and after, never a diff.
- A step (something only the maintainer can do, like placing a secret) shows a deadline and links to the item with the instructions.

**Finished.** One line per item, in plain words, saying what changed for the maintainer or their users, with the pull request a click away. No numbers standing in for words.

**Moving, or stuck.** Only what has waited longer than expected, with what it waits for.

**Measures.** One line: merged, reverted, lead tokens per merged outcome, paid minutes used against the month's budget.

## How it's answered

The maintainer answers in the lead's chat, on the laptop or on the phone. The lead acts, updates the board, and the item leaves the page at the next build.

## Where its data comes from

| Section | Source |
|---|---|
| Needs you | Board items whose next actor is the maintainer: decisions and maintainer steps |
| Finished | Pull requests merged and issues closed since the last build, in the track's repositories |
| Moving, or stuck | Board items in progress whose last activity is older than the item's expected wait |
| Measures | The code host's merges and reverts, the launch log, the billing usage |

## Checks before publishing

The `today` skill checks its own draft before it publishes: no text repeated from the last build without a change, no bare numbers standing in for items, no internal labels, counts never in place of content, every item linkable later, nothing built on a weekend unless something needs the maintainer.
