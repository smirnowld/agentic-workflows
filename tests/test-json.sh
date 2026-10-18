#!/bin/sh
# Every JSON file parses, and the manifest's paths point at the right places.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$root" || exit 1
fail=0
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json routing.json; do
  python3 -m json.tool "$f" > /dev/null || { echo "FAIL: $f is not valid JSON"; fail=1; }
done
python3 - <<'PY' || fail=1
import json, os, sys
m = json.load(open(".claude-plugin/plugin.json"))
ok = m.get("name") == "agentic-workflows"
for a in m.get("agents", []):
    ok &= a.startswith("./") and a.endswith(".md")
    if not os.path.exists(a):
        print("note: %s does not exist yet" % a)
mk = json.load(open(".claude-plugin/marketplace.json"))
ok &= mk["name"] == "agentic-workflows" and mk["plugins"][0]["source"] == "."
h = json.load(open("hooks/hooks.json"))["hooks"]
for ev in h.values():
    for g in ev:
        for hk in g["hooks"]:
            path = hk["command"].replace('"', "").replace("${CLAUDE_PLUGIN_ROOT}/", "")
            if not os.access(path, os.X_OK):
                print("FAIL: hook %s is missing or not executable" % path); ok = False
sys.exit(0 if ok else 1)
PY
[ "$fail" = 0 ] && echo "ok"
exit "$fail"
