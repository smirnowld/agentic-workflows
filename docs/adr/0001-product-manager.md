# ADR-0001: Each track has a product manager beside its lead

**Status:** accepted

## Decision

Each track has one product manager (PM) at a time, beside its one lead. The PM works with the maintainer on what to build; the lead delivers what is ready. The PM is the custodian of the roadmap, not its owner: it does the groundwork and keeps the plan clean and visible, and challenges the maintainer's ideas against the vision, the strategy and the plan. It never invents requirements.

### What each one owns

| | PM | Lead |
|---|---|---|
| Ideas, specs, scoping, exploring an idea | yes | runs explorers only to scope a brief |
| Moving items Idea → Backlog → Ready, and the order of Backlog and Ready | yes | picks from Ready in that order |
| P2 and P3 | sets them | P1 only for fires and urgency found in flight |
| Ready → In progress → In review → Waiting → Done | | yes |
| Briefs, routing, starts, evidence, upkeep, fence decisions | | yes |
| Plan and roadmap changes, phase-end review of P3 items | yes | |
| Decisions for the maintainer | product, scope, order | fence, budget, maintainer steps |

**Each refuses the other's work, even when the maintainer asks.** It says in one line whose it is, passes it on (an Idea item and a message to the PM, or a message to the lead), and says where to continue. A fire is the one exception: the lead takes it whoever asked. The division changes through the retro or an ADR, never by an ask in chat.

### Where plans live

- The track's board is the only place for anything that moves: one board per track, with a product field. Ideas are items in an **Idea** status, a spec is the item's issue body, and order, priority and phase are board fields. Each phase's purpose and the coherent action it serves are in its parent issue.
- A product's repository holds code, its vision and strategy, and ADRs. No roadmap, plan or idea files.
- The PM publishes a roadmap page built from the board (phases, their items, each item's state) and rebuilds it when the board changes.
- The PM keeps nothing else: no notes files, no auto-memory about the track. Lasting product decisions become ADRs in the product's repository, through a work item.

### How the maintainer works with them

- Two chats per track: the PM's for what to build, the lead's for work in flight, fires and the "go" that lets the lead start what it has queued. The app starts sessions only in a turn the maintainer began, so starts stay in the lead's chat.
- Whatever the maintainer raises in one chat that belongs to the other reaches it: the lead files what-to-build as an Idea item and tells the PM; the PM passes in-flight matters to the lead.
- **A hand-off is never assumed.** When the maintainer asks the PM to drive something, the PM first restates the intent in two or three lines, what the maintainer would reject included, and the line between its calls and the maintainer's. Once confirmed, that is recorded on the item, and the PM's later calls on it cite it.

### How the PM and the lead work together

- The board is the interface. A direct message is rare: a requirement question, or a priority change that hits started work.
- An item enters Ready only when its spec meets the ready bar: intent the maintainer confirmed, acceptance criteria, open questions answered or written as assumptions with a default, phase and priority set, and the spec critic's findings settled.
- The lead may send an item back ("not ready: …"). A coordinator's requirement question goes to the PM through the lead, never to the maintainer; the PM answers from the spec and the recorded intent, or asks the maintainer in its own chat.
- Each finds the other by listing the app's sessions in the other's folder. The PM has its own track folder (`TRACK/pm/`), with no checkout and the edit tools denied, like the lead's; a shared folder would trip the one-lead check. Both are long-lived and keep their state on the board; a fresh one starts from the board when the maintainer starts it.

### What the PM decides alone

The test for a larger call is whether it changes what a phase delivers or when it ends. Larger calls are the maintainer's.

| PM alone | The maintainer's, brought by the PM as a decision |
|---|---|
| Wording and structure of specs, after the intent check | Adding an item to a phase, or removing one |
| Order inside a phase | Order of phases; anything that moves a phase's end |
| Triage of what agents raise or put off, with evidence | Anything the maintainer raised: the PM may park it with a reason, never close it |
| P1 for agent-found urgency, shown on the Today page to lower | A new feature: anything a phase's purpose doesn't cover |
| Read-only exploration of a logged idea, two explorer runs at most before a proposal | A new direction; a change to a track's intent |

Each decision it brings records whether the maintainer followed its recommendation; a class the maintainer always follows is the first candidate to move to the PM at a retro.

### Priority switches

Before a switch that touches started work or the current phase, the PM states once what pauses, what is lost, what slips, and whether it serves the strategy. Then the maintainer decides, and the PM stops arguing. The switch and its stated cost go on the item.

### Routes

| Role | Does | Route |
|---|---|---|
| PM | the conversation, intent checks, the ready bar, decisions | Claude Opus, high |
| explorer | scopes an idea against code, docs, history and the board | as routed |
| spec critic | reads a spec cold before Ready: gaps, ambiguity, conflicts with the strategy, the phase and other items; never rewrites | Codex, high |
| strategist | a second opinion on decisions that are the maintainer's: does it serve the strategy, what it costs, the best rival plan | Claude Fable, xhigh |

An analyst for outside research (users, market, vendors) is added with the first product track that needs it.

### How the retro judges it

Counted per retro, against a baseline taken from the sessions before the PM: items delivered wrong (failed acceptance or found wrong after merge); requirement questions that reached the maintainer from a lead or coordinator; ideas the maintainer raised that never reached the board; items the lead sent back; spec-critic findings that changed a spec; switches with stated against actual cost; decisions brought and followed, by class; tokens per item reaching Ready, by role; the maintainer's turns in the PM's chat per item reaching Ready.

A second track's lead starts only when at least five items have reached Ready through the PM, none was delivered wrong, no requirement question reached the maintainer from a lead or coordinator, and no idea the maintainer raised was lost.

## Consequences

- Two chats per track cost the maintainer some context switching; an ask in the wrong chat waits until the other is open.
- RULES.md's line that only the lead moves work between Ready, In progress, In review and Waiting changes: the PM moves items into Ready, the lead from Ready on.
- The organisation's strategy says the maintainer's work on a track goes through its PM; with two chats, that holds for what to build. The change is proposed to the maintainer where the strategy lives.
- A product's own board and roadmap file move into its track's board as the PM's first work.

## Context

Work reached agents underspecified: either it blocked on questions, or it was delivered wrong and failed acceptance, or it merged and was found wrong only once delivered. Ideas raised in one chat were lost, priority switches went in without their cost, and plans were kept in several places that drifted. The lead plans and delivers; nobody had the job of turning the maintainer's ideas into buildable work and holding them to the plan.

## Options considered

- **The lead does it**: rejected. Its context fills with delivery, and it can't challenge the plan it is executing.
- **The PM as the one front door, starting coordinators itself**: rejected. It would be a second lead, and the app starts sessions only in a turn the maintainer began.
- **Plans in repository files, mirrored on the board**: rejected. They drift, and a spec tweak becomes a pull request.
