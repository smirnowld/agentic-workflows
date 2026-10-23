# Brief: TITLE

<!-- One work item for one coordinator, written by the lead. Conclusions, not reasoning: the receiver never needs the lead's chat. The one brief format; plans live in the epic's parent issue. -->

**Work item:** LINK to its issue, which the pull request closes
**Repository and base:** OWNER/REPO, from main
**Risk:** low | normal | critical | critical, a revert can't undo it: WHAT A MISTAKE WOULD DO  <!-- the last option means the strongest critical reviewer: a revert can't undo the harm and it reaches production data, backups, secrets or credentials, money, or real people's data -->
**Priority:** P1 | P2 | P3 | fire: THE BOARD ITEM'S PRIORITY, or fire  <!-- "fire" is only a brief value, never a board priority; it lets the work start while the cap or more items wait on the maintainer -->
**Lead session:** SESSION ID  <!-- the lead's own session id, for the coordinator's SendMessage -->
**Implementer kind:** trivial | specified | symptom-bug | native-mobile  <!-- the route's key in routing.json -->

## Goal

One or two sentences: the outcome, and how anyone can tell it's done.

## Settled

<!-- Decisions not to reopen, each with its link. -->
- DECISION (LINK)

## Where the work is

- PATH or RESOURCE

## Don't touch

- PATH or RESOURCE another session holds, and anything outside the fence

## Already known

<!-- Facts the receiver doesn't re-establish, each with its evidence. -->
- FACT (EVIDENCE)

## Proof

<!-- What must be green or shown before merge. A tester run on the real thing where the change touches something that runs. -->
- ACCEPTANCE CRITERION: EVIDENCE REQUIRED (one line for each criterion on the item)
- Review: the reviewer also says whether the docs are still true, and the pull request updates the docs it affects or says "No docs change:" with a reason.

## Needs the maintainer

<!-- Steps or decisions outside the fence, if any, as they will appear on the Today page. None is the usual answer. -->
- none

## Report back

A few lines to the lead, by SendMessage to the lead session and in your own chat: what changed for the maintainer, the proof with links, anything left and who acts next.
