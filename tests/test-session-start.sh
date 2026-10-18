#!/bin/sh
# session-start.sh prints the plugin root line and RULES.md, under the 9,500
# character cap for a hook's output.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
fail=0
bad() { echo "FAIL: $*"; fail=1; }
out=$(CLAUDE_PLUGIN_ROOT="$root" sh "$root/hooks/session-start.sh") || bad "exited non-zero"
printf '%s\n' "$out" | head -n 1 | grep -q "^Plugin root .*: $root\$" || bad "first line does not name the plugin root"
printf '%s\n' "$out" | grep -q '^# Rules$' || bad "RULES.md missing from the output"
n=$(printf '%s\n' "$out" | wc -c | tr -d ' ')
echo "session-start output: $n characters"
[ "$n" -lt 9500 ] || bad "output is $n characters, over the 9,500 cap"
# Without CLAUDE_PLUGIN_ROOT it finds the root from its own place.
env -u CLAUDE_PLUGIN_ROOT sh "$root/hooks/session-start.sh" | grep -q '^# Rules$' || bad "no rules without CLAUDE_PLUGIN_ROOT"
[ "$fail" = 0 ] && echo "ok"
exit "$fail"
