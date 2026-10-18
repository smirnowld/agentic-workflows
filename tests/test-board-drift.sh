#!/bin/sh
# board-drift with a fake gh on PATH: every kind of finding, and error exits.
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../bin/board-drift"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (exit $3, wanted $2)"; fail=1; fi; }
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
# Fake gh: answers the project query from $FAKE_ITEMS and the pull request query from $FAKE_PRS.
case "$*" in
  *pullRequests*) cat "$FAKE_PRS" ;;
  *) cat "$FAKE_ITEMS" ;;
esac
GH
chmod +x "$tmp/bin/gh"
PATH="$tmp/bin:$PATH"
recent=$(python3 -c 'from datetime import datetime,timezone;print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')
u=https://example.invalid/o/r
cat > "$tmp/items.json" <<ITEMS
{"data":{"organization":{"projectV2":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
 {"updatedAt":"$recent","status":{"name":"In progress"},"content":{"__typename":"Issue","url":"$u/issues/1","title":"Closed but open on board","state":"CLOSED","updatedAt":"$recent"}},
 {"updatedAt":"$recent","status":{"name":"Done"},"content":{"__typename":"Issue","url":"$u/issues/2","title":"Properly done","state":"CLOSED","updatedAt":"$recent"}},
 {"updatedAt":"2020-01-01T00:00:00Z","status":{"name":"In progress"},"content":{"__typename":"Issue","url":"$u/issues/3","title":"Forgotten work","state":"OPEN","updatedAt":"2020-01-01T00:00:00Z"}},
 {"updatedAt":"$recent","status":{"name":"In progress"},"content":{"__typename":"Issue","url":"$u/issues/4","title":"Fresh work","state":"OPEN","updatedAt":"$recent"}},
 {"updatedAt":"$recent","status":{"name":"Todo"},"content":{"__typename":"Issue","url":"$u/issues/5","title":"Finished initiative","state":"OPEN","updatedAt":"$recent","subIssuesSummary":{"total":2,"completed":2}}},
 {"updatedAt":"$recent","status":{"name":"Todo"},"content":{"__typename":"Issue","url":"$u/issues/6","title":"Running initiative","state":"OPEN","updatedAt":"$recent","subIssuesSummary":{"total":2,"completed":1}}},
 {"updatedAt":"$recent","status":null,"content":{}}
]}}}}}
ITEMS
cat > "$tmp/prs.json" <<PRS
{"data":{"repository":{"pullRequests":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
 {"url":"$u/pull/9","title":"Loose pull request"},
 {"url":"$u/issues/4","title":"Already on board"}
]}}}}
PRS
export FAKE_ITEMS="$tmp/items.json" FAKE_PRS="$tmp/prs.json"

out=$(python3 "$tool" ORG 1 --repo ORG/r --json); check "exit 0 with findings" 0 $?
has() { echo "$out" | grep "\"kind\": \"$1\"" | grep -q "$2"; check "$1: $2" 0 $?; }
has closed-not-done "Closed but open on board"
has stale "Forgotten work"
has not-on-board "Loose pull request"
has upkeep-due "Finished initiative"
n=$(echo "$out" | wc -l | tr -d ' '); check "exactly four findings" 4 "$n"
echo "$out" | python3 -c 'import sys,json
for l in sys.stdin: assert set(json.loads(l))=={"kind","url","title","detail"}'; check "json fields" 0 $?
python3 "$tool" ORG 1 --repo ORG/r | grep -q "^upkeep-due: Finished initiative"; check "plain lines" 0 $?
out=$(python3 "$tool" ORG 1 --stale-days 100000 --json); check "no repo, stale limit raised" 0 $?
echo "$out" | grep -q '"stale"'; check "stale-days respected" 1 $?
python3 "$tool" ORG >/dev/null 2>&1; check "missing number is an error" 2 $?
# options: another status field and other names for done and in progress
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
cat "$FAKE_ITEMS"
GH
out=$(python3 "$tool" ORG 1 --status-field Stage --done Shipped --in-progress Doing --json)
echo "$out" | grep -q 'Properly done'; check "custom done name: Done is no longer done" 0 $?
echo "$out" | grep -q 'Forgotten work'; check "custom in-progress name: nothing stale" 1 $?
# pagination: first page says more, second page ends
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$FAKE_COUNT"
if [ "$n" = 0 ]; then cat "$FAKE_PAGE1"; else cat "$FAKE_PAGE2"; fi
GH
export FAKE_COUNT="$tmp/count" FAKE_PAGE1="$tmp/p1.json" FAKE_PAGE2="$tmp/p2.json"
cat > "$tmp/p1.json" <<P1
{"data":{"organization":{"projectV2":{"items":{"pageInfo":{"hasNextPage":true,"endCursor":"c1"},"nodes":[
 {"updatedAt":"$recent","status":{"name":"Todo"},"content":{"__typename":"Issue","url":"$u/issues/21","title":"Page one finished","state":"OPEN","updatedAt":"$recent","subIssuesSummary":{"total":1,"completed":1}}}
]}}}}}
P1
cat > "$tmp/p2.json" <<P2
{"data":{"organization":{"projectV2":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
 {"updatedAt":"$recent","status":{"name":"Todo"},"content":{"__typename":"Issue","url":"$u/issues/22","title":"Page two finished","state":"OPEN","updatedAt":"$recent","subIssuesSummary":{"total":1,"completed":1}}}
]}}}}}
P2
out=$(python3 "$tool" ORG 1 --json)
echo "$out" | grep -q 'Page one' && echo "$out" | grep -q 'Page two'; check "both pages read" 0 $?
# user fallback: the organization query cannot be resolved, the user query works
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
case "$*" in
  *organization*) echo "Could not resolve to an Organization" >&2; exit 1 ;;
  *) sed 's/"organization"/"user"/' "$FAKE_ITEMS" ;;
esac
GH
out=$(python3 "$tool" someone 1 --json); check "user fallback" 0 $?
echo "$out" | grep -q 'Forgotten work'; check "user fallback finds items" 0 $?
# another organization error is reported, not the fallback's
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
case "$*" in
  *organization*) echo "missing scope read:project" >&2; exit 1 ;;
  *) echo "Could not resolve to a User" >&2; exit 1 ;;
esac
GH
python3 "$tool" ORG 1 2> "$tmp/err" >/dev/null; check "scope error exits 2" 2 $?
grep -q "read:project" "$tmp/err"; check "first error reported" 0 $?
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/gh"
python3 "$tool" ORG 1 >/dev/null 2>&1; check "gh failure is an error" 2 $?
exit "$fail"
