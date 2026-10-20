#!/bin/sh
# SessionStart: print RULES.md from the plugin root, so every session starts
# with the rules, and one line naming the plugin root (for the helpers in bin/).
# A hook's output over 10,000 characters is saved to a file and shown as a
# 2,000-character preview (https://code.claude.com/docs/en/hooks): the test
# keeps RULES.md under 9,500.
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
python3 "$root/hooks/rules-check.py" --mark || :
echo "Plugin root for routing.json, docs and helpers: $root"
cat "$root/RULES.md"
