#!/usr/bin/env python3
"""PreToolUse hook for Agent, Bash, Edit, Write, MultiEdit, Read, Grep and Glob.

Agent: maps an "agentic-workflows:ROLE" subagent_type to a role in routing.json
and allows the launch only when the model is one routing.json allows for that
role. A launch without a model uses the one in the role's agent file, so it is
checked the same way; it is denied when that cannot be read or is not allowed.
Effort must be explicit and match a Claude route for the model, preferring the given kind.
The deny message names the primary route's model first. Other subagent types,
bare names included, are the user's or the project's own agents and pass.

Edit/Write/MultiEdit/Bash: coordinator edits are logged; Read/Grep/Glob and
read-only Bash calls increment the session read count in sessions/SESSION_ID.
Bash: in a lead's track folder (cwd holds both track.md and CLAUDE.md), a
command that writes is logged, never blocked. The same applies with role pm
in TRACK/pm/, which holds CLAUDE.md and whose parent holds track.md.

Every Agent decision (allow, deny, pass), coordinator edit and lead write is appended as
one JSON line to ${AGENTIC_LOG_DIR:-$HOME/.claude/agentic-workflows}/launch-log.jsonl.
The hook never fails closed on its own errors: any exception allows the call
and is logged as decision "error".

Hook input and output: https://code.claude.com/docs/en/hooks (PreToolUse input
carries session_id, cwd, tool_name, tool_input; a deny prints
hookSpecificOutput.permissionDecision "deny" with permissionDecisionReason).
"""
import fcntl
import json
import os
import re
import shlex
import subprocess
import tempfile
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
    entry.update(role=role or None, model=model, effort=effort, effort_from=effort_from)
    if role == "implementer":
        match = re.match(r"^\s*(trivial|specified|symptom-bug|native-mobile)\s*:",
                         str(ti.get("description") or ""), re.I)
        entry["kind"] = match.group(1).lower() if match else None
    with open(os.path.join(plugin_root(), "routing.json")) as f:
        roles = json.load(f).get("roles", {})
    spec = roles.get(role)
    allowed = claude_models(spec) if isinstance(spec, dict) and role not in ("lead", "pm") else []
    if not allowed:
        entry["decision"] = "pass"
        return None
    effective = model or agent_file_value(role, "model")
    if role == "implementer" and entry.get("kind"):
        kind_spec = spec.get("kinds", {}).get(entry["kind"], {})
        routes = [kind_spec.get("primary"), kind_spec.get("fallback")]
        entry["route_ok"] = bool(effective and model_ok(effective, [r["model"] for r in routes
                                              if r and r.get("family") == "claude"]))
    routes = ([r for k in spec["kinds"].values() for r in (k.get("primary"), k.get("fallback"))
               if r and r.get("family") == "claude"] if "kinds" in spec else
              [spec if spec.get("family") == "claude" else spec["claude"]])
    if role == "implementer" and entry.get("kind"):
        kind_spec = spec["kinds"][entry["kind"]]
        kind_routes = [r for r in (kind_spec.get("primary"), kind_spec.get("fallback"))
                       if r and r.get("family") == "claude"]
        if any(effective and model_ok(effective, [r["model"]]) for r in kind_routes):
            routes = kind_routes
    efforts = list(dict.fromkeys(r["effort"] for r in routes
                                if effective and model_ok(effective, [r["model"]])))
    if effective and model_ok(effective, allowed) and effort in efforts:
        entry["decision"] = "allow"
        if not model:
            entry["model"] = effective
            entry["model_from"] = "agent file"
        return None
    entry["decision"] = "deny"
    reason = ("routing.json runs the %s role on %s (docs/routing.md); this launch %s. "
              "Set model to %s on the Agent call."
              % (role, " or ".join(allowed), "names model %s" % model if model else "names no model", allowed[0]))
    if effective and model_ok(effective, allowed):
        reason = ("routing.json runs the %s role on %s with effort %s (docs/routing.md); "
                  "this launch %s. Set effort to %s on the Agent call."
                  % (role, effective, " or ".join(efforts) or "from its kind's route",
                     "names effort %s" % effort if effort is not None else "names no effort",
                     " or ".join(efforts) or "the kind's route"))
    entry["reason"] = reason
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                   "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


HEREDOC = re.compile(r"(?P<head>[^\n]*?<<-?[ \t]*(['\"]?)(\w+)\2[^\n]*)\n(?P<body>.*?)\n[ \t]*\3[ \t]*(?:\n|$)", re.S)
SHELL_HEREDOC = re.compile(r"(?:^|[;&|(\n])[ \t]*" + r"(?:sh|bash|zsh|dash)(?:[ \t]+-[^\s<]+)*[ \t]*<<")
# A quoted string, but the one after sh/bash/zsh -c is a command and is kept.
QUOTED = re.compile(
    r"(?P<keep>(?:^|[\s;&|(])(?:ba|z)?sh\s+(?:-\S+\s+)*-c\s+)(?P<cmd>\"(?:\\.|[^\"\\])*\"|'[^']*')"
    r"|\"(?:\\.|[^\"\\])*\"|'[^']*'", re.S)


def _quoted(m):
    if m.group("cmd"):
        return m.group("keep") + " " + m.group("cmd")[1:-1]
    return '""'


def code_of(cmd):
    """Strip data heredocs and quoted data, keeping shell -c command strings."""
    cmd = HEREDOC.sub(lambda m: m.group("head") + "\n" +
                      (code_of(m.group("body")) + "\n" if SHELL_HEREDOC.search(m.group("head")) else ""), cmd)
    return QUOTED.sub(_quoted, cmd)


# Shell targets remain separate from command text, which never enters the log.
TARGET = r"(?:\"[^\"]*\"|'[^']*'|[^\s;&|<>]+)"
REDIRECT = re.compile(r"(?<![<>&])(?:[0-9]*)(>>?)(?![>&])\s*(" + TARGET + r")")


def private_target(path, data):
    path = path.strip("\"'")
    if ".." in path.split("/"):
        return False
    if re.match(r"^\$\{?AGENTIC_RETRO_NOTES\}?(?:/|$)", path):
        return True
    path = os.path.realpath(os.path.join(data.get("cwd") or "", os.path.expandvars(path)))
    root = os.environ.get("AGENTIC_RETRO_NOTES")
    if root:
        root = os.path.realpath(root)
        if path == root or path.startswith(root + os.sep):
            return True
    session = data.get("session_id")
    if not session:
        return False
    for root in {"/private/tmp", "/tmp", os.environ.get("TMPDIR") or tempfile.gettempdir()}:
        pattern = (re.escape(os.path.realpath(root).rstrip("/")) + r"/claude-[^/]+/[^/]+/"
                   + re.escape(session) + r"(?:/|$)")
        if re.match(pattern, path):
            return True
    return False


def exclude_private_writes(cmd, data):
    cmd = REDIRECT.sub(lambda m: " " if private_target(m.group(2), data) else m.group(0), cmd)
    # Only discard a utility when every possible destination is private.
    def utility(command):
        try:
            args = shlex.split(command)
        except ValueError:
            return command
        paths = [a for a in args[1:] if not a.startswith("-")]
        if args[0] == "cp":
            # Target-directory options and clusters stay counted conservatively.
            if any(a.startswith("--target") or
                   (a.startswith("-") and not a.startswith("--") and "t" in a[1:])
                   for a in args[1:]):
                return command
            paths = paths[-1:]
        if args[0] == "sed":
            # Only simple substitutions establish that input files are all the writes.
            operands, scripts, i = [], [], 1
            while i < len(args):
                a = args[i]
                if a == "-e" and i + 1 < len(args):
                    scripts.append(args[i + 1])
                    i += 2
                    continue
                if a == "-i" and i + 1 < len(args) and args[i + 1] == "":
                    i += 2
                    continue
                if a.startswith("-i") or a in ("-E", "-r", "-n"):
                    pass
                elif a.startswith("-"):
                    return command  # script files and other options stay counted
                elif not scripts:
                    scripts.append(a)
                else:
                    operands.append(a)
                i += 1
            if not scripts or not all(re.fullmatch(r"s/[^/;\n]*/[^/;\n]*/[gIp0-9]*", x) for x in scripts):
                return command
            paths = operands
        return " " if paths and all(private_target(a, data) for a in paths) else command
    return re.sub(r"(^|[;&|\n])[ \t]*((?:tee|mkdir|touch|rm|mv|cp|sed)\b[^;&|\n]*)",
                  lambda m: m.group(1) + utility(m.group(2)), cmd)

def check_bash(data, entry):
    cwd = data.get("cwd") or ""
    role = None
    if os.path.isfile(os.path.join(cwd, "CLAUDE.md")):
        if os.path.isfile(os.path.join(cwd, "track.md")):
            role = "lead"
        elif os.path.basename(os.path.normpath(cwd)) == "pm" and os.path.isfile(
                os.path.join(cwd, "..", "track.md")):
            role = "pm"
    if role is None:
        return False
    cmd = str((data.get("tool_input") or {}).get("command") or "")
    code = code_of(exclude_private_writes(cmd, data))
    kinds = [name for name, rx in WRITE_PATTERNS if rx.search(code)]
    if git_writes(code):
        kinds.append("git write")
    if not kinds:
        return False
    entry.update(role=role, decision=role + "-write", detail=kinds)
    return True


def session_path(data):
    session = str(data.get("session_id") or "unknown")
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", session):
        raise ValueError("invalid session id")
    return os.path.join(os.path.dirname(log_path()), "sessions", session)


def save_session(data, state):
    path = session_path(data)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=os.path.dirname(path), delete=False) as f:
            temporary = f.name
            json.dump(state, f)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def session_state(data, entry):
    try:
        with open(session_path(data)) as f:
            state = json.load(f)
        if not isinstance(state, dict):
            raise ValueError("invalid session state")
        return state
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as e:
        write_log(dict(entry, decision="error", error="%s: %s" % (type(e).__name__, e)))
        save_session(data, {})
        return {}


def is_coordinator(data, state):
    # Subagents never inherit the coordinator's role or cached state.
    if data.get("agent_id") or data.get("agent_type"):
        return False
    if "coordinator" not in state:
        transcript = data.get("transcript_path")
        if not transcript:
            return False
        try:
            with open(transcript, "rb") as f:
                remaining = 2 * 1024 * 1024
                while remaining:
                    line = f.readline(remaining)
                    if not line:
                        break
                    remaining -= len(line)
                    try:
                        row = json.loads(line)
                    except (ValueError, UnicodeError):
                        continue
                    if not isinstance(row, dict) or row.get("type") != "user":
                        continue
                    message = row.get("message") or {}
                    content = message.get("content", "") if isinstance(message, dict) else ""
                    if isinstance(content, list):
                        content = "\n".join(c.get("text", "") for c in content
                                            if isinstance(c, dict) and c.get("type") == "text")
                    state["coordinator"] = bool(isinstance(content, str) and
                                               re.search(r"^\*\*Lead session:\*\*[^\n]*$", content, re.M))
                    break
        except OSError:
            return False
        if "coordinator" not in state:
            return False
        save_session(data, state)
    return state["coordinator"]


def changed_files(cwd):
    def git(*args):
        return subprocess.check_output(["git", "-C", cwd, *args], stderr=subprocess.DEVNULL, timeout=5).decode().rstrip("\n")
    try:
        default = git("symbolic-ref", "refs/remotes/origin/HEAD")
    except subprocess.CalledProcessError:
        default = next((r for r in ("origin/main", "origin/master", "main", "master")
                        if subprocess.run(["git", "-C", cwd, "rev-parse", "--verify", r],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode == 0), None)
        if default is None:
            raise RuntimeError("default branch unavailable")
    base = git("merge-base", "HEAD", default)
    root = git("rev-parse", "--show-toplevel")
    # Implementer-touched means tracked differences from the default merge base plus untracked files.
    names = git("diff", "--name-only", "-z", base, "--") + "\0" + git("ls-files", "--full-name", "--others", "--exclude-standard", "-z")
    return {os.path.realpath(os.path.join(root, p)) for p in names.split("\0") if p}


def check_coordinator(data, entry):
    if data.get("agent_id") or data.get("agent_type"):
        return False
    path = session_path(data)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Keep role detection, read counts and edit classification in one transaction.
    with open(path + ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return check_coordinator_locked(data, entry)


def check_coordinator_locked(data, entry):
    state = session_state(data, entry)
    if not is_coordinator(data, state):
        return False
    tool, ti = data.get("tool_name"), data.get("tool_input") or {}
    entry["role"] = "coordinator"
    targets = []
    if tool in ("Edit", "Write", "MultiEdit"):
        targets = [ti["file_path"]]
    elif tool == "Bash":
        cmd = str(ti.get("command") or "")
        code = code_of(cmd)
        if any(rx.search(code) for _, rx in WRITE_PATTERNS) or git_writes(code):
            targets = [m.group(2).strip("\"'") for m in REDIRECT.finditer(cmd)]
            if re.search(r"[;&|\n]", code) or git_writes(code):
                targets = []  # compound commands have uncertain destinations
            elif targets and any(rx.search(code) for name, rx in WRITE_PATTERNS if name != "redirect"):
                targets = []
            elif not targets:
                # Utility operands are conservative: an uncertain target is first-version.
                try:
                    targets = [a for a in shlex.split(cmd)[1:] if not a.startswith("-")]
                except ValueError:
                    targets = []
        else:
            state["reads"] = state.get("reads", 0) + 1
            save_session(data, state)
            return False
    elif tool in ("Read", "Grep", "Glob"):
        state["reads"] = state.get("reads", 0) + 1
        save_session(data, state)
        return False
    else:
        return False
    touched = changed_files(data.get("cwd") or "")
    paths = [os.path.realpath(os.path.join(data.get("cwd") or "", t)) for t in targets]
    own = set(state.get("first_versions", []))
    first = {p for p in paths if p not in touched or p in own}
    state["first_versions"] = sorted(own | first)
    save_session(data, state)
    entry.update(decision="coordinator-edit", detail="fix" if paths and not first else "first-version")
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
        elif tool == "Bash" and check_bash(data, entry):
            pass  # Lead writes are logged independently of coordinator state failures.
        elif not check_coordinator(data, entry):
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
