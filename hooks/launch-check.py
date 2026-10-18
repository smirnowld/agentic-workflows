#!/usr/bin/env python3
"""PreToolUse hook for the Agent and Bash tools.

Agent: maps subagent_type (with or without the "agentic-workflows:" prefix) to
a role in routing.json and allows the launch only when tool_input.model is one
routing.json allows for that role. A launch of a routed role without a model,
or with another one, is denied with a message naming the expected model.
Unrouted subagent types pass.

Bash: in a lead's track folder (cwd holds both track.md and CLAUDE.md), a
command that writes is logged, never blocked.

Every Agent decision (allow, deny, pass) and every lead write is appended as
one JSON line to ${AGENTIC_LOG_DIR:-$HOME/.claude/agentic-workflows}/launch-log.jsonl.
The hook never fails closed on its own errors: any exception allows the call
and is logged as decision "error".

Hook input and output: https://code.claude.com/docs/en/hooks (PreToolUse input
carries session_id, cwd, tool_name, tool_input; a deny prints
hookSpecificOutput.permissionDecision "deny" with permissionDecisionReason).
"""
import json
import os
import re
import sys
import time

PREFIX = "agentic-workflows:"
START = r"(^|[\s;&|(])"

# Command shapes that write, for the lead's folder.
WRITE_PATTERNS = [
    ("redirect", re.compile(r"(^|[^<>&0-9])>>?(?!&)")),
    ("tee", re.compile(START + r"tee(\s|$)")),
    ("sed -i", re.compile(START + r"sed\s+(-\S+\s+)*-[a-zA-Z]*i")),
    ("mv", re.compile(START + r"mv(\s|$)")),
    ("cp", re.compile(START + r"cp(\s|$)")),
    ("rm", re.compile(START + r"rm(\s|$)")),
    ("mkdir", re.compile(START + r"mkdir(\s|$)")),
    ("touch", re.compile(START + r"touch(\s|$)")),
    ("git write", re.compile(START + r"git\s+(-\S+\s+)*(commit|push|apply)(\s|$)")),
]


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
        print("launch-check: cannot write the launch log: %s" % e, file=sys.stderr)


def plugin_root():
    return os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))


def claude_models(spec):
    """Models the Agent tool may run this role on, from routing.json."""
    if "kinds" in spec:  # implementer: any kind's primary or fallback
        routes = [r for k in spec["kinds"].values() for r in (k.get("primary"), k.get("fallback"))]
        return sorted({r["model"] for r in routes if r and r.get("family") == "claude"})
    if spec.get("family") == "claude":
        return [spec["model"]]
    if isinstance(spec.get("claude"), dict):  # critical-reviewer
        return [spec["claude"]["model"]]
    return []


def model_ok(given, allowed):
    """An alias matches itself, or a full id that contains it as a word."""
    g = str(given).strip().lower()
    return any(g == a.lower() or a.lower() in re.split(r"[^a-z0-9.]+", g) for a in allowed)


def check_agent(data, entry):
    ti = data.get("tool_input") or {}
    st = str(ti.get("subagent_type") or "")
    role = st[len(PREFIX):] if st.startswith(PREFIX) else st
    model = ti.get("model")
    entry.update(role=role or None, model=model)
    with open(os.path.join(plugin_root(), "routing.json")) as f:
        roles = json.load(f).get("roles", {})
    spec = roles.get(role)
    allowed = claude_models(spec) if isinstance(spec, dict) and role != "lead" else []
    if not allowed:
        entry["decision"] = "pass"
        return None
    if model and model_ok(model, allowed):
        entry["decision"] = "allow"
        return None
    entry["decision"] = "deny"
    reason = ("routing.json runs the %s role on %s (docs/routing.md); this launch %s. "
              "Set model to %s on the Agent call."
              % (role, " or ".join(allowed), "names model %s" % model if model else "names no model", allowed[0]))
    entry["reason"] = reason
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


def check_bash(data, entry):
    cwd = data.get("cwd") or ""
    if not (os.path.isfile(os.path.join(cwd, "track.md")) and os.path.isfile(os.path.join(cwd, "CLAUDE.md"))):
        return False
    cmd = str((data.get("tool_input") or {}).get("command") or "")
    kinds = [name for name, rx in WRITE_PATTERNS if rx.search(cmd)]
    if not kinds:
        return False
    entry.update(role="lead", decision="lead-write", detail=kinds)
    return True


def main():
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "session": None, "cwd": None, "role": None, "model": None, "decision": "error"}
    out = None
    try:
        data = json.load(sys.stdin)
        entry.update(session=data.get("session_id"), cwd=data.get("cwd"), tool=data.get("tool_name"))
        tool = data.get("tool_name")
        if tool == "Agent":
            out = check_agent(data, entry)
        elif tool == "Bash":
            if not check_bash(data, entry):
                return 0  # not a lead write: nothing to log
        else:
            return 0
    except Exception as e:
        entry["decision"] = "error"
        entry["error"] = "%s: %s" % (type(e).__name__, e)
        print("launch-check: error, allowing: %s" % entry["error"], file=sys.stderr)
        out = None
    write_log(entry)
    if out:
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
