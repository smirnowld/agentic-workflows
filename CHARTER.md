# Charter

How one person runs many projects with agents doing the work. This is the second version of the setup (2.0). The first (1.0) is input, evidence of what worked and what didn't, not a base to edit. Project details, hosts, costs and trial logs are kept privately.

## Purpose

The maintainer works like the CEO/CTO of a 200–500 person company: vision, strategy, users, roadmap, and the quality and design bar. They want to be busy and active, with many streams in flight, spending their time on direction rather than tactics. Agents do everything else: planning, implementation, testing, review, operations and admin. They act within delegated authority, and mechanisms enforce its limits.

## What changed from 1.0

1. **Claude is the entry point.** The maintainer talks to Claude in the Claude desktop app. OpenAI models do work where they are cheaper, faster or better for that job. Not provider-neutral.
2. **The maintainer directs rather than approves.** A routinely rubber-stamped gate is either removed or replaced by a mechanism. Pretend control costs attention and protects nothing.
3. **Mechanisms over remembered rules.** What matters is enforced: hooks, checks, rulesets, admission policies, tool restrictions, scoped identities. Everything else is short guidance.
4. **Status is computed, not maintained.** Progress comes from PRs, issues, sessions, CI and deployments. Only intent is written by hand.
5. **Each agent gets the context its job needs, and no more.**
6. **Opinionated.** It names the actual tools, with one way to do each thing.
7. **Agents act on their own, including with secrets and commands.** They work within scoped identities and an audit trail, not under the maintainer's watch.

## Non-goals

- Provider neutrality, or the same experience in several apps.
- Claude cloud sessions, even as an opt-in. They skew cost reporting, and every token must be visible.
- Multiple users.

## Measures

| Measure | Direction |
|---|---|
| Maintainer actions that are mechanical (copy-pasted commands, rubber-stamped merges and approvals, reading tactical detail) | near zero |
| Share of maintainer decisions that are about direction (vision, users, roadmap, design, standards) | most of them |
| Outcomes shipped per week, by track | up |
| Tokens per shipped outcome, within the Claude and Codex subscription budgets | down |
| Reverts, escaped defects, incidents | not up |
| Updates the maintainer can understand cold, without opening anything (rated yes/no) | nearly all |

The number of sessions or streams the maintainer touches is **not** a measure. More high-level steering while agents deliver counts as a win.

## Layers

1. **Intent.** Vision, users, roadmap, quality and design bar, the delegation table. Shaped in conversation with AI, which writes it down and keeps it consistent. The maintainer decides.
2. **Management.** One lead per track. It turns intent into work, owns tactical decisions within delegated authority, and escalates only what the table says to.

   *Open:* 1.0 coordinators implemented work themselves, carried too much context and seemed expensive. Design against that: a lead with no checkout to edit, its state kept in issues rather than chat, wake-ups only when work finishes. Measure the lead's tokens per outcome.
3. **Execution.** Workflows made of roles: implementers, testers (who use the product), and reviewers for code, UI, UX, visual design, docs and security. Each role is routed to the model that suits it and given only its own context.
4. **Controls.**
   - GitOps: a merge is the deploy.
   - Rulesets, admission policies, RBAC.
   - Scoped identities per track, including secrets that agents use but never see.
   - Budgets, an audit log, rollback.
5. **Visibility.**
   - A feed of finished work: one line each, details a click away.
   - An inbox holding only the maintainer's decisions.
   - Portfolio and thread views: phases, deliverables, outcomes, KPIs.
   - A visual plan for each initiative, and an org-structure view of who does what.
   - Likely built into the maintainer's existing dashboard.
6. **Learning.**
   - Process metrics.
   - A retro capture skill: the maintainer calls it mid-session with a line on what was wrong, and it records that with the session, time and context.
   - A scheduled retro: it reads the captured notes, sessions, skills and metrics, and proposes concrete changes with examples. The retro is the one place where the process changes.

## Writing for the maintainer

Every update, report and feed line has to land for a reader who has no prior context:

- plain words, leading with what changed for them or what they must decide;
- never a bare issue or PR number; what the item is goes in words, with the link for depth;
- no internal labels unless the maintainer must act on one.

A mechanism checks this, a review step on generated reports, and the maintainer's yes/no ratings feed the retro. 1.0's daily summary note is the counter-example to study.

## Authority, in principle

The full delegation table is a later document. Its principles:

- **Agents decide, act and merge:** work inside the fence (the limits that mechanisms enforce: access rights, admission policies, rulesets, scoped identities), including running commands and using the secrets their identity holds, with checks green and independent review passed. It appears in the feed.
- **The maintainer decides:**
  - direction: vision, roadmap, users, design taste, the maintainer's own touch points, high-impact standards;
  - starting and stopping tracks;
  - budget and provider split;
  - changes to the fence: RBAC, admission policies, rulesets, identities, which secrets an identity holds, the delegation table;
  - irreversible or outward-facing actions: publishing, money, accounts, real people's data.
- **Open:** how a fence change is shown so the maintainer actually judges it. The proposal is effects, not code: who gains or loses which right, proven before and after, checked by a reviewer from another model family. If even that gets rubber-stamped, replace the gate with audit plus revert.

## Lessons carried from 1.0

- **Route by measured results, and verify outside the labour model.** In 39 blind-graded reruns, Codex Sol medium did well on tooling, CI, Go and spec'd server work, and poorly on Android and on bugs given only as symptoms; higher effort bought nothing. The test lane decided the grade more than the model did. The strongest model took most of the spend.
- **One owner per fact works; hand-kept mirrors don't.** Boards had the right shape, but their use was never measured and some fields were still copied by hand.
- **Silent failures are the main risk.** The app quietly capped a started session's model and effort, and nothing noticed until a hook did. Every mechanism gets a test that it fires.
- **Prove a reviewer before it gates.** The design review replay (seven past defects the maintainer caught, blind-scored) found the visual reviewer worth keeping: it caught 14 of 23 defects, the fast tier as well as the standard one. It missed defects that only show when variants are measured, so scripts measure those. Copy review on strings alone added little, and every tier was noisy, at 8–13 stray findings a case. Build blind grading into the retro.
- **A rule plus a hook did not stop coordinators implementing; structure has to.** 12% of sessions (21 of 173) still did their own implementing because the edit hook fails open and doesn't see shell writes. Delegated sessions cost about a third less. In 2.0 the lead has no checkout, and the self-implementing share is measured from day one.
- **Hooks that block cost more than they catch unless measured.** In ten days the question hook denied 47 questions, 19 of them dismissed, and the stop hook forced 139 extra turns, each re-reading the whole context. Both were removed. Start with few hooks, count blocks and false positives for each, and alert when one fails open.
- **Shipped helpers beat free-form loops.** Hand-written waits hung silently for 37 to 116 minutes until one shared wait tool replaced them.
- **Launch settings are explicit and pinned in one place.** Briefs that left the model and effort implicit were fixed three times over. Each role's model and effort comes from one routing file, and a launch check compares them.
- **Formats that churn signal an unsettled design.** Brief, plan and decision-card formats changed repeatedly, and one trial lasted a day. 2.0 starts with one brief template and one home for plans, the parent issue.
- **Idle sessions and starting context are real costs.** Idle long sessions paid again and again to rebuild their cache. Sessions started at a median of 71k tokens against a 60k target. Leads sleep between wake-ups, and each role's starting context has a budget.
- **The board and thread layer is untested.** It was built in four days, with no measure of its use. 2.0 adds visibility one piece at a time, each with a stated measure (for example stale items per week).
- **1.0's daily summary note is the anti-pattern for the feed:** the same text every day, bare numbers, internal labels, counts instead of content, nothing stored, runs on weekends. The feed says what changed since yesterday, describes each item in words, gives each decision with a recommendation, and is stored where it can be linked.

## Agent identity and isolation

- A network identity belongs to a machine, not to a process: anything on a machine reaches what the machine can. And a pull request runs its own workflow file before anyone reviews it, so every CI job counts as hostile.
- The maintainer's own devices run no agents. Agents run on a separate host, as a standard user with their own credentials, none of the maintainer's keys, password manager or browser sign-ins.
- The network denies by default. Agents and runners reach only what their track needs, and never the maintainer's devices.
- Workflow files and deploy secrets are protected on the code host: owners and a ruleset for workflow files, deploy secrets only in environments limited to the main branch or gated by approval.

## Tracks and transition

Work is split into tracks by purpose, not by host: a track's context is what its agents need to know. Each track gets a lead and moves from 1.0 to this setup on its own, starting with a pilot track, gated on evidence that the new setup does better. 1.0 keeps running for every track that hasn't moved. The list of tracks and the schedule are kept privately.

## Open questions

1. Does a lead per track cost less than 1.0's coordination?
2. Which jobs go to Codex? To be settled by side-by-side runs and the 1.0 trials' results.
3. Where do docs and context live, and how does each role get its share?
4. What does the fence gate look like, if the maintainer is to actually use it?
5. How do agents hold secrets without the maintainer watching: one identity per track, vault scopes, rotation?
