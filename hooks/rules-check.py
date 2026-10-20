#!/usr/bin/env python3
"""Supply rules on the first tool call when SessionStart did not supply them.

SessionStart uses --mark with its stdin to record delivery without output.
PreToolUse returns hookSpecificOutput.additionalContext, with no permission
decision, so the tool proceeds. See the input and context schemas:
https://code.claude.com/docs/en/hooks#pretooluse
https://code.claude.com/docs/en/hooks#add-context-for-claude
Markers and launch-log.jsonl live under AGENTIC_LOG_DIR, or
~/.claude/agentic-workflows. Errors are logged without a permission decision.
"""
import json
import os
import re
import sys
import time


def write_log(base, entry):
    os.makedirs(base, exist_ok=True)
    with open(os.path.join(base, "launch-log.jsonl"), "a") as f:
        f.write(json.dumps(entry, sort_keys=True) + "\n")


def log_error(base, data, error):
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "hook": "rules-check", "decision": "error", "error": str(error)}
    if isinstance(data, dict):
        entry.update(session=data.get("session_id"), cwd=data.get("cwd"),
                     tool=data.get("tool_name"))
    try:
        write_log(base, entry)
    except Exception as log_error:
        print("rules-check: cannot write error to launch log: %s; %s" %
              (str(error).replace("\n", " "), str(log_error).replace("\n", " ")),
              file=sys.stderr)


def main():
    base = os.environ.get("AGENTIC_LOG_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude", "agentic-workflows")
    data = None
    try:
        data = json.load(sys.stdin)
        session = data.get("session_id")
        if not isinstance(session, str) or not session:
            return 0
        name = re.sub(r"[^A-Za-z0-9._-]", "_", session)
        if name in (".", ".."):
            name = "_" + name
        marker = os.path.join(base, "rules-loaded", name)
        if os.path.exists(marker) and sys.argv[1:] != ["--mark"]:
            return 0
        root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
            os.path.dirname(os.path.abspath(__file__)))
        marking = sys.argv[1:] == ["--mark"]
        if not marking:
            with open(os.path.join(root, "RULES.md")) as f:
                context = "Plugin root for routing.json, docs and helpers: %s\n%s" % (root, f.read())
        os.makedirs(os.path.dirname(marker), exist_ok=True)
        # Exclusive creation also keeps concurrent first calls from logging twice.
        try:
            with open(marker, "x"):
                pass
        except FileExistsError:
            return 0
        if marking:
            return 0
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                "additionalContext": context}}))
        entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                 "session": session, "cwd": data.get("cwd"), "hook": "rules-check",
                 "decision": "rules-late", "tool": data.get("tool_name")}
        try:
            write_log(base, entry)
        except Exception as error:
            log_error(base, data, error)
    except Exception as error:
        log_error(base, data, error)
    return 0


if __name__ == "__main__":
    sys.exit(main())
