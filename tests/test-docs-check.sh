#!/bin/sh
# docs-check: touched (docs changed, not changed, reason given, empty reason)
# and budget (under, over), in temporary git repositories.
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/../bin/docs-check"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { # check NAME EXPECTED_EXIT ACTUAL_EXIT
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (exit $3, wanted $2)"; fail=1; fi
}
cd "$tmp" || exit 1
git init -q . && git config user.email t@t && git config commit.gpgsign false && git config user.name t
mkdir docs src
echo code > src/a.c; echo hi > README.md; echo one > docs/x.md
git add -A && git commit -qm base && base=$(git rev-parse HEAD)

echo more >> src/a.c; git commit -qam code
PR_BODY= python3 "$tool" touched --base "$base" 2> err; check "code only fails" 1 $?
grep -q "No docs change:" err && grep -q "documentation file" err; check "failure names both ways" 0 $?
PR_BODY="text
No docs change: internal refactor" python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "reason given passes" 0 $?
PR_BODY="No docs change:   " python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "empty reason fails" 1 $?
PR_BODY="<!-- No docs change: x -->" python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "commented line fails" 1 $?
echo more >> docs/x.md; git commit -qam docs
PR_BODY= python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "docs file changed passes" 0 $?

main=$(git rev-parse --abbrev-ref HEAD)
# nested docs path, custom globs, deleted docs file, non-ASCII path
git checkout -q "$base"; git checkout -q -b n1
mkdir -p skills/x; echo s > skills/x/SKILL.md; git add -A; git commit -qm n
PR_BODY= python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "nested .md passes" 0 $?
PR_BODY= python3 "$tool" touched --base "$base" --globs 'src/*' >/dev/null 2>&1; check "custom globs replace the defaults" 1 $?
git checkout -q "$base"; git checkout -q -b n2
git rm -q docs/x.md; git commit -qm del
PR_BODY= python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "deleted docs file passes" 0 $?
git checkout -q "$base"; git checkout -q -b n3
echo c > src/b.c; git add -A; git commit -qm c
PR_BODY= python3 "$tool" touched --base "$base" --globs 'src/b.c' >/dev/null 2>&1; check "--globs matches given glob" 0 $?
PR_BODY= python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "same change fails with default globs" 1 $?
git checkout -q "$base"; git checkout -q -b n4
echo d > "docs/caf\303\251.md"; git add -A; git commit -qm u
PR_BODY= python3 "$tool" touched --base "$base" >/dev/null 2>&1; check "non-ASCII docs path passes" 0 $?
git checkout -q "$main"
printf '{"globs": ["*.md", "docs/**"], "max_lines": 100}\n' > b.json
python3 "$tool" budget --file b.json >/dev/null 2>&1; check "budget under passes" 0 $?
i=0; while [ $i -lt 120 ]; do echo line; i=$((i+1)); done > docs/big.md
git add -A && git commit -qm big
python3 "$tool" budget --file b.json > /dev/null 2> err; check "budget over fails" 1 $?
grep -q "docs/big.md" err && grep -q "limit 100" err; check "budget lists total and largest" 0 $?
python3 "$tool" budget --file missing.json >/dev/null 2>&1; check "missing budget file is an error" 2 $?
exit "$fail"
