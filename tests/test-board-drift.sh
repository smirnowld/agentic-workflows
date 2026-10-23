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
 {"updatedAt":"$recent","status":{"name":"Todo"},"content":{"__typename":"Issue","url":"$u/issues/5","title":"Finished epic","state":"OPEN","updatedAt":"$recent","subIssuesSummary":{"total":2,"completed":2}}},
 {"updatedAt":"$recent","status":{"name":"Todo"},"content":{"__typename":"Issue","url":"$u/issues/6","title":"Running epic","state":"OPEN","updatedAt":"$recent","subIssuesSummary":{"total":2,"completed":1}}},
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
has upkeep-due "Finished epic"
n=$(echo "$out" | wc -l | tr -d ' '); check "exactly four findings" 4 "$n"
echo "$out" | python3 -c 'import sys,json
for l in sys.stdin: assert set(json.loads(l))=={"kind","url","title","detail"}'; check "json fields" 0 $?
python3 "$tool" ORG 1 --repo ORG/r | grep -q "^upkeep-due: Finished epic"; check "plain lines" 0 $?
out=$(python3 "$tool" ORG 1 --stale-days 100000 --json); check "no repo, stale limit raised" 0 $?
echo "$out" | grep -q '"stale"'; check "stale-days respected" 1 $?
python3 "$tool" ORG >/dev/null 2>&1; check "missing number is an error" 2 $?
# Idea is healthy unless a whole Phase iteration elapsed without issue or board activity.
cp "$tmp/items.json" "$tmp/base-items.json"
python3 - "$tmp/items.json" <<'PYIDEA'
import json, sys
from datetime import datetime, timedelta, timezone
p = sys.argv[1]
d = json.load(open(p))
board = d['data']['organization']['projectV2']
now = datetime.now(timezone.utc)
start = now - timedelta(days=30)
stamp = lambda t: t.isoformat()
board['fields'] = {'nodes': [{'name':'Phase', 'configuration': {
    'iterations':[{'startDate':(now+timedelta(days=2)).date().isoformat(),'duration':14}],
    'completedIterations':[{'startDate':start.date().isoformat(),'duration':14}]}}]}
for n, title, issue_days, board_days, state in (
    (51,'Idea untouched',40,40,'OPEN'),
    (52,'Idea issue triaged',1,40,'OPEN'),
    (53,'Idea board triaged',40,1,'OPEN'),
    (54,'Idea recent',1,1,'OPEN'),
    (55,'Idea closed',40,40,'CLOSED'),
    (56,'Idea within phase',20,20,'OPEN')):
    board['items']['nodes'].append(dict(status={'name':'Idea'}, updatedAt=stamp(now-timedelta(days=board_days)),
        content=dict(__typename='Issue',url='https://example.invalid/o/r/issues/'+str(n),title=title,state=state,
                     updatedAt=stamp(now-timedelta(days=issue_days)))))
json.dump(d,open(p,'w'))
PYIDEA
out=$(python3 "$tool" ORG 1 --json)
has idea-untriaged "Idea untouched"
for title in 'Idea issue triaged' 'Idea board triaged' 'Idea recent' 'Idea closed' 'Idea within phase'; do
 echo "$out" | grep '"kind": "idea-untriaged"' | grep -q "$title"; check "not untriaged: $title" 1 $?
done
python3 - "$tmp/items.json" <<'PYIDEA'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['data']['organization']['projectV2'].pop('fields'); json.dump(d,open(p,'w'))
PYIDEA
out=$(python3 "$tool" ORG 1 --json 2>"$tmp/idea-err")
echo "$out" | grep -q '"kind": "idea-untriaged"'; check "no inferred phase length without dates" 1 $?
grep -q 'Idea phase age unavailable' "$tmp/idea-err"; check "missing phase dates reported" 0 $?
mv "$tmp/base-items.json" "$tmp/items.json"
# Closing an on-board issue tracks the PR; old open bot PRs need attention.
python3 - "$tmp/prs.json" <<'PYTEST'
import json, sys
from datetime import datetime, timedelta, timezone
p = sys.argv[1]
prs = json.load(open(p))
nodes = prs['data']['repository']['pullRequests']['nodes']
base = nodes[0]['url'].rsplit('/', 1)[0]
nodes.append(dict(url=base+'/10', title='Closes tracked issue',
                  closingIssuesReferences={'nodes':[{'url':base.replace('/pull','/issues')+'/4'}]}))
for n, days, draft, login in ((11,4,False,'dependabot'), (12,2,False,'dependabot[bot]'),
                               (13,4,True,'dependabot'), (14,4,False,'contributor')):
    nodes.append(dict(url=base+'/'+str(n), title='Dependency '+str(n), isDraft=draft,
                      author={'login':login}, createdAt=(datetime.now(timezone.utc)-timedelta(days=days)).isoformat()))
json.dump(prs, open(p,'w'))
PYTEST
out=$(python3 "$tool" ORG 1 --repo ORG/r --json)
echo "$out" | grep -q 'Closes tracked issue'; check "PR closing tracked issue is tracked" 1 $?
has bot-wait "Dependency 11"
for title in 'Dependency 12' 'Dependency 13' 'Dependency 14'; do
 echo "$out" | grep '"kind": "bot-wait"' | grep -q "$title"; check "not bot-wait: $title" 1 $?
done
# options: another status field and other names for done and in progress
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
cat "$FAKE_ITEMS"
GH
out=$(python3 "$tool" ORG 1 --status-field Stage --done Shipped --in-progress Doing --json)
echo "$out" | grep -q 'Properly done'; check "custom done name: Done is no longer done" 0 $?
echo "$out" | grep -q 'Forgotten work'; check "custom in-progress name: nothing stale" 1 $?
# waiting-unlinked: Waiting items need an open blocked-by link, or an outside wait in words
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
cat "$FAKE_ITEMS"
GH
wf() { printf ',"fieldValues":{"nodes":[{},{"text":"%s","field":{"name":"%s"}}]}' "$1" "${2:-Waiting for}"; }
wi() { # number title blockers-json [waiting-for [field-name]]
  printf '{"updatedAt":"%s","status":{"name":"Waiting"}%s,"content":{"__typename":"Issue","url":"%s/issues/%s","title":"%s","state":"OPEN","updatedAt":"%s","blockedBy":{"nodes":%s}}},' \
    "$recent" "$( [ -n "$4" ] && wf "$4" "$5" )" "$u" "$1" "$2" "$recent" "$3"; }
{
 printf '{"data":{"organization":{"projectV2":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":['
 wi 31 "Wait empty" '[]'
 wi 32 "Wait hash" '[]' "#12"
 wi 33 "Wait url" '[]' "see https://github.com/o/r/issues/7"
 wi 34 "Wait words" '[]' "the customer signs"
 wi 35 "Wait linked" '[{"state":"OPEN"}]'
 wi 36 "Wait closed link" '[{"state":"CLOSED"}]'
 wi 37 "Wait lower case field" '[]' "#12" "waiting FOR"
 wi 38 "Wait words with open link" '[{"state":"OPEN"}]' "#12"
 printf '{"updatedAt":"%s","status":{"name":"Waiting"},"content":{"__typename":"DraftIssue"}},' "$recent"
 printf '{"updatedAt":"%s","status":{"name":"Waiting"},"content":{"__typename":"PullRequest","url":"%s/pull/39","title":"Wait pr","state":"OPEN","updatedAt":"%s"}}' "$recent" "$u" "$recent"
 printf ']}}}}}'
} > "$tmp/wait.json"
out=$(FAKE_ITEMS="$tmp/wait.json" python3 "$tool" ORG 1 --json); check "waiting: exit 0" 0 $?
w() { echo "$out" | grep '"waiting-unlinked"' | grep -q "$1"; check "waiting-unlinked $2: $1" "$3" $?; }
w "Wait empty" flagged 0
w "Wait hash" flagged 0
w "Wait url" flagged 0
w "Wait words\"" "not flagged" 1
w "Wait linked" "not flagged" 1
w "Wait closed link" flagged 0
w "Wait lower case field" flagged 0
w "Wait words with open link" "not flagged" 1
w "Wait pr" "not flagged" 1
n=$(echo "$out" | wc -l | tr -d ' '); check "waiting: five findings, draft ignored" 5 "$n"
FAKE_ITEMS="$tmp/wait.json" python3 "$tool" ORG 1 > "$tmp/plain"; grep -q "^waiting-unlinked: Wait empty .* - .*blocked by" "$tmp/plain"; check "waiting: plain line says what to do" 0 $?
# pagination: first page says more, second page ends
cat > "$tmp/bin/gh" <<'GH'
#!/bin/sh
case "$*" in *"field=Status"*) ;; *) echo "wrong status field" >&2; exit 1 ;; esac
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$FAKE_COUNT"
if [ "$n" = 0 ]; then cat "$FAKE_PAGE1"; else cat "$FAKE_PAGE2"; fi
GH
export FAKE_COUNT="$tmp/count" FAKE_PAGE1="$tmp/p1.json" FAKE_PAGE2="$tmp/p2.json"
cat > "$tmp/p1.json" <<P1
{"data":{"organization":{"projectV2":{"fields":{"nodes":[{"name":"Phase","configuration":{"iterations":[],"completedIterations":[]}}]},"items":{"pageInfo":{"hasNextPage":true,"endCursor":"c1"},"nodes":[
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
