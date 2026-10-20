#!/usr/bin/env python3
"""Log the app's start result after its start-session tools execute.

PostToolUse carries tool_response; PostToolUseFailure fires for execution
errors (including MCP error results), with top-level error and is_interrupt:
https://code.claude.com/docs/en/hooks#posttooluse-input
https://code.claude.com/docs/en/hooks#posttoolusefailure-input
Both carry session_id, cwd, tool_name and tool_input. Validation rejections
before execution do not fire PostToolUseFailure. This hook only appends to
launch-log.jsonl under AGENTIC_LOG_DIR (default ~/.claude/agentic-workflows);
it never prints a decision. Errors are logged without blocking the tool.
"""
import json
import os
import re
import sys
import time

TOOLS = {"mcp__ccd_session__start_session", "mcp__ccd_session__spawn_task"}
STARTED = re.compile(r'^Started session "[^"\n]*" \(session_id: ([A-Za-z0-9._-]+),')
PROPOSED = re.compile(r'\b(?:proposal_id|task_id)\s*[:=]\s*[A-Za-z0-9._-]+')


def response_parts(value):
    """Collect returned text, error flags and explicit proposal/task IDs."""
    texts, failed, proposed = [], False, False
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except ValueError:
            parsed = None
        if isinstance(parsed, (dict, list)):
            return response_parts(parsed)
        texts.append(value)
        proposed = bool(PROPOSED.search(value))
    elif isinstance(value, list):
        for item in value:
            t, f, p = response_parts(item)
            texts.extend(t)
            failed |= f
            proposed |= p
    elif isinstance(value, dict):
        failed = value.get("is_error") is True or value.get("isError") is True
        proposed = any(value.get(k) for k in ("proposal_id", "task_id", "proposalId", "taskId"))
        proposed |= any(isinstance(value.get(k), dict) and bool(value[k].get("id"))
                        for k in ("proposal", "task"))
        for key in ("text", "content", "structuredContent", "structured_content", "result"):
            if key in value:
                t, f, p = response_parts(value[key])
                texts.extend(t)
                failed |= f
                proposed |= p
    return texts, failed, proposed


def write_log(base, entry):
    os.makedirs(base, exist_ok=True)
    with open(os.path.join(base, "launch-log.jsonl"), "a") as f:
        f.write(json.dumps(entry, sort_keys=True) + "\n")


def log_error(base, data, error):
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "hook": "start-result", "result": "error", "error": str(error)}
    if isinstance(data, dict):
        entry.update(session=data.get("session_id"), cwd=data.get("cwd"),
                     tool=data.get("tool_name"))
    try:
        write_log(base, entry)
    except Exception as log_error:
        print("start-result: cannot write error to launch log: %s; %s" %
              (str(error).replace("\n", " "), str(log_error).replace("\n", " ")),
              file=sys.stderr)


def main():
    base = os.environ.get("AGENTIC_LOG_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude", "agentic-workflows")
    data = None
    try:
        data = json.load(sys.stdin)
        if data.get("tool_name") not in TOOLS:
            return 0
        texts, failed, proposed = response_parts(data.get("tool_response"))
        entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                 "session": data.get("session_id"), "cwd": data.get("cwd"),
                 "hook": "start-result", "tool": data.get("tool_name"), "result": "unknown"}
        failed |= data.get("hook_event_name") == "PostToolUseFailure" or data.get("is_error") is True
        if failed:
            entry.update(result="refused", refusal=str(data.get("error") or "\n".join(texts))[:200])
        else:
            match = next((m for t in texts if (m := STARTED.match(t))), None)
            if match:
                entry.update(result="started", started_session_id=match.group(1))
            elif proposed:
                entry["result"] = "proposed"
        write_log(base, entry)
    except Exception as error:
        log_error(base, data, error)
    return 0


if __name__ == "__main__":
    sys.exit(main())
