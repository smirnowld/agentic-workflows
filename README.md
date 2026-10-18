# agentic-workflows

How I run my projects with agents. I set the direction: what to build, for whom, and how good it has to be. Agents do the rest (planning, building, testing, review, operations), within limits that mechanisms enforce rather than rules they're asked to remember.

The tools are named rather than abstracted: Claude in the Claude desktop app is where I work, and OpenAI's Codex takes the jobs where it measures better.

## Principles

- **I direct rather than approve.** A gate that is routinely rubber-stamped is removed or replaced by a mechanism. Pretend control costs attention and protects nothing.
- **Mechanisms over remembered rules.** What matters is enforced: hooks, checks, rulesets, admission policies, tool restrictions, scoped identities. Everything else is short guidance.
- **Status is computed, not maintained.** Progress comes from pull requests, issues, sessions, CI and deployments. Only intent is written by hand.
- **Each agent gets the context its job needs, and no more.**
- **Opinionated.** It names the actual tools, with one way to do each thing.
- **Agents act on their own, secrets and commands included,** within scoped identities and an audit trail rather than under my watch.

Not goals: provider neutrality, cloud sessions (every token must be visible), more than one user.

## How it's layered

1. **Intent.** Vision, users, roadmap, the quality and design bar, and each track's delegation table ([docs/delegation.md](docs/delegation.md)). I decide; AI writes it down and keeps it consistent.
2. **Management.** One lead per track ([docs/lead.md](docs/lead.md)). It turns intent into work, decides tactics within its delegated authority and brings me only what the table says to. It has no checkout to edit and keeps its state on the board.
3. **Execution.** Roles: implementers, testers who use the product, and reviewers. Each runs on the model that measured best for it ([docs/routing.md](docs/routing.md)) and gets only its own context.
4. **Controls.** A merge is the deploy. Rulesets, admission policies and RBAC; scoped identities, with secrets agents use but never see; budgets, an audit log, rollback.
5. **Visibility.** The Today page ([docs/today.md](docs/today.md)): what needs me, what finished, what is stuck.
6. **Learning.** Notes captured mid-session with the `retro-note` skill, and a scheduled retro that reads them with the sessions and measures and proposes concrete changes. The retro is the one place the process changes.

## Measures

| Measure | Direction |
|---|---|
| My actions that are mechanical: copied commands, rubber-stamped merges, reading tactical detail | near zero |
| Share of my decisions that are about direction | most of them |
| Outcomes shipped per week, by track | up |
| Tokens per shipped outcome, within the subscription budgets | down |
| Reverts, escaped defects, incidents | not up |
| Updates I understand cold, without opening anything | nearly all |

How many sessions I touch is not a measure.

## What's here

- [RULES.md](RULES.md): the rules every session starts with.
- [AGENTS.md](AGENTS.md): the rules for changing this repository.
- [docs/delegation.md](docs/delegation.md): who decides what, how a track's delegation table is written, and how agents are isolated.
- [docs/lead.md](docs/lead.md): the lead, the sessions it starts, and its track folder.
- [docs/routing.md](docs/routing.md) and [routing.json](routing.json): which model each role runs on, and why.
- [docs/today.md](docs/today.md): the Today page.
- [templates/](templates/): the brief and the track folder.
- The Claude Code plugin ([.claude-plugin/](.claude-plugin/)): the roles, skills, hooks and helpers that bring all of this into a session.

## Using it

1. Add this repository as a plugin marketplace in Claude Code and install the `agentic-workflows` plugin for the project, not for your whole account, so sessions in other projects don't get these rules. Enable it in each project's `.claude/settings.json` (`enabledPlugins`); the track folder template already does.
2. In each project, point `AGENTS.md` at [RULES.md](RULES.md) and add the project's own delegation table and rules.
3. Make a track folder from [templates/track/](templates/track/) and start a session in it: that session is the track's lead.
