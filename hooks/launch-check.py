#!/usr/bin/env python3
"""PreToolUse hook for the Agent and Bash tools.

Agent: maps an "agentic-workflows:ROLE" subagent_type to a role in routing.json
and allows the launch only when the model is one routing.json allows for that
role. A launch without a model uses the one in the role's agent file, so it is
checked the same way; it is denied when that cannot be read or is not allowed.
The deny message names the primary route's model first. Other subagent types,
bare names included, are the user's or the project's own agents and pass.

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
    ("redirect", re.compile(r"(^|[^<>&0-9])>>?(?![>&])(?!\s*/dev/(?:null|stdout|stderr|tty|fd/[0-9]+)(\s|$|[;&|)]))")),
    ("tee", re.compile(START + r"tee(\s|$)")),
    ("sed -i", re.compile(START + r"sed\s+(\S+\s+)*?(-[a-zA-Z]*i|--in-place)")),
    ("mv", re.compile(START + r"mv(\s|$)")),
    ("cp", re.compile(START + r"cp(\s|$)")),
    ("rm", re.compile(START + r"rm(\s|$)")),
    ("mkdir", re.compile(START + r"mkdir(\s|$)")),
    ("touch", re.compile(START + r"touch(\s|$)")),
]


GIT = re.compile(START + r"git\s+(?:-[Cc]\s+\S+\s+|-\S+\s+)*([a-z][a-z-]*)(?:[ \t]+([^\s;&|]+))?")
GIT_WRITES = {"commit", "push", "apply", "add", "rm", "mv", "reset", "checkout", "switch", "merge",
              "rebase", "cherry-pick", "revert", "tag", "stash", "restore", "clean", "pull", "am"}


# Flags that put git tag in list mode; others (--sort, --format, -i) only
# modify a listing, so with a tag name they still create the tag.
TAG_LISTS = ("-l", "--list", "--contains", "--no-contains", "--points-at", "--merged",
             "--no-merged")


def git_writes(code):
    """True when a git command in CODE writes; tag listing forms and
    stash list/show only read."""
    for m in GIT.finditer(code):
        sub, arg = m.group(2), m.group(3)
        if sub not in GIT_WRITES:
            continue
        if sub == "tag":
            args = re.split(r"[;&|\n]", code[m.end(2):], maxsplit=1)[0].split()
            mutates = any(re.fullmatch(r"-[a-zA-Z]*[dfasum][a-zA-Z]*", a)
                          or a in ("--delete", "--force", "--annotate", "--sign", "--local-user", "--message", "--file")
                          or a.startswith(("--message=", "--file=", "--local-user=")) for a in args)
            lists = any(a in TAG_LISTS or a.startswith(tuple(f + "=" for f in TAG_LISTS))
                        or re.fullmatch(r"-n[0-9]*", a) for a in args) \
                or all(a.startswith("-") for a in args)
            if not mutates and (arg is None or lists):
                continue
        if sub == "stash" and arg in ("list", "show"):
            continue
        return True
    return False


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
        # primaries first, then fallbacks, each in routing.json order
        routes = [k.get("primary") for k in spec["kinds"].values()] + [k.get("fallback") for k in spec["kinds"].values()]
        return list(dict.fromkeys(r["model"] for r in routes if r and r.get("family") == "claude"))
    if spec.get("family") == "claude":
        return [spec["model"]]
    if isinstance(spec.get("claude"), dict):  # critical-reviewer
        return [spec["claude"]["model"]]
    return []


def model_ok(given, allowed):
    """An alias matches itself, or a full id that contains it as a word."""
    g = str(given).strip().lower()
    return any(g == a.lower() or a.lower() in re.split(r"[^a-z0-9.]+", g) for a in allowed)


def agent_file_value(role, field):
    """A scalar line of the plugin's agents/ROLE.md frontmatter, or None."""
    if not re.fullmatch(r"[a-z0-9-]+", role):
        return None
    try:
        with open(os.path.join(plugin_root(), "agents", role + ".md")) as f:
            text = f.read()
    except OSError:
        return None
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    mm = re.search(r"^" + re.escape(field) + r":\s*(\S+)\s*$", m.group(1), re.M) if m else None
    return mm.group(1) if mm else None


def check_agent(data, entry):
    ti = data.get("tool_input") or {}
    st = str(ti.get("subagent_type") or "")
    role = st[len(PREFIX):] if st.startswith(PREFIX) else ""
    model = ti.get("model")
    effort = ti.get("effort")
    effort_from = "input" if effort is not None else None
    if effort is None and role:
        effort = agent_file_value(role, "effort")
        effort_from = "agent file" if effort is not None else None
    entry.update(role=role or None, model=model, effort=effort, effort_from=effort_from)
    if role == "implementer":
        match = re.match(r"^\s*(trivial|specified|symptom-bug|native-mobile)\s*:",
                         str(ti.get("description") or ""), re.I)
        entry["kind"] = match.group(1).lower() if match else None
    with open(os.path.join(plugin_root(), "routing.json")) as f:
        roles = json.load(f).get("roles", {})
    spec = roles.get(role)
    allowed = claude_models(spec) if isinstance(spec, dict) and role != "lead" else []
    if not allowed:
        entry["decision"] = "pass"
        return None
    effective = model or agent_file_value(role, "model")
    if role == "implementer" and entry.get("kind"):
        kind_spec = spec.get("kinds", {}).get(entry["kind"], {})
        routes = [kind_spec.get("primary"), kind_spec.get("fallback")]
        entry["route_ok"] = bool(effective and model_ok(effective, [r["model"] for r in routes
                                              if r and r.get("family") == "claude"]))
    if effective and model_ok(effective, allowed):
        entry["decision"] = "allow"
        if not model:
            entry["model"] = effective
            entry["model_from"] = "agent file"
        return None
    entry["decision"] = "deny"
    reason = ("routing.json runs the %s role on %s (docs/routing.md); this launch %s. "
              "Set model to %s on the Agent call."
              % (role, " or ".join(allowed), "names model %s" % model if model else "names no model", allowed[0]))
    entry["reason"] = reason
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


RETRO = re.compile(r"(>>?|mkdir\s+(-\S+\s+)*)\s*[\"']?\$\{?AGENTIC_RETRO_NOTES\}?[^\s;&|]*[\"']?")
HEREDOC = re.compile(r"(?P<head>[^\n]*?<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*)\n(?P<body>.*?)\n[ \t]*\3[ \t]*(?:\n|$)", re.S)
SHELL_HEREDOC = re.compile(r"(?:^|[;&|(\n])[ \t]*" + r"(?:sh|bash|zsh|dash)(?:[ \t]+-[^\s<]+)*[ \t]*<<")
# A quoted string, but the one after sh/bash/zsh -c is a command and is kept.
QUOTED = re.compile(
    r"(?P<keep>(?:^|[\s;&|(])(?:ba|z)?sh\s+(?:-\S+\s+)*-c\s+)(?P<cmd>\"(?:\\.|[^\"\\])*\"|'[^']*')"
    r"|\"(?:\\.|[^\"\\])*\"|'[^']*'", re.S)


def _retro(m):
    return m.group(0) if ".." in m.group(0) else " "


def _quoted(m):
    if m.group("cmd"):
        return m.group("keep") + " " + m.group("cmd")[1:-1]
    return '""'


def code_of(cmd):
    """The command without data heredoc bodies, the retro-note skill's own writes
    (into $AGENTIC_RETRO_NOTES, never with ..) and quoted text, which is not a
    command, except the argument of sh -c."""
    cmd = HEREDOC.sub(lambda m: m.group("head") + "\n" +
                      (code_of(m.group("body")) + "\n" if SHELL_HEREDOC.search(m.group("head")) else ""), cmd)
    return QUOTED.sub(_quoted, RETRO.sub(_retro, cmd))


def check_bash(data, entry):
    cwd = data.get("cwd") or ""
    if not (os.path.isfile(os.path.join(cwd, "track.md")) and os.path.isfile(os.path.join(cwd, "CLAUDE.md"))):
        return False
    cmd = str((data.get("tool_input") or {}).get("command") or "")
    code = code_of(cmd)
    kinds = [name for name, rx in WRITE_PATTERNS if rx.search(code)]
    if git_writes(code):
        kinds.append("git write")
    if not kinds:
        return False
    entry.update(role="lead", decision="lead-write", detail=kinds)
    return True


def main():
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "session": None, "cwd": None, "role": None, "model": None, "effort": None, "effort_from": None, "decision": "error"}
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
