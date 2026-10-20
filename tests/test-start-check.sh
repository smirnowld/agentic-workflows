#!/bin/sh
# start-check.py against a fake gh: decisions, output, flags and log lines.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
hook="$root/hooks/start-check.py"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/log" "$tmp/nogh"
AGENTIC_LOG_DIR="$tmp/log"; AGENTIC_CONFIG="$tmp/config.json"
PATH="$tmp/bin:$PATH"; export AGENTIC_LOG_DIR AGENTIC_CONFIG PATH
log="$tmp/log/launch-log.jsonl"
hookpath=$PATH
unset CLAUDE_PROJECT_DIR
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# Fake gh: logs its arguments; answers "gh api graphql" searches from the files
# issues and prs (JSON node lists; issues-p2 and prs-p2 are the second page,
# served when the call carries after=; issues-more and prs-more make the first
# page say hasNextPage; issues-forever: every page does); fails when gh-fail exists (gh-fail-prs: only the pull
# request search); sleeps when gh-slow exists; sleeps a second on each page after
# the first when gh-slow-later exists; prints a GraphQL errors body, exit 0, when
# gh-errors exists.
cat > "$tmp/bin/gh" <<'SH'
#!/bin/sh
d=$(dirname "$0")/..
echo "$*" >> "$d/argv"
[ -e "$d/gh-slow" ] && exec sleep 5
[ -e "$d/gh-errors" ] && { echo '{"data":null,"errors":[{"message":"x"}]}'; exit 0; }
[ -e "$d/gh-fail" ] && { echo "gh: not logged in" >&2; exit 4; }
[ "$1 $2" = "api graphql" ] || exit 2
q=
for a in "$@"; do case $a in q=*) q=${a#q=} ;; esac; done
case $q in
  *"is:issue assignee:LOGIN"*) f=issues ;;
  *"is:pr review-requested:LOGIN"*) f=prs; [ -e "$d/gh-fail-prs" ] && { echo "gh: boom" >&2; exit 4; } ;;
  *) exit 2 ;;
esac
more=false; src=$f
case "$*" in *after=*) src=$f-p2; [ -e "$d/$f-forever" ] && more=true ;; *) [ -e "$d/$f-more" ] && more=true ;; esac
[ -e "$d/gh-slow-later" ] && case "$*" in *after=*) sleep 1 ;; esac
nodes=[]; [ -e "$d/$src" ] && nodes=$(cat "$d/$src")
echo "{\"data\":{\"search\":{\"pageInfo\":{\"hasNextPage\":$more,\"endCursor\":\"C\"},\"nodes\":$nodes}}}"
SH
chmod +x "$tmp/bin/gh"
# A PATH with python3 and no gh.
printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v python3)" > "$tmp/nogh/python3"; chmod +x "$tmp/nogh/python3"

# blockers START N STATE: JSON nodes of N issues, each blocking one issue in STATE
blockers() {
  python3 -c 'import json,sys; s,n,st=int(sys.argv[1]),int(sys.argv[2]),sys.argv[3]; print(json.dumps([{"url":"https://example.test/ORG/r/issues/%d"%(s+i),"blocking":{"nodes":[{"state":st,"projectItems":{"nodes":[{"fieldValueByName":{"name":"Waiting"}}]}}]}} for i in range(n)]))' "$1" "$2" "$3"
}
# reviews START N AUTHOR_TYPE LOGIN: JSON nodes of N review-requested pull requests
reviews() {
  python3 -c 'import json,sys; s,n,t,l=int(sys.argv[1]),int(sys.argv[2]),sys.argv[3],sys.argv[4]; print(json.dumps([{"url":"https://example.test/ORG/r/pull/%d"%(s+i),"author":{"__typename":t,"login":l}} for i in range(n)]))' "$1" "$2" "$3" "$4"
}
setup() { # setup CAP BLOCKERS REVIEW_PRS
  echo "{\"waiting\":{\"cap\":$1,\"maintainer\":\"LOGIN\",\"repos\":[\"ORG/a\",\"ORG/b\"]}}" > "$AGENTIC_CONFIG"
  rm -f "$tmp"/issues* "$tmp"/prs*
  blockers 1 "$2" OPEN > "$tmp/issues"; reviews 101 "$3" User human > "$tmp/prs"
  rm -f "$tmp/gh-fail" "$tmp/gh-fail-prs" "$tmp/gh-slow" "$tmp/gh-slow-later" "$tmp/gh-errors" "$tmp/argv"; : > "$log"
}
# run JSON
run() { printf '%s' "$1" | PATH=$hookpath python3 "$hook" 2>&1; }
# input TOOL PROMPT: hook input JSON
input() { python3 -c 'import json,sys; print(json.dumps({"session_id":"s1","cwd":"/w","tool_name":sys.argv[1],"tool_input":{"prompt":sys.argv[2]}}))' "$1" "$2"; }
decision() { python3 -c 'import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1])["decision"])' < "$log" 2>/dev/null; }
# expect NAME DECISION OUT(deny|none) JSON
expect() {
  : > "$log"
  out=$(run "$4")
  [ "$(decision)" = "$2" ] || bad "$1: logged '$(decision)', want $2"
  [ "$(wc -l < "$log" | tr -d ' ')" = 1 ] || bad "$1: want exactly one log line"
  case $3 in
    deny) printf '%s' "$out" | grep -q '"permissionDecision": "deny"' || bad "$1: no deny output" ;;
    *) case $out in *permissionDecision*) bad "$1: unexpected deny" ;; esac ;;
  esac
}
T=mcp__ccd_session__start_session
start() { input $T "$1"; }

setup 3 1 1
expect "under cap" allow none "$(start 'do the thing')"
grep -q '"count": 2' "$log" || bad "under cap: count not logged"

# The searches: one issue and one pull request search over all repos.
[ "$(wc -l < "$tmp/argv" | tr -d ' ')" = 2 ] || bad "want two gh calls"
grep -q "q=is:issue assignee:LOGIN is:open archived:false repo:ORG/a repo:ORG/b$" "$tmp/argv" || bad "issue search: $(cat "$tmp/argv")"
grep -q "q=is:pr review-requested:LOGIN is:open archived:false repo:ORG/a repo:ORG/b$" "$tmp/argv" || bad "pr search"

setup 3 2 4
expect "at cap" deny deny "$(start 'do the thing')"
out=$(run "$(start x)")
for n in 1 2; do case $out in *"issues/$n"*) ;; *) bad "deny lacks issue $n" ;; esac; done
case $out in *"6 items waiting on the maintainer"*"(and 1 more)"*) ;; *) bad "deny lacks count or overflow: $out" ;; esac
case $out in *"put the new request on the board"*"**Priority:** fire"*) ;; *) bad "deny lacks advice" ;; esac

setup 2 1 1
expect "exactly cap" deny deny "$(start x)"

# Coordinator routing is checked before the cap and fire; omitted values inherit.
setup 3 0 0
routed() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":dict(prompt="Priority: fire", **json.loads(sys.argv[2]))}))' "$1" "$2"; }
for tool in "$T" mcp__ccd_session__spawn_task; do
  for fields in '{"model":"opus","effort":"medium"}' '{"model":"opus","effort":"Medium"}' '{"model":"claude-opus-5-5","effort":"medium"}' '{"model":"opus"}' '{"effort":"medium"}' '{}'; do
    expect "route allows $fields" fire none "$(routed "$tool" "$fields")"
    python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).readlines()[-1]); ti=json.loads(sys.argv[2]); assert all(e[k]==ti.get(k) and e[k+"_from"]==("input" if k in ti else "inherited") for k in ("model","effort"))' "$log" "$fields" || bad "route log fields"
  done
  for fields in '{"model":"sonnet","effort":"medium"}' '{"model":"opus","effort":"high"}' '{"model":"notopus"}' '{"effort":"low"}'; do
    expect "route denies even fire $fields" deny deny "$(routed "$tool" "$fields")"
    grep -q 'opus with effort medium' "$log" || bad "route refusal lacks model and effort"
    [ ! -e "$tmp/argv" ] || bad "route check queried waiting items"
  done
done
rm "$AGENTIC_CONFIG"
expect "no config ignores route" not-configured none "$(routed "$T" '{"model":"sonnet","effort":"high"}')"

# What counts.
setup 1 0 0
blockers 1 3 CLOSED > "$tmp/issues"
expect "blockers of closed issues only" allow none "$(start x)"
grep -q '"count": 0' "$log" || bad "closed blocked: want count 0"
echo '[{"url":"https://example.test/ORG/r/issues/9","blocking":{"nodes":[]}}]' > "$tmp/issues"
expect "assigned, blocks nothing" allow none "$(start x)"
echo '[{"url":"https://example.test/ORG/r/issues/9","blocking":{"nodes":[{"state":"CLOSED","projectItems":{"nodes":[{"fieldValueByName":{"name":"Done"}}]}},{"state":"OPEN","projectItems":{"nodes":[{"fieldValueByName":{"name":"in review"}}]}}]}}]' > "$tmp/issues"
expect "one open blocked issue among closed" deny deny "$(start x)"
# started work: the blocked issue's board Status decides.
blocked_by() { # blocked_by PROJECTITEMS_JSON: one blocker of one open issue with that board data
  echo "[{\"url\":\"https://example.test/ORG/r/issues/9\",\"blocking\":{\"nodes\":[{\"state\":\"OPEN\",\"projectItems\":$1}]}}]" > "$tmp/issues"
}
blocked_by '{"nodes":[{"fieldValueByName":{"name":"In progress"}}]}'
expect "blocked issue In progress" deny deny "$(start x)"
blocked_by '{"nodes":[{"fieldValueByName":{"name":"Ready"}}]}'
expect "blocked issue Ready" allow none "$(start x)"
blocked_by '{"nodes":[{"fieldValueByName":{"name":"Backlog"}},{"fieldValueByName":null}]}'
expect "blocked issue Backlog, status-less item" allow none "$(start x)"
blocked_by '{"nodes":[]}'
expect "blocked issue on no board" allow none "$(start x)"
blocked_by '{"nodes":[{"fieldValueByName":{"name":"Ready"}},{"fieldValueByName":{"name":"WAITING"}}]}'
expect "status match ignores case, any board" deny deny "$(start x)"
blocked_by 'null'
expect "no project data fails open" error none "$(start x)"
blocked_by '{"nodes":[{"fieldValueByName":{"name":"Ready"}}]}'
echo '{"waiting":{"cap":1,"maintainer":"LOGIN","repos":["ORG/a"],"started":["ready"]}}' > "$AGENTIC_CONFIG"
expect "custom started list honoured" deny deny "$(start x)"
blocked_by '{"nodes":[{"fieldValueByName":{"name":"Waiting"}}]}'
expect "custom started list replaces the default" allow none "$(start x)"
echo '{"waiting":{"cap":1,"maintainer":"LOGIN","repos":["ORG/a"],"started":"Ready"}}' > "$AGENTIC_CONFIG"
expect "bad started type" error none "$(start x)"
setup 1 0 0
blockers 1 1 OPEN > "$tmp/issues"
expect "blocker of an open issue" deny deny "$(start x)"
echo '[]' > "$tmp/issues"
reviews 1 1 Bot dependabot > "$tmp/prs"
expect "bot-typed review pr" allow none "$(start x)"
reviews 1 1 User 'some-app[bot]' > "$tmp/prs"
expect "[bot] login review pr" allow none "$(start x)"
reviews 1 1 User human > "$tmp/prs"
expect "human review pr" deny deny "$(start x)"
echo '[{"url":"https://example.test/ORG/r/pull/1","author":null}]' > "$tmp/prs"
expect "review pr, author gone" deny deny "$(start x)"

setup 3 5 5
for p in '**Priority:** fire' '**Priority: fire**' '- Priority: fire' '  Priority: fire' 'Priority: fire' '* **Priority:** FIRE' '> priority:  fire' '**Priority:** fire  <!-- why -->' '**Priority:** fire**'; do
  expect "fire form: $p" fire none "$(start "$(printf 'Brief\n%s\nmore' "$p")")"
done
expect "fire with CRLF" fire none "$(start "$(printf 'Brief\r\n**Priority:** fire\r\nmore\r\n')")"
expect "fire under a later heading" deny deny "$(start "$(printf 'Brief\n\n## Notes\n**Priority:** fire\n')")"
expect "fire before the first heading" fire none "$(start "$(printf '**Priority:** fire\n\n## Notes\nmore\n')")"
for p in 'Priority: fireworks' '**Priority:** P1 | P2 | P3 | fire: only for an outage' '**Priority:** fire | P1 | P2 | P3' 'Priority: fire now' 'the Priority: fire rule' 'Priority: P1'; do
  expect "no fire: $p" deny deny "$(start "$(printf 'Brief\n%s\nmore' "$p")")"
done

# De-duplication: the same URL twice counts once.
setup 4 0 0
echo '[{"url":"https://example.test/ORG/r/issues/1","blocking":{"nodes":[{"state":"OPEN","projectItems":{"nodes":[{"fieldValueByName":{"name":"In progress"}}]}}]}},{"url":"https://example.test/ORG/r/issues/1","blocking":{"nodes":[{"state":"OPEN","projectItems":{"nodes":[{"fieldValueByName":{"name":"In progress"}}]}}]}},{"url":"https://example.test/ORG/r/issues/2","blocking":{"nodes":[{"state":"OPEN","projectItems":{"nodes":[{"fieldValueByName":{"name":"In progress"}}]}}]}}]' > "$tmp/issues"
echo '[{"url":"https://example.test/ORG/r/pull/1","author":null},{"url":"https://example.test/ORG/r/pull/1","author":null}]' > "$tmp/prs"
expect "de-duplicated" allow none "$(start x)"
grep -q '"count": 3' "$log" || bad "de-duplication: want count 3"

# Paging: a first page that says hasNextPage, then a second page via after.
setup 3 0 0
blockers 1 1 OPEN > "$tmp/issues"; touch "$tmp/issues-more"
blockers 2 2 OPEN > "$tmp/issues-p2"
expect "second page counted" deny deny "$(start x)"
grep -q 'after=C' "$tmp/argv" || bad "paging: no after cursor"
grep -q '"count": 3' "$log" || bad "paging: want count 3"
grep -q truncated "$log" && bad "paging: not truncated"

# Paging that never ends stops at the page limit and says so.
setup 9 0 0
touch "$tmp/issues-more"; blockers 1 1 OPEN > "$tmp/issues"; cp "$tmp/issues" "$tmp/issues-p2"
touch "$tmp/issues-forever"
expect "paging stops at the limit" allow none "$(start x)"
grep -q '"note": "truncated"' "$log" || bad "truncation not logged"
[ "$(grep -c 'is:issue' "$tmp/argv")" = 5 ] || bad "want five pages: $(grep -c 'is:issue' "$tmp/argv")"

# The second search failing still allows (and says why).
setup 1 5 0
touch "$tmp/gh-fail-prs"
expect "pr search failing" error none "$(start x)"

# A deny is exactly one JSON object on stdout, exit 0, nothing on stderr.
setup 1 2 0
printf '%s' "$(start x)" | PATH=$hookpath python3 "$hook" > "$tmp/stdout" 2> "$tmp/stderr"; rc=$?
[ $rc = 0 ] || bad "deny exit code $rc"
[ ! -s "$tmp/stderr" ] || bad "deny wrote to stderr"
python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).read()); assert d["hookSpecificOutput"]["permissionDecision"]=="deny"; assert "2 items waiting on the maintainer" in d["hookSpecificOutput"]["permissionDecisionReason"]' "$tmp/stdout" || bad "deny output is not one JSON object"

# Per-track config: found through CLAUDE_PROJECT_DIR, else the input cwd; none: allow.
setup 1 2 0
mkdir -p "$tmp/proj/.claude" "$tmp/other"
cp "$AGENTIC_CONFIG" "$tmp/proj/.claude/agentic-workflows.json"
unset AGENTIC_CONFIG
cwdin() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"cwd":sys.argv[2],"tool_input":{"prompt":"x"}}))' "$T" "$1"; }
CLAUDE_PROJECT_DIR=$tmp/proj; export CLAUDE_PROJECT_DIR
expect "config via CLAUDE_PROJECT_DIR" deny deny "$(cwdin "$tmp/other")"
unset CLAUDE_PROJECT_DIR
expect "config via input cwd" deny deny "$(cwdin "$tmp/proj")"
expect "no config in a plain directory" not-configured none "$(cwdin "$tmp/other")"
expect "no config, no cwd" not-configured none "{\"tool_name\":\"$T\"}"
AGENTIC_CONFIG="$tmp/config.json"; export AGENTIC_CONFIG

setup 1 1 0
expect "legacy tool" deny deny "$(input mcp__ccd_session__spawn_task x)"

# Odd tool_input shapes are counted, not errors.
setup 1 1 0
for ti in '' ',"tool_input":null' ',"tool_input":"text"' ',"tool_input":[]' ',"tool_input":{}'; do
  expect "tool_input [$ti]" deny deny "{\"tool_name\":\"$T\"$ti}"
done
setup 1 1 0
expect "prompt not a string" deny deny "{\"tool_name\":\"$T\",\"tool_input\":{\"prompt\":null}}"

setup 1 5 0
rm "$AGENTIC_CONFIG"
expect "no config" not-configured none "$(start x)"
echo '{"waiting":{"cap":"many"}}' > "$AGENTIC_CONFIG"
expect "bad cap type" error none "$(start x)"
echo '{"waiting":{"cap":101,"maintainer":"LOGIN","repos":["ORG/a"]}}' > "$AGENTIC_CONFIG"
expect "cap above search limit" error none "$(start x)"
echo '{"waiting":{"cap":1,"maintainer":"LOGIN","repos":["ORG"]}}' > "$AGENTIC_CONFIG"
expect "repo without owner" error none "$(start x)"
echo '{"waiting":{"cap":1,"maintainer":"LOGIN","owners":["ORG"]}}' > "$AGENTIC_CONFIG"
expect "old owners shape" error none "$(start x)"
echo 'not json' > "$AGENTIC_CONFIG"
expect "bad config file" error none "$(start x)"

setup 1 5 0
touch "$tmp/gh-fail"
expect "gh failing" error none "$(start x)"

setup 1 5 0
hookpath=$tmp/nogh
expect "gh missing" error none "$(start x)"
hookpath=$PATH
unset CLAUDE_PROJECT_DIR

setup 1 5 0
touch "$tmp/gh-slow"
AGENTIC_START_TIMEOUT=1 expect "gh too slow" error none "$(start x)"
grep -q 'TimeoutExpired' "$log" || bad "timeout not logged"

# The time budget is shared by all pages: no single call is slow, the total is.
# Page one is quick; each later page takes a second; the budget is two seconds.
setup 9 0 0
touch "$tmp/issues-more" "$tmp/issues-forever" "$tmp/gh-slow-later"
blockers 1 1 OPEN > "$tmp/issues"; cp "$tmp/issues" "$tmp/issues-p2"
t0=$(date +%s)
AGENTIC_START_TIMEOUT=2 expect "shared budget across pages" error none "$(start x)"
t1=$(date +%s)
[ $((t1 - t0)) -le 3 ] || bad "shared budget: took $((t1 - t0))s, want about 2s"
grep -q 'Timeout' "$log" || bad "shared budget: timeout not logged"
[ "$(grep -c 'is:issue' "$tmp/argv")" -lt 5 ] || bad "shared budget: all five pages were fetched"

# A GraphQL errors body with exit 0 is an error, and the start is allowed.
setup 1 5 0
touch "$tmp/gh-errors"
expect "graphql errors body" error none "$(start x)"
grep -q 'returned errors' "$log" || bad "graphql errors not logged"

[ $fail = 0 ] && echo "start-check: ok"
exit $fail
