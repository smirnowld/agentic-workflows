#!/bin/sh
# board-set with a fake gh: payloads, validation, batching and error exits.
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../bin/board-set"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export CALLS="$tmp/calls"
cat > "$tmp/bin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
assert sys.argv[1:] == ['api', 'graphql', '--input', '-']
p = json.load(sys.stdin)
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps(p) + '\n')
q, v = p['query'], p['variables']
mode = os.environ.get('ERROR')
if mode == 'nonobject':
    print('[]')
    sys.exit(0)
if q.startswith('mutation') and mode in ('transport', 'unreadable', 'mutation-nonobject'):
    print('[]' if mode == 'mutation-nonobject' else 'broken')
    print('unexpected end of JSON input', file=sys.stderr)
    sys.exit(1 if mode == 'transport' else 0)
if mode == 'read' or (q.startswith('mutation') and mode == 'write'):
    print(json.dumps({'errors': [{'message': 'request denied'}], 'data': None}))
    sys.exit(1)
if 'fields(first: 50)' in q:
    if os.environ.get('NO_PROJECT'):
        print(json.dumps({'errors': [{'message': 'Could not resolve to a ProjectV2 with the number of 1'}]}))
        sys.exit(1)
    if os.environ.get('USER_OWNER') and 'organization(' in q:
        print(json.dumps({'errors': [{'message': 'Could not resolve to an Organization'}]}))
        sys.exit(1)
    kind = 'user' if 'user(' in q else 'organization'
    fields = [dict(id='select', name='Status', dataType='SINGLE_SELECT',
                   options=[dict(id='ready', name='Ready'), dict(id='doing', name='In progress')])]
    fields += [dict(id=k.lower(), name=k.title(), dataType=k) for k in ('TEXT', 'NUMBER', 'DATE', 'ITERATION')]
    print(json.dumps({'data': {kind: {'projectV2': {'id': 'project', 'fields': {'nodes': fields}}}}}))
elif 'resource(url:' in q or 'nodes(ids:' in q:
    if mode == 'lookup-null':
        print(json.dumps({'data': None, 'errors': [{'message': 'lookup denied'}]}))
        sys.exit(1)
    data = {}
    if 'ids' in v:
        assert len(v['ids']) <= 100
        data['nodes'] = [None if item == 'PVTI_unknown' else {'id': item} if item == 'PVTI_notitem' else
                         dict(id=item, project={'id': 'other' if item == 'PVTI_other' else 'project'})
                         for item in v['ids']]
    for key, url in v.items():
        if key == 'ids':
            continue
        i = key.removeprefix('url')
        assert url not in q
        assert ('u%s: resource(url: $url%s)' % (i, i)) in q
        nodes = [] if url.endswith('/999') else [dict(id='PVTI_other', project={'id': 'other'}),
                                                dict(id='PVTI_url' + i, project={'id': 'project'})]
        data['u' + i] = {'projectItems': {'nodes': nodes}}
    if 'PVTI_missing' in v.get('ids', []):
        i = v['ids'].index('PVTI_missing')
        data['nodes'][i] = None
        print(json.dumps({'data': data, 'errors': [{'message': 'Could not resolve to a node', 'path': ['nodes', i]}]}))
        sys.exit(1)
    errors = []
    if mode == 'lookup-id-error':
        data['nodes'][0] = None
        errors = [{'message': 'lookup denied', 'path': ['nodes', 0]}]
    if mode == 'lookup-url-error':
        data['u0'] = None
        errors = [{'message': 'lookup denied', 'path': ['u0']}]
    if mode == 'lookup-id-present-error':
        errors = [{'message': 'lookup denied', 'path': ['nodes', 0, 'project']}]
    if mode == 'lookup-url-present-error':
        errors = [{'message': 'lookup denied', 'path': ['u0', 'projectItems']}]
    if mode == 'lookup-missing-nodes':
        del data['nodes']
    if mode == 'lookup-missing-alias':
        del data['u0']
    if mode == 'lookup-missing-url-nodes':
        del data['u0']['projectItems']['nodes']
    print(json.dumps({'data': data, 'errors': errors}))
else:
    assert q.startswith('mutation(')
    n = sum(k.startswith('item') for k in v)
    assert 1 <= n <= 50 and q.count('updateProjectV2ItemFieldValue(') == n
    assert v['project'] == 'project'
    for i in range(n):
        assert v['item%d' % i].startswith('PVTI_')
        assert isinstance(v['value%d' % i], dict)
        assert ('m%d: updateProjectV2ItemFieldValue' % i) in q
    data = {'m%d' % i: {'projectV2Item': {'id': v['item%d' % i]}} for i in range(n)}
    if mode in ('partial', 'partial-missing'):
        data['m1'] = None
        if mode == 'partial-missing':
            del data['m1']
        print(json.dumps({'data': data, 'errors': [{'message': 'item denied', 'path': ['m1']}]}))
        sys.exit(1)
    if mode == 'mutation-null-path':
        print(json.dumps({'data': None, 'errors': [{'message': 'item denied', 'path': ['m0']}]}))
        sys.exit(1)
    if mode == 'mutation-pathless':
        print(json.dumps({'data': data, 'errors': [{'message': 'request denied'}]}))
        sys.exit(1)
    if mode == 'mutation-missing-alias':
        del data['m1']
    if mode == 'mutation-null-alias':
        data['m1'] = None
    if mode in ('mutation-data-list', 'mutation-data-string'):
        print(json.dumps({'data': [] if mode.endswith('list') else 'bad',
                          'errors': [{'message': 'item denied', 'path': ['m0']}]}))
        sys.exit(1)
    if mode in ('mutation-error-string', 'mutation-error-null'):
        print(json.dumps({'data': data, 'errors': ['bad' if mode.endswith('string') else None]}))
        sys.exit(1)
    print(json.dumps({'data': data}))
PY
chmod +x "$tmp/bin/gh"
PATH="$tmp/bin:$PATH"
export PATH
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got $3, wanted $2)"; fail=1; fi; }
run() {
    : > "$CALLS"
    python3 "$tool" owner 1 "$@" < /dev/null > "$tmp/out" 2> "$tmp/err"
    rc=$?
}
counts() {
    n=$(python3 -c 'import json,os; p=[json.loads(l) for l in open(os.environ["CALLS"])]; print(sum(x["query"].startswith("mutation(") for x in p))')
    check "$1 mutations" "$2" "$n"
    n=$(wc -l < "$CALLS" | tr -d ' ')
    check "$1 calls" "$3" "$n"
}
run --field sTaTuS PVTI_a=rEaDy
check 'by ID and case matching' 0 "$rc"
counts 'one ID' 1 3
grep -qx 'PVTI_a -> rEaDy' "$tmp/out"; check 'output line' 0 $?
python3 -c 'import json,os; p=json.loads(open(os.environ["CALLS"]).readlines()[-1]); assert p["variables"]["value0"]=={"singleSelectOptionId":"ready"}'
check 'option ID in payload' 0 $?
run https://github.com/o/r/issues/1=Ready https://github.com/o/r/pull/2=Ready
check 'issue and pull URLs' 0 "$rc"
counts 'URLs' 1 3
python3 -c 'import json,os; p=[json.loads(l) for l in open(os.environ["CALLS"])]; assert p[2]["variables"]["item0"]=="PVTI_url0"; assert p[2]["variables"]["item1"]=="PVTI_url1"; assert p[1]["query"].count("resource(url:")==2'
check 'one aliased URL lookup selects this project' 0 $?
: > "$CALLS"
printf '\n# skip\nPVTI_a In progress\nPVTI_b Ready\n' | python3 "$tool" owner 1 > "$tmp/out" 2> "$tmp/err"
check 'stdin values with spaces' 0 $?
counts 'stdin' 1 3
grep -qx 'PVTI_a -> In progress' "$tmp/out"; check 'stdin output' 0 $?
: > "$CALLS"
printf 'PVTI_a trailing spaces  \n' | python3 "$tool" owner 1 --field Text > "$tmp/out" 2> "$tmp/err"
check 'stdin text preserves trailing spaces' 0 $?
python3 -c 'import json,os; p=json.loads(open(os.environ["CALLS"]).readlines()[-1]); assert p["variables"]["value0"]=={"text":"trailing spaces  "}'
check 'stdin rest of line in payload' 0 $?
run --field Missing PVTI_a=Ready
check 'unknown field' 2 "$rc"; counts 'unknown field' 0 1
run PVTI_a=Ready PVTI_b=Missing
check 'unknown option validates full batch' 2 "$rc"; counts 'unknown option' 0 1
run PVTI_a=Ready https://github.com/o/r/issues/999=Ready
check 'URL absent from board' 2 "$rc"; counts 'absent URL' 0 2
grep -q 'https://github.com/o/r/issues/999' "$tmp/err"; check 'absent URL named' 0 $?
run --dry-run https://github.com/o/r/issues/1=Ready
check 'dry run resolves URL' 0 "$rc"; counts 'dry run' 0 2
grep -qx 'would set https://github.com/o/r/issues/1 -> Ready' "$tmp/out"; check 'dry run prints action' 0 $?
set --
i=0
while [ "$i" -lt 20 ]; do set -- "$@" "PVTI_$i=$(if [ $(((i + i / 50) % 2)) -eq 0 ]; then echo Ready; else echo 'In progress'; fi)"; i=$((i+1)); done
run "$@"
check 'twenty items' 0 "$rc"; counts 'twenty items' 1 3
while [ "$i" -lt 60 ]; do set -- "$@" "PVTI_$i=$(if [ $(((i + i / 50) % 2)) -eq 0 ]; then echo Ready; else echo 'In progress'; fi)"; i=$((i+1)); done
run "$@"
check 'sixty items' 0 "$rc"; counts 'sixty items' 2 4
n=$(wc -l < "$tmp/out" | tr -d ' '); check 'sixty output lines' 60 "$n"
python3 - <<'PYTEST'
import json, os
calls = [json.loads(line) for line in open(os.environ['CALLS'])]
chunks = [p for p in calls if p['query'].startswith('mutation(')]
for chunk_index, p in enumerate(chunks):
    v = p['variables']
    for i in range(50 if chunk_index == 0 else 10):
        item = chunk_index * 50 + i
        assert v['item%d' % i] == 'PVTI_%d' % item
        assert v['value%d' % i] == {'singleSelectOptionId': 'ready' if (item + item // 50) % 2 == 0 else 'doing'}
PYTEST
check 'each chunk keeps each item value' 0 $?
ERROR=partial; export ERROR
run "$@"
check 'partial mutation exits 1' 1 "$rc"; counts 'partial stops later chunks' 1 3
n=$(wc -l < "$tmp/out" | tr -d ' '); check 'partial successes' 49 "$n"
grep -qx 'PVTI_0 -> Ready' "$tmp/out"; check 'partial m0 success' 0 $?
grep -qx 'PVTI_2 -> Ready' "$tmp/out"; check 'partial m2 success' 0 $?
grep -qx 'board-set: not set: PVTI_1 -> In progress: item denied' "$tmp/err"; check 'partial failure mapped' 0 $?
grep -qx 'board-set: 10 items not attempted in later chunks' "$tmp/err"; check 'later chunk count' 0 $?
ERROR=write; export ERROR
run "$@"
check 'uncertain chunk exit' 1 "$rc"; counts 'uncertain stops later chunks' 1 3
grep -qx 'board-set: 10 items not attempted in later chunks' "$tmp/err"; check 'uncertain later chunk count' 0 $?
unset ERROR

for field in Text Number Date; do
    case "$field" in
        Text) value='words "quoted" $text = value' ;;
        Number) value='12.5' ;;
        Date) value='2026-04-30' ;;
    esac
    run --field "$field" "PVTI_a=$value"
    check "$field value" 0 "$rc"
    FIELD="$field" VALUE="$value" python3 - <<'PY'
import json, os
p = json.loads(open(os.environ['CALLS']).readlines()[-1])
k = os.environ['FIELD'].lower()
v = float(os.environ['VALUE']) if k == 'number' else os.environ['VALUE']
assert p['variables']['value0'] == {k: v}
assert os.environ['VALUE'] not in p['query']
PY
    check "$field variable payload" 0 $?
done
for value in nope NaN inf; do
    run --field Number "PVTI_a=$value"
    check 'invalid number' 2 "$rc"; counts 'invalid number' 0 1
done
for value in 2026-02-30 20260430; do
    run --field Date "PVTI_a=$value"
    check 'invalid date' 2 "$rc"; counts 'invalid date' 0 1
done
run --field Iteration PVTI_a=Ready
check 'unsupported field type' 2 "$rc"; counts 'unsupported type' 0 1
ERROR=write; export ERROR
run PVTI_a=Ready
check 'mutation GraphQL error' 1 "$rc"
grep -q 'request denied' "$tmp/err"; check 'GraphQL message printed' 0 $?
ERROR=read; export ERROR
run PVTI_a=Ready
check 'read GraphQL error' 1 "$rc"; counts 'read error' 0 1
unset ERROR
USER_OWNER=1; export USER_OWNER
run PVTI_a=Ready
check 'organization then user fallback' 0 "$rc"; counts 'user fallback' 1 4
unset USER_OWNER
run
check 'empty input' 2 "$rc"; counts 'empty input' 0 0
for item in PVTI_other PVTI_unknown PVTI_notitem PVTI_missing; do
    run PVTI_a=Ready "$item=Ready"
    check 'invalid board membership' 2 "$rc"; counts 'membership' 0 2
    grep -q "$item" "$tmp/err"; check 'invalid ID named' 0 $?
done
for ERROR in lookup-null lookup-id-error lookup-id-present-error lookup-missing-nodes; do
    export ERROR
    run PVTI_a=Ready
    check "$ERROR exit" 1 "$rc"; counts "$ERROR" 0 2
    grep -q 'not on this board\|Traceback' "$tmp/err"; check "$ERROR clean read failure" 1 $?
    if [ "$ERROR" != lookup-missing-nodes ]; then
        grep -q 'lookup denied' "$tmp/err"; check "$ERROR GraphQL message" 0 $?
    fi
done
for ERROR in lookup-url-error lookup-url-present-error lookup-missing-alias lookup-missing-url-nodes; do
    export ERROR
    run https://github.com/o/r/issues/1=Ready
    check "$ERROR exit" 1 "$rc"; counts "$ERROR" 0 2
    grep -q 'not on this board\|Traceback' "$tmp/err"; check "$ERROR clean read failure" 1 $?
    case "$ERROR" in
        *error) grep -q 'lookup denied' "$tmp/err"; check "$ERROR GraphQL message" 0 $? ;;
    esac
done
unset ERROR
run PVTI_a=Ready PVTI_a=Ready
check 'duplicate item' 2 "$rc"; counts 'duplicate item' 0 0
run PVTI_url0=Ready https://github.com/o/r/issues/1=Ready
check 'duplicate resolved item' 2 "$rc"; counts 'resolved duplicate' 0 2
NO_PROJECT=1; export NO_PROJECT
run PVTI_a=Ready
check 'existing organization missing project' 2 "$rc"; counts 'missing project no fallback' 0 1
grep -qx 'board-set: no such project owner/1' "$tmp/err"; check 'missing project message' 0 $?
unset NO_PROJECT
ERROR=nonobject; export ERROR
run PVTI_a=Ready
check 'nonobject read' 2 "$rc"
grep -qx 'board-set: unreadable answer from gh' "$tmp/err"; check 'clean nonobject error' 0 $?
for ERROR in transport unreadable mutation-nonobject write mutation-null-path mutation-pathless mutation-data-list mutation-data-string mutation-error-string mutation-error-null; do
    export ERROR
    run PVTI_a=Ready PVTI_b=Ready
    check 'uncertain mutation exit' 1 "$rc"
    grep -q 'writes for this chunk may or may not have happened' "$tmp/err"; check 'uncertain writes warning' 0 $?
    grep -qx 'board-set: PVTI_a -> Ready' "$tmp/err"; check 'uncertain first item' 0 $?
    grep -qx 'board-set: PVTI_b -> Ready' "$tmp/err"; check 'uncertain second item' 0 $?
    grep -q 'not set:\|Traceback\|0 items not attempted' "$tmp/err"; check "$ERROR clean uncertainty" 1 $?
    check "$ERROR no claimed successes" 0 "$(wc -l < "$tmp/out" | tr -d ' ')"
done
for ERROR in mutation-missing-alias mutation-null-alias; do
    export ERROR
    run PVTI_a=Ready PVTI_b=Ready
    check "$ERROR exit" 1 "$rc"
    grep -qx 'PVTI_a -> Ready' "$tmp/out"; check "$ERROR known success" 0 $?
    grep -qx 'board-set: writes for this chunk may or may not have happened:' "$tmp/err"; check "$ERROR uncertain warning" 0 $?
    grep -qx 'board-set: PVTI_b -> Ready' "$tmp/err"; check "$ERROR uncertain item" 0 $?
    grep -q 'board-set: PVTI_a\|not set:\|Traceback\|0 items not attempted' "$tmp/err"; check "$ERROR only uncertain item" 1 $?
done
for ERROR in partial partial-missing; do
    export ERROR
    run PVTI_a=Ready PVTI_b=Ready
    check "$ERROR last chunk exit" 1 "$rc"
    grep -qx 'board-set: not set: PVTI_b -> Ready: item denied' "$tmp/err"; check "$ERROR named failure" 0 $?
    grep -q 'items not attempted\|may or may not' "$tmp/err"; check "$ERROR no later count or uncertainty" 1 $?
done
unset ERROR
: > "$CALLS"
printf 'PVTI_a   leading and trailing  \n' | python3 "$tool" owner 1 --field Text > "$tmp/out" 2> "$tmp/err"
check 'stdin preserves value whitespace' 0 $?
python3 -c 'import json,os; p=json.loads(open(os.environ["CALLS"]).readlines()[-1]); assert p["variables"]["value0"]=={"text":"  leading and trailing  "}'
check 'single stdin separator consumed' 0 $?
set --
i=0
while [ "$i" -lt 101 ]; do set -- "$@" "PVTI_$i=Ready"; i=$((i+1)); done
run "$@"
check 'ID validation chunks' 0 "$rc"; counts 'ID chunks' 3 6
python3 -c 'import json,os; p=[json.loads(l) for l in open(os.environ["CALLS"])]; assert [len(x["variables"]["ids"]) for x in p if "ids" in x["variables"]]==[100,1]'
check 'ID reads at most 100' 0 $?
run invalid=Ready
check 'invalid item' 2 "$rc"; counts 'invalid item' 0 0
exit "$fail"
