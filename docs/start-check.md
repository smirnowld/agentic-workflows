# Start check

A lead can't start new work while too many items wait on the maintainer. The hook [hooks/start-check.py](../hooks/start-check.py) runs before the app's start-session tools (`mcp__ccd_session__start_session` and the older `mcp__ccd_session__spawn_task`) and counts what waits. In a track with a start-check config, it first checks the coordinator route in [routing.json](../routing.json): a supplied model must match the route’s alias or a model ID containing it as a word, and a supplied effort must match the route. A mismatch is denied with the required model and effort, including for a fire. Omitted values inherit from the starter and pass the route check.

## What it counts

The cap applies per track: only the repositories listed in the track's config count. Two kinds of open item wait on the maintainer, each item once; archived repositories don't count.

- Steps that hold up started work: an issue assigned to the maintainer that blocks, through GitHub's issue dependencies ("blocked by"), at least one open issue whose Status on a board is started: "In progress", "In review" or "Waiting" by default, matched without regard to case. An issue assigned to them that blocks nothing doesn't count. Neither does one whose blocked issues are all closed, on no board, or in a status such as Backlog, Ready or Planned.
- A pull request (itself started work) that requests the maintainer's review (drafts included), unless a bot wrote it. Dependabot and other bot authors are left out; any human author counts.

The hook reads the board field named Status; on a board whose status field has another name nothing reads as started, so no step there counts. For each step it reads up to 20 blocked issues, and for each blocked issue up to 5 boards.

The hook asks GitHub's GraphQL API through `gh`, which needs the `project` scope to read board statuses; without it the search fails and the start goes ahead (logged as `error`). It makes one issue search (with the blocked issues' board statuses) and one pull request search over all the track's repositories, each followed page by page (up to five pages of 20). All the calls share one time budget of 15 seconds; `AGENTIC_START_TIMEOUT` (seconds) changes it. If a search still has more pages after the fifth, the hook counts what it has and notes `truncated` in the log line.

- Under the cap: the start goes ahead.
- At or over the cap: the start is denied. The cap blocks when the count is at or above it.
- A start whose brief header has the line `**Priority:** fire` goes ahead after the coordinator route check. The header is the part of the prompt before its first `## ` heading (the whole prompt if it has none); a fire line under a later heading doesn't count. The value must be exactly `fire`, so a template placeholder such as `P1 | P2 | fire` doesn't pass; an HTML comment may follow it. Also accepted: `**Priority: fire**`, `Priority: fire`, a leading `- `, `* ` or `> `, Windows line endings, and any case.
- No config (a session outside a track), a bad config, or `gh` failing or timing out: the start goes ahead, like the launch check, so a broken check never blocks a fire.

Each decision (`allow`, `deny`, `fire`, `not-configured`, `rules-late`, `error`) is one line in the launch log, `launch-log.jsonl` in `${AGENTIC_LOG_DIR:-$HOME/.claude/agentic-workflows}`, with the count and cap when they were read. Each start line records `model` and `effort` (null when omitted), and `model_from` and `effort_from` as `input` or `inherited`.

Agent launch lines record explicit `effort`, with `effort_from` as `input` or null. Omitted or mismatched effort is denied. Implementer lines record `kind` from a leading kind and colon in the Agent description, or null; a supplied kind records `route_ok` and selects the Claude routes whose model and effort are allowed. Codex `finished` lines record `input_tokens`, `cached_input_tokens` and `output_tokens` from completed-turn usage events, or null when unreadable.

The start check logs its own decision before the app acts. After the app acts, [hooks/start-result.py](../hooks/start-result.py) logs a `start-result` line with `result` set to `started`, `proposed`, `refused`, `unknown` or `error`, the started session ID when present, and the first 200 characters of a refusal. Count real starts from those `start-result` lines whose `result` is `started`. Calls rejected before execution do not fire the result hook. Hook errors log `result: error` with the error text; if the log cannot be written, the hook prints a one-line note to stderr. It always exits successfully and makes no permission decision.

## The config file

Per track: `.claude/agentic-workflows.json` in the track's project directory (`$CLAUDE_PROJECT_DIR`, or the working directory the hook is given when that is unset). `AGENTIC_CONFIG`, when set, names a file to use instead. The track template ships a starting copy, [templates/track/.claude/agentic-workflows.json](../templates/track/.claude/agentic-workflows.json); replace `LOGIN` and `OWNER/REPO` in the copy. The track folder is not a repository, so the real login stays in the local copy; the plugin's template holds placeholders only.

```json
{"waiting": {"cap": 5, "maintainer": "LOGIN", "repos": ["OWNER/REPO"],
  "started": ["In progress", "In review", "Waiting"]}}
```

- `cap`: the number of waiting items at which new starts stop, from 1 to 100.
- `maintainer`: the login whose blocking issues and requested reviews count.
- `repos`: the track's repositories, each as `OWNER/REPO`.
- `started`: optional; the board Status names that make a blocked issue started work. Matched without regard to case; the list shown is the default when the key is missing.

## What the maintainer sees

Nothing while under the cap. At the cap, the lead gets a refusal that says how many items are waiting on the maintainer, lists up to five URLs, and what to do instead: finish work in flight that isn't blocked, and put the new request on the board for later. Clearing an item (closing it, unlinking it from what it blocks, unassigning it, or merging the pull request) lifts the cap; no other step is needed.

## Rules check

[hooks/rules-check.py](../hooks/rules-check.py) runs before every tool call. SessionStart records that it ran by calling the hook with `--mark`, which creates a session marker under `rules-loaded/` beside the launch log. An existing marker is left alone. Without a marker, the check reads the plugin's rules, creates the marker exclusively and supplies the rules as tool context. `CLAUDE_PLUGIN_ROOT` names the plugin root; when unset, the hook uses its own location.

The check logs `rules-late` when it supplies rules. An error logs `error` with the error text; if the log cannot be written, the hook prints a one-line note to stderr. Rules context is printed before logging so a log failure cannot prevent delivery. The check always exits successfully and makes no permission decision.

The marker records that the SessionStart hook ran. If the app ran that hook but dropped its output, the check cannot tell.
