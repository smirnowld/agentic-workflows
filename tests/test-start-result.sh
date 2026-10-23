#!/bin/sh
# Real starts, app refusals, proposals and unrecognised or broken responses.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export AGENTIC_LOG_DIR="$tmp/log"
python3 - "$root" <<'PY'
import json, os, subprocess, sys
root = sys.argv[1]
hook = root + "/hooks/start-result.py"
log = os.environ["AGENTIC_LOG_DIR"] + "/launch-log.jsonl"

def run(data):
    r = subprocess.run([sys.executable, hook], input=data, text=True, capture_output=True)
    assert r.returncode == 0 and not r.stdout and not r.stderr, r

def check(response, expected, event="PostToolUse", tool="mcp__ccd_session__start_session", **extra):
    data = dict(session_id="parent", cwd="/work", tool_name=tool,
                hook_event_name=event, tool_response=response,
                tool_input={"initiation":"manual"}, **extra)
    before = len(open(log).readlines()) if os.path.exists(log) else 0
    run(json.dumps(data))
    rows = [json.loads(line) for line in open(log)]
    assert len(rows) == before + 1
    row = rows[-1]
    assert row["result"] == expected, row
    assert row["hook"] == "start-result" and row["session"] == "parent"
    assert row["cwd"] == "/work" and row["tool"] == tool and row["time"]
    assert "decision" not in row
    return row

started = 'Started session "Example" (session_id: local_123, name: example)'
row = check({"content":[{"type":"text", "text":started}]}, "started")
assert row["started_session_id"] == "local_123"
check(started, "started", tool="mcp__ccd_session__spawn_task")
for refusal in ("Start sessions only on the user's own words to you here; " + "x" * 250,
                "A proposal card cannot carry a host, folder, environment or preset yet: example"):
    row = check({"is_error":True, "content":[{"type":"text", "text":refusal}]}, "refused")
    assert row["refusal"] == refusal[:200] and "started_session_id" not in row
    row = check(None, "refused", event="PostToolUseFailure", error=refusal, is_interrupt=False)
    assert row["refusal"] == refusal[:200]
check({"isError":True, "content":[{"text":started}]}, "refused")
for proposal in ({"proposal_id":"proposal-1"}, {"task_id":"task-1"},
                 {"structuredContent":{"proposal":{"id":"proposal-1"}}},
                 {"content":[{"type":"text", "text":'{"task_id":"task-1"}'}]},
                 {"content":[{"text":'Created proposal (proposal_id: proposal-1)'}]},
                 'Created task (task_id: task-1)'):
    check(proposal, "proposed")
check({"content":[{"text":"Unexpected response"}]}, "unknown")
check(None, "unknown")
# An initiation request alone is not proof of a proposal or a start.
check({}, "unknown")
before = open(log).read()
for data in ("{}", '{"tool_name":"Read"}'):
    run(data)
assert open(log).read() == before
for data in ("", "bad json", "[]", "null"):
    count = len(open(log).readlines())
    run(data)
    rows = [json.loads(line) for line in open(log)]
    assert len(rows) == count + 1
    row = rows[-1]
    assert row["hook"] == "start-result" and row["result"] == "error"
    assert row["error"] and row["time"] and "decision" not in row
os.environ["AGENTIC_LOG_DIR"] = log  # a file cannot be a log directory
r = subprocess.run([sys.executable, hook],
                   input=json.dumps({"tool_name":"mcp__ccd_session__start_session", "tool_response":started}),
                   text=True, capture_output=True)
assert r.returncode == 0 and not r.stdout
assert len(r.stderr.splitlines()) == 1
assert r.stderr.startswith("start-result: cannot write error to launch log:"), r
h = json.load(open(root + "/hooks/hooks.json"))["hooks"]
for event in ("PostToolUse", "PostToolUseFailure"):
    assert h[event][0]["matcher"] == "mcp__ccd_session__start_session|mcp__ccd_session__spawn_task"
    assert h[event][0]["hooks"][0]["command"].endswith('/hooks/start-result.py"')
print("start-result: ok")
PY
