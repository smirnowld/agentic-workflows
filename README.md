# agentic-workflows

How I run my projects with agents. I set the direction: what to build, for whom, and how good it has to be. Agents do the rest (planning, building, testing, review, operations), within limits that mechanisms enforce rather than rules they're asked to remember.

This is the second version of the setup. It's being built now, one track of work at a time, starting with a pilot.

The tools are named rather than abstracted: Claude in the Claude desktop app is where I work, and OpenAI's Codex takes the jobs where it measures better. Project details, hosts, costs and trial logs stay private.

## What's here

- [CHARTER.md](CHARTER.md): what the setup is for, how it's layered, who decides what, and the lessons carried over from the first version.
- [RULES.md](RULES.md): the rules every session starts with.
- [docs/delegation.md](docs/delegation.md): how a track's delegation table is written, and the patterns that make it work.
- [docs/lead.md](docs/lead.md): the lead, the sessions it starts, and its track folder.
- [docs/routing.md](docs/routing.md) and [routing.json](routing.json): which model each role runs on, and why.
- [docs/today.md](docs/today.md): the Today page, the maintainer's feed and inbox.
- [templates/](templates/): the brief and the track folder.
- The Claude Code plugin ([.claude-plugin/](.claude-plugin/)): the roles, skills, hooks and helpers that bring all of this into a session.

## Using it

1. Add this repository as a plugin marketplace in Claude Code and install the `agentic-workflows` plugin.
2. In each project, point `AGENTS.md` at [RULES.md](RULES.md) and add the project's own delegation table and rules.
3. Make a track folder from [templates/track/](templates/track/) and start a session in it: that session is the track's lead.
