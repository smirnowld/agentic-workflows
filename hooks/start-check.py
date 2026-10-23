#!/usr/bin/env python3
"""PreToolUse hook for the app's start-session tools.

Matched tools: mcp__ccd_session__start_session and the older
mcp__ccd_session__spawn_task. A lead cannot start new work while too many
items wait on the maintainer: the hook counts open issues assigned to the
maintainer that block at least one open issue that is started work (GitHub's
"blocked by" dependencies; started: its board Status is one of the config's
"started" list), and open pull requests with a review requested from them that
a bot did not author (drafts included), across the track's repositories,
archived repositories left out, each URL counted once. It denies the start when the count reaches the cap. A start passes when
the header of its prompt (the lines before the first "## " heading, or
the whole prompt without one; nothing else is scanned) has a line "Priority:
fire" in the brief template's form "**Priority:** fire". A leading "- ", "* "
or "> ", bold around the label or the value, and a trailing HTML comment are
accepted too. The value must be exactly "fire": a template placeholder such as
"P1 | P2 | fire" does not pass.

Config, per track: $AGENTIC_CONFIG if set, else
$CLAUDE_PROJECT_DIR/.claude/agentic-workflows.json (the hook input's cwd when
CLAUDE_PROJECT_DIR is unset). The lead's config lives in
TRACK/lead/.claude/agentic-workflows.json. No file: not-configured, the start passes.
  {"waiting": {"cap": 5, "maintainer": "LOGIN", "repos": ["OWNER/REPO"],
   "started": ["In progress", "In review", "Waiting"]}}   ("started" optional)

Every decision (allow, deny, fire, not-configured, error) is appended as one
JSON line to ${AGENTIC_LOG_DIR:-$HOME/.claude/agentic-workflows}/launch-log.jsonl,
the file hooks/launch-check.py writes. The hook never fails closed on its own
errors: a missing or bad config, or a failing gh, allows the start.
AGENTIC_START_TIMEOUT (seconds, default 15) sets the total time for the gh
GitHub searches; the tests set it short.

Hook input and output: https://code.claude.com/docs/en/hooks (PreToolUse input
carries session_id, cwd, tool_name, tool_input; a deny prints
hookSpecificOutput.permissionDecision "deny" with permissionDecisionReason).
MCP tools are matched by the name mcp__<server>__<tool> on the same page.
"""
import json
import os
import re
import subprocess
import sys
import time

FIRE = re.compile(r"^[ \t]*(?:[-*>][ \t]+)?(?:\*\*)?Priority:(?:\*\*)?[ \t]*(?:\*\*)?fire(?:\*\*)?[ \t]*(?:<!--.*?-->)?[ \t]*\r?$", re.I | re.M)
STARTED = ["In progress", "In review", "Waiting"]
REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHOWN = 5
PAGE = 20
MAX_PAGES = 5
MAX_CAP = PAGE * MAX_PAGES  # the search limit: a higher cap could never be reached


def header(prompt):
    """The brief's header: the lines before the first "## " heading."""
    return re.split(r"^##[ \t]", prompt, maxsplit=1, flags=re.M)[0]


def timeout():
    try:
        return float(os.environ.get("AGENTIC_START_TIMEOUT") or 15)
    except ValueError:
        return 15.0


class NotConfigured(Exception):
    pass


def log_path():
    base = os.environ.get("AGENTIC_LOG_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude", "agentic-workflows")
    return os.path.join(base, "launch-log.jsonl")


def write_log(entry):
    try:
        path = log_path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a") as f:
            f.write(json.dumps(entry, sort_keys=True) + "\n")
    except Exception as e:  # a log that cannot be written is said, not hidden
        print("start-check: cannot write the launch log: %s" % e, file=sys.stderr)


def config_path(cwd):
    if os.environ.get("AGENTIC_CONFIG"):
        return os.environ["AGENTIC_CONFIG"]
    project = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
    if not isinstance(project, str) or not project:
        raise NotConfigured()
    return os.path.join(project, ".claude", "agentic-workflows.json")


def load_config(cwd):
    """(cap, maintainer, repos, started) from the config file; NotConfigured when the
    file is absent, ValueError when it is unusable."""
    try:
        with open(config_path(cwd)) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        raise NotConfigured()
    w = cfg.get("waiting") if isinstance(cfg, dict) else None
    if not isinstance(w, dict):
        raise NotConfigured()
    cap, who, repos = w.get("cap"), w.get("maintainer"), w.get("repos")
    if (not isinstance(cap, int) or isinstance(cap, bool) or cap < 1 or cap > MAX_CAP or not isinstance(who, str) or not who
            or not isinstance(repos, list) or not repos or not all(isinstance(r, str) and REPO.match(r) for r in repos)):
        raise ValueError("waiting needs an integer cap from 1 to 100, a maintainer and a list of OWNER/REPO repos")
    started = w.get("started", STARTED)
    if not isinstance(started, list) or not all(isinstance(x, str) and x for x in started):
        raise ValueError("started must be a list of board Status names")
    return cap, who, repos, started


ISSUE_FIELDS = ("... on Issue { url blocking(first: 20) { nodes { state "
                "projectItems(first: 5) { nodes { fieldValueByName(name: \"Status\") "
                "{ ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } }")
PR_FIELDS = "... on PullRequest { url author { __typename login } }"
QUERY = ("query($q: String!, $after: String) { search(type: ISSUE, first: " + str(PAGE) + ", query: $q, after: $after) "
         "{ pageInfo { hasNextPage endCursor } nodes { %s } } }")


def search(terms, fields, deadline, notes):
    """Nodes of one GraphQL search, following pages while the deadline allows;
    notes gets "truncated" when MAX_PAGES ends it with more pages left."""
    nodes, after = [], None
    for page in range(MAX_PAGES):
        cmd = ["gh", "api", "graphql", "-f", "query=" + QUERY % fields, "-f", "q=" + terms]
        if after:
            cmd += ["-f", "after=" + after]
        left = deadline - time.monotonic()
        if left <= 0:
            raise TimeoutError("gh search took too long")
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=left)
        if r.returncode != 0:
            raise RuntimeError("gh search failed: %s" % r.stderr.strip()[:200])
        body = json.loads(r.stdout)
        if body.get("errors"):
            raise RuntimeError("gh search returned errors: %s" % str(body["errors"])[:200])
        res = body["data"]["search"]
        nodes += [n for n in res["nodes"] if n]
        if not res["pageInfo"]["hasNextPage"]:
            break
        if page == MAX_PAGES - 1:
            notes.append("truncated")
            break
        after = res["pageInfo"]["endCursor"]
    return nodes


def is_bot(author):
    if not author:
        return False
    return author.get("__typename") == "Bot" or str(author.get("login") or "").endswith("[bot]")


def is_started(issue, wanted):
    """An open blocked issue whose Status on some board is a started one. A
    missing projectItems (no project scope) raises, so the start fails open."""
    if not issue or issue.get("state") != "OPEN":
        return False
    for item in issue["projectItems"]["nodes"]:
        value = (item or {}).get("fieldValueByName") or {}
        if str(value.get("name") or "").lower() in wanted:
            return True
    return False


def waiting(who, repos, started, notes):
    """URLs of the open items waiting on the maintainer, each once: issues
    assigned to them that block at least one open issue, and pull requests
    that request their review, not authored by a bot. (GitHub's is:blocking
    qualifier does not filter, so blocking is read from each issue.) Several
    repo: qualifiers in one query are ORed."""
    wanted = {x.lower() for x in started}
    deadline = time.monotonic() + timeout()
    base = "is:open archived:false " + " ".join("repo:" + r for r in repos)
    urls = []
    for n in search("is:issue assignee:%s %s" % (who, base), ISSUE_FIELDS, deadline, notes):
        if any(is_started(b, wanted) for b in n["blocking"]["nodes"]):
            urls.append(n["url"])
    for n in search("is:pr review-requested:%s %s" % (who, base), PR_FIELDS, deadline, notes):
        if not is_bot(n.get("author")):
            urls.append(n["url"])
    return list(dict.fromkeys(urls))


def deny_reason(count, cap, urls):
    shown = "\n".join("- " + u for u in urls[:SHOWN])
    more = "\n(and %d more)" % (len(urls) - SHOWN) if len(urls) > SHOWN else ""
    return ("%d items waiting on the maintainer (cap %d), so no new work starts. Waiting:\n%s%s\n"
            "Instead: finish work in flight that is not blocked; put the new request on the board "
            "for later. The cap lifts when the maintainer clears items. "
            "Only a start whose brief header has the line \"**Priority:** fire\" passes."
            % (count, cap, shown, more))


def main():
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "session": None, "cwd": None, "role": None, "model": None, "model_from": "inherited",
             "effort": None, "effort_from": "inherited", "decision": "error"}
    out = None
    try:
        data = json.load(sys.stdin)
        entry.update(session=data.get("session_id"), cwd=data.get("cwd"), tool=data.get("tool_name"))
        ti = data.get("tool_input")
        ti = ti if isinstance(ti, dict) else {}
        prompt = str(ti.get("prompt") or "")
        for field in ("model", "effort"):
            entry[field] = ti.get(field)
            entry[field + "_from"] = "input" if ti.get(field) is not None else "inherited"
        try:
            cap, who, repos, started = load_config(data.get("cwd"))
        except NotConfigured:
            entry["decision"] = "not-configured"
        else:
            root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            with open(os.path.join(root, "routing.json")) as f:
                route = json.load(f)["roles"]["coordinator"]
            model = entry["model"]
            model_matches = model is None or str(model).lower() == route["model"].lower() or route["model"].lower() in re.split(r"[^a-z0-9.]+", str(model).lower())
            if not model_matches or (entry["effort"] is not None and str(entry["effort"]).lower() != str(route["effort"]).lower()):
                entry["decision"] = "deny"
                reason = "routing.json runs the coordinator on %s with effort %s (docs/routing.md). Set model and effort to that route." % (route["model"], route["effort"])
                entry["reason"] = reason
                out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}
            elif FIRE.search(header(prompt)):
                entry["decision"] = "fire"
            else:
                notes = []
                urls = waiting(who, repos, started, notes)
                if notes:
                    entry["note"] = notes[0]
                entry.update(count=len(urls), cap=cap)
                if len(urls) >= cap:
                    entry["decision"] = "deny"
                    reason = deny_reason(len(urls), cap, urls)
                    entry["reason"] = reason
                    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                  "permissionDecision": "deny",
                                                  "permissionDecisionReason": reason}}
                else:
                    entry["decision"] = "allow"
    except Exception as e:
        entry["decision"] = "error"
        entry["error"] = "%s: %s" % (type(e).__name__, e)
        print("start-check: error, allowing: %s" % entry["error"], file=sys.stderr)
        out = None
    write_log(entry)
    if out:
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
