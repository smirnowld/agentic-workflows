#!/bin/sh
# session-start.sh prints the plugin root line and RULES.md, under the 9,500
# character cap for a hook's output.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
# A temporary launch log, and no stdin: the hook reads its input from stdin.
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
AGENTIC_LOG_DIR="$tmp/log"; export AGENTIC_LOG_DIR
fail=0
bad() { echo "FAIL: $*"; fail=1; }
out=$(echo '{"session_id":"test"}' | CLAUDE_PLUGIN_ROOT="$root" sh "$root/hooks/session-start.sh") || bad "exited non-zero"
printf '%s\n' "$out" | head -n 1 | grep -q "^Plugin root .*: $root\$" || bad "first line does not name the plugin root"
printf '%s\n' "$out" | grep -q '^# Rules$' || bad "RULES.md missing from the output"
n=$(printf '%s\n' "$out" | wc -c | tr -d ' ')
echo "session-start output: $n characters"
[ "$n" -lt 9500 ] || bad "output is $n characters, over the 9,500 cap"
# Without CLAUDE_PLUGIN_ROOT it finds the root from its own place.
echo '{"session_id":"test"}' | env -u CLAUDE_PLUGIN_ROOT sh "$root/hooks/session-start.sh" | grep -q '^# Rules$' || bad "no rules without CLAUDE_PLUGIN_ROOT"
[ -e "$tmp/log/rules-loaded/test" ] || bad "--mark did not record the session from stdin"
! grep -q '"decision": *"error"' "$tmp/log/launch-log.jsonl" 2>/dev/null || bad "the hook logged an error"
[ "$fail" = 0 ] && echo "ok"
exit "$fail"
