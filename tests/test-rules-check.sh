#!/bin/sh
# Rules delivery, markers, repeat calls and errors in an isolated log directory.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
AGENTIC_LOG_DIR="$tmp/log"; CLAUDE_PLUGIN_ROOT="$root"
export AGENTIC_LOG_DIR CLAUDE_PLUGIN_ROOT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
run() { printf '%s' "$1" | python3 "$root/hooks/rules-check.py"; }
printf '%s' '{"session_id":"start/one"}' | sh "$root/hooks/session-start.sh" > "$tmp/start" || bad "session-start exit"
[ -f "$AGENTIC_LOG_DIR/rules-loaded/start_one" ] || bad "session-start marker missing"
[ "$(run '{"session_id":"start/one"}')" = '' ] || bad "marked call printed output"
[ ! -e "$AGENTIC_LOG_DIR/launch-log.jsonl" ] || bad "marked call logged"
run '{"session_id":"late","cwd":"/work","tool_name":"Read"}' > "$tmp/out" || bad "late call exit"
python3 - "$tmp/out" "$root" "$AGENTIC_LOG_DIR" <<'PY' || bad "late context or log"
import json, os, sys
out, root, log = sys.argv[1:]
d = json.load(open(out))
expected = "Plugin root for routing.json, docs and helpers: %s\n%s" % (root, open(root + "/RULES.md").read())
assert d == {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": expected}}
assert os.path.isfile(log + "/rules-loaded/late")
rows = [json.loads(line) for line in open(log + "/launch-log.jsonl")]
assert len(rows) == 1
row = rows[0]
assert row["time"] and row["session"] == "late" and row["cwd"] == "/work"
assert row["hook"] == "rules-check" and row["decision"] == "rules-late" and row["tool"] == "Read"
PY
[ "$(run '{"session_id":"late"}')" = '' ] || bad "second call printed output"
[ "$(wc -l < "$AGENTIC_LOG_DIR/launch-log.jsonl" | tr -d ' ')" = 1 ] || bad "second call logged"
for data in '' 'bad json' '[]' 'null' '{}' '{"session_id":12}'; do
  out=$(run "$data" 2>&1) || bad "bad input exit"
  [ -z "$out" ] || bad "bad input output"
  printf '%s' "$data" | sh "$root/hooks/session-start.sh" > "$tmp/start" || bad "session-start bad input exit"
  head -n 1 "$tmp/start" | grep -q '^Plugin root ' || bad "session-start bad input lost rules"
done
python3 - "$AGENTIC_LOG_DIR/launch-log.jsonl" <<'PYTEST' || bad "error log"
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
errors = [row for row in rows if row.get("decision") == "error"]
# Each malformed input reaches both the tool hook and SessionStart marking.
assert len(errors) == 8, errors
assert all(row["hook"] == "rules-check" and row["error"] and row["time"] for row in errors)
PYTEST
# Repeated marking preserves the marker and produces no output or log entry.
cp "$AGENTIC_LOG_DIR/launch-log.jsonl" "$tmp/before"
printf 'kept' > "$AGENTIC_LOG_DIR/rules-loaded/late"
out=$(printf '%s' '{"session_id":"late"}' | python3 "$root/hooks/rules-check.py" --mark 2>&1) || bad "repeat mark exit"
[ -z "$out" ] || bad "repeat mark output"
[ "$(cat "$AGENTIC_LOG_DIR/rules-loaded/late")" = kept ] || bad "repeat mark changed marker"
cmp -s "$tmp/before" "$AGENTIC_LOG_DIR/launch-log.jsonl" || bad "repeat mark logged"
# Resolve the plugin root from the hook when the environment does not name it.
(unset CLAUDE_PLUGIN_ROOT; run '{"session_id":"unset-root"}') > "$tmp/unset" || bad "unset root exit"
python3 - "$tmp/unset" "$tmp/out" <<'PYTEST' || bad "unset root context"
import json, sys
assert json.load(open(sys.argv[1])) == json.load(open(sys.argv[2]))
PYTEST
# Dot paths must be files within rules-loaded, never the directory itself.
run '{"session_id":".."}' > /dev/null
[ -f "$AGENTIC_LOG_DIR/rules-loaded/_.." ] || bad "unsafe dot marker"
touch "$tmp/not-dir"
out=$(AGENTIC_LOG_DIR="$tmp/not-dir" run '{"session_id":"error"}' 2>&1) || bad "filesystem error exit"
case "$out" in
  "rules-check: cannot write error to launch log: "*) ;;
  *) bad "filesystem error missing stderr note" ;;
esac
AGENTIC_LOG_DIR="$tmp/not-dir" sh "$root/hooks/session-start.sh" <<'JSON' > "$tmp/start" 2> "$tmp/start-stderr" || bad "session-start filesystem error exit"
{"session_id":"start-error"}
JSON
head -n 1 "$tmp/start" | grep -q '^Plugin root ' || bad "session-start filesystem error lost rules"
[ "$(wc -l < "$tmp/start-stderr" | tr -d ' ')" = 1 ] || bad "session-start filesystem error stderr lines"
grep -q '^rules-check: cannot write error to launch log:' "$tmp/start-stderr" || bad "session-start filesystem error missing stderr note"
# A broken log must not swallow context after the marker is created.
mkdir -p "$tmp/broken-log/launch-log.jsonl"
AGENTIC_LOG_DIR="$tmp/broken-log" run '{"session_id":"log-error"}' > "$tmp/context" 2> "$tmp/stderr" || bad "log failure exit"
python3 - "$tmp/context" "$tmp/out" <<'PYTEST' || bad "log failure lost context"
import json, sys
assert json.load(open(sys.argv[1])) == json.load(open(sys.argv[2]))
PYTEST
[ -f "$tmp/broken-log/rules-loaded/log-error" ] || bad "log failure marker missing"
[ "$(wc -l < "$tmp/stderr" | tr -d ' ')" = 1 ] || bad "log failure stderr lines"
grep -q '^rules-check: cannot write error to launch log:' "$tmp/stderr" || bad "log failure missing stderr note"
# The fallback must be registered first and cover every tool.
python3 - "$root/hooks/hooks.json" <<'PY' || bad "registration"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]
assert h["matcher"] == "*" and h["hooks"][0]["command"].endswith('/hooks/rules-check.py"')
PY
[ "$fail" = 0 ] && echo "rules-check: ok"
exit "$fail"
