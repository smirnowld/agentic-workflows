#!/bin/sh
# launch-check.py against sample hook inputs: decisions, output and log lines.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
hook="$root/hooks/launch-check.py"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
AGENTIC_LOG_DIR="$tmp/log"; CLAUDE_PLUGIN_ROOT="$root"; export AGENTIC_LOG_DIR CLAUDE_PLUGIN_ROOT
log="$tmp/log/launch-log.jsonl"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

mkdir "$tmp/track" "$tmp/plain" "$tmp/log"
echo "# track" > "$tmp/track/track.md"; echo "lead" > "$tmp/track/CLAUDE.md"

agent() { printf '{"session_id":"s1","cwd":"/w","tool_name":"Agent","tool_input":{"subagent_type":"%s"%s}}' "$1" "${2:+,\"model\":\"$2\"}" | python3 "$hook"; }
bash_in() { printf '{"session_id":"s1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2" | python3 "$hook"; }
# expect_agent NAME TYPE MODEL DECISION
expect_agent() {
  : > "$log"
  out=$(agent "$2" "$3" 2>&1)
  d=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1])["decision"])' < "$log" 2>/dev/null)
  [ "$d" = "$4" ] || bad "$1: logged decision '$d', want $4"
  case $4 in
    deny) printf '%s' "$out" | grep -q '"permissionDecision": "deny"' || bad "$1: no deny output" ;;
    *) [ -z "$out" ] || bad "$1: expected no output, got: $out" ;;
  esac
  [ "$(wc -l < "$log" | tr -d ' ')" = 1 ] || bad "$1: want exactly one log line"
}
expect_agent "implementer sonnet" implementer sonnet allow
expect_agent "prefixed implementer opus" agentic-workflows:implementer opus allow
expect_agent "implementer no model" implementer "" deny
expect_agent "implementer gpt" implementer gpt-6.1-sol deny
expect_agent "critical-reviewer opus" critical-reviewer opus allow
expect_agent "critical-reviewer sonnet" agentic-workflows:critical-reviewer sonnet deny
expect_agent "reviewer no model" reviewer "" deny
expect_agent "explorer sonnet" explorer sonnet allow
expect_agent "unrouted" Explore "" pass
expect_agent "full model id" reviewer claude-sonnet-4-5 allow
out=$(agent reviewer "" 2>&1); case $out in *"names no model"*"sonnet"*) ;; *) bad "deny message does not name the expected model: $out" ;; esac

# Bash: only a lead's folder is looked at, writes are logged and never blocked.
: > "$log"
out=$(bash_in "$tmp/track" "git status | cat"); [ -z "$out" ] && [ ! -s "$log" ] || bad "read-only command was logged"
for c in 'echo x > f' 'echo x >> f' 'ls | tee f' 'sed -i s/a/b/ f' 'mv a b' 'cp a b' 'rm a' 'mkdir d' 'touch f' 'git commit -m x' 'git push' 'git apply p'; do
  : > "$log"
  out=$(bash_in "$tmp/track" "$c")
  [ -z "$out" ] || bad "'$c' was blocked or printed: $out"
  grep -q '"decision": "lead-write"' "$log" || bad "'$c' not logged as a lead write"
done
: > "$log"
bash_in "$tmp/plain" "rm a"; [ ! -s "$log" ] || bad "write outside a track folder was logged"
: > "$log"
bash_in "$tmp/track" "echo x 2>&1 | cat"; [ ! -s "$log" ] || bad "2>&1 counted as a write"

# Never fails closed: bad input and a broken routing.json allow and log "error".
: > "$log"
out=$(echo 'not json' | python3 "$hook" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && grep -q '"decision": "error"' "$log" || bad "bad input: rc=$rc out=$out"
mkdir "$tmp/badroot"; echo '{' > "$tmp/badroot/routing.json"; : > "$log"
out=$(CLAUDE_PLUGIN_ROOT="$tmp/badroot" agent implementer sonnet 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && grep -q '"decision": "error"' "$log" || bad "broken routing.json: rc=$rc out=$out"
[ "$fail" = 0 ] && echo "ok"
exit "$fail"
