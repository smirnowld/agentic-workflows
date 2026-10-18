#!/bin/sh
# Self-test for wait-for against a fake gh; touches no repository. Each case
# queues the answers gh gives, one per call, the last one repeating, and
# checks the exit code and the final line.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/wait-for"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/bin" "$dir/q"
# Fake gh: picks a queue by the command, pops its next answer (JSON, !ERR for a
# gh error, !EMPTY for no output) and applies the --jq filter as gh would.
cat > "$dir/bin/gh" <<FAKE
#!/bin/sh
q="$dir/q"
case "\$*" in
  'run watch'*) key=watch ;;
  'run view'*) key=runview ;;
  *baseRefName*) key=base ;;
  'pr view'*) key=pr ;;
  *rules/branches*) key=rules ;;
  *actions/runs*) key=actionruns ;;
  *check-runs*) key=checkruns ;;
  *) echo "fake gh: unexpected \$*" >&2; exit 99 ;;
esac
echo "\$key GH_REPO=\${GH_REPO:-}" >> "$dir/calls"
f="\$q/\$key"
[ -f "\$f" ] || { echo "fake gh: no queue \$key" >&2; exit 98; }
line=\$(head -n 1 "\$f")
[ "\$(wc -l < "\$f")" -le 1 ] || { tail -n +2 "\$f" > "\$f.t"; mv "\$f.t" "\$f"; }
if [ "\$key" = watch ]; then sleep "\${line% *}"; exit "\${line#* }"; fi
case \$line in '!ERR') exit 1 ;; '!EMPTY') exit 0 ;; esac
jqf=; while [ \$# -gt 0 ]; do [ "\$1" = --jq ] && jqf=\$2; shift; done
printf '%s\n' "\$line" | jq -r "\${jqf:-.}"
FAKE
chmod +x "$dir/bin/gh"
PATH="$dir/bin:$PATH"; export PATH
WAIT_FOR_POLL=0; export WAIT_FOR_POLL

pr() { printf '{"state":"%s","headRefOid":"%s","mergeable":"%s","autoMergeRequest":%s}\n' "$@"; }
open=$(pr OPEN aaa MERGEABLE '{"mergeMethod":"SQUASH"}')
rules='[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"check","integration_id":15368}]}}]'
runs='{"check_runs":[{"name":"check","details_url":"https://github.com/o/r/actions/runs/77/job/1"}]}'
# Workflow runs on the head: none, one still going, all completed.
noruns='{"total_count":0,"workflow_runs":[]}'
active='{"total_count":2,"workflow_runs":[{"status":"in_progress"},{"status":"completed"}]}'
done='{"total_count":1,"workflow_runs":[{"status":"completed"}]}'
# queue KEY ANSWER...: what gh answers for KEY, in order.
queue() { k=$1; shift; printf '%s\n' "$@" > "$dir/q/$k"; }
reset() { rm -f "$dir/q/"* "$dir/calls"; queue base '{"baseRefName":"main"}'; queue rules "$rules"; }
# grace0 CMD...: run CMD with no grace period; a subshell, because a shell may
# keep a variable set in front of a function call (macOS sh does).
grace0() { ( WAIT_FOR_GRACE=0; export WAIT_FOR_GRACE; "$@" ); }
# expect CODE LINE_PREFIX ARGS...
expect() {
  want=$1 prefix=$2; shift 2
  # A wait that never ends fails the test instead of hanging it.
  "$tool" "$@" >"$dir/out" 2>"$dir/err" & pid=$!
  ( sleep 20 & s=$!; trap 'kill $s; exit' TERM; wait $s; kill "$pid" ) 2>/dev/null & dog=$!
  set +e; wait "$pid"; got=$?; set -e
  { kill "$dog"; wait "$dog"; } 2>/dev/null || true
  out=$(cat "$dir/out")
  [ "$got" = "$want" ] || { echo "error: wait-for $* exited $got, want $want: $out" >&2; cat "$dir/err" >&2; exit 1; }
  case $out in "$prefix"*) ;; *) echo "error: wait-for $* printed '$out', want '$prefix...'" >&2; exit 1 ;; esac
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] || { echo "error: more than one line: $out" >&2; exit 1; }
}

# 0: CI passes on the head; the run's own conclusion decides, not watch's exit.
reset; queue pr "$open"; queue checkruns "$runs"; queue watch '0 0'
queue runview '{"status":"completed","conclusion":"success"}'
expect 0 'passed: CI on PR 5 at aaa' pr-ci 5
# A run not yet started is waited for, then watched.
reset; queue pr "$open"; queue checkruns '{"check_runs":[]}' "$runs"; queue watch '0 0'
queue runview '{"status":"completed","conclusion":"success"}'
expect 0 'passed:' pr-ci 5
# Past the grace period, a check created only after other jobs is waited for
# while a workflow run on the head is still going; a lag after they all
# completed is waited out once.
reset; queue pr "$open"; queue checkruns '{"check_runs":[]}' '{"check_runs":[]}' '{"check_runs":[]}' "$runs"
queue actionruns "$active" "$active" "$done"; queue watch '0 0'
queue runview '{"status":"completed","conclusion":"success"}'
grace0 expect 0 'passed: CI on PR 5 at aaa (runs 77)' pr-ci 5
[ "$(grep -c '^actionruns' "$dir/calls")" -eq 3 ]
# 0: merged, and the run form.
reset; queue pr "$open" "$open" "$(pr MERGED aaa UNKNOWN null)"
expect 0 'merged: PR 5' pr-merged 5
reset; queue watch '0 0'; queue runview '{"status":"completed","conclusion":"success"}'
expect 0 'passed: run 77' run 77

# 1: a failed run, even if watch exited 0; a cancelled one too.
reset; queue pr "$open"; queue checkruns "$runs"; queue watch '0 0'
queue runview '{"status":"completed","conclusion":"failure"}'
expect 1 'failed: run 77 ended failure' pr-ci 5
reset; queue watch '0 1'; queue runview '{"status":"completed","conclusion":"cancelled"}'
expect 1 'failed: run 77 ended cancelled' run 77

# 2: closed without merging.
reset; queue pr "$open" "$(pr CLOSED aaa UNKNOWN null)"
expect 2 'closed:' pr-merged 5

# 3: head moved while the run is watched; auto-merge turned off; head moved
# before the merge.
reset; queue pr "$open" "$open" "$(pr OPEN bbb MERGEABLE null)"; queue checkruns "$runs"; queue watch '5 0'
expect 3 'moved: PR 5 head is now bbb' pr-ci 5
reset; queue pr "$open" "$open" "$(pr OPEN aaa MERGEABLE null)"
expect 3 'moved: auto-merge' pr-merged 5
reset; queue pr "$open" "$(pr OPEN ccc MERGEABLE '{"mergeMethod":"SQUASH"}')"
expect 3 'moved: PR 5 head is now ccc' pr-merged 5
# A PR without auto-merge at the start is waited on (merged by hand).
reset; queue pr "$(pr OPEN aaa MERGEABLE null)" "$(pr OPEN aaa MERGEABLE null)" "$(pr MERGED aaa UNKNOWN null)"
expect 0 'merged:' pr-merged 5

# pr-ci: merged at another head than the one waited on; a short answer.
reset; queue pr "$open" "$(pr MERGED zzz UNKNOWN null)"; queue checkruns '{"check_runs":[]}'
expect 3 'moved: PR 5 merged at zzz' pr-ci 5
reset; queue pr '{"state":"OPEN","headRefOid":"","mergeable":"","autoMergeRequest":null}'
expect 5 'unknown: PR 5 answered' pr-merged 5
reset; queue watch '0 0'; queue runview '{"status":"","conclusion":""}'
expect 5 'unknown:' run 77

# 4: a conflict while no run starts, and while waiting on the merge.
reset; queue pr "$open" "$(pr OPEN aaa CONFLICTING '{"mergeMethod":"SQUASH"}')"; queue checkruns '{"check_runs":[]}'
expect 4 'conflict:' pr-ci 5
reset; queue pr "$open" "$(pr OPEN aaa CONFLICTING '{"mergeMethod":"SQUASH"}')"
expect 4 'conflict:' pr-merged 5

# 5: empty output, null fields and gh errors twice in a row; once is retried.
reset; queue pr '!EMPTY'
expect 5 'unknown:' pr-merged 5
reset; queue pr "$(pr OPEN null UNKNOWN null)"
expect 5 'unknown:' pr-merged 5
reset; queue pr '{"state":null,"headRefOid":null,"mergeable":null,"autoMergeRequest":null}'
expect 5 'unknown:' pr-merged 5
reset; queue pr '!ERR'
expect 5 'unknown:' pr-ci 5
reset; queue pr '!ERR' "$open" "$open" "$(pr MERGED aaa UNKNOWN null)"
expect 0 'merged:' pr-merged 5
reset; queue pr "$open" "$open" '!ERR' '!EMPTY'
expect 5 'unknown:' pr-merged 5
reset; queue pr "$open"; queue checkruns '!ERR'
expect 5 'unknown: cannot read check runs' pr-ci 5
# No required Actions check, a check run outside Actions, a run that never
# starts, a run view that cannot be read, and a watcher that keeps dying.
reset; queue pr "$open"; queue rules '[]'
expect 5 'unknown: main requires no' pr-ci 5
reset; queue pr "$open"; queue checkruns '{"check_runs":[{"name":"check","details_url":"https://ci.example/1"}]}'
expect 5 'unknown: check check on aaa has no Actions run' pr-ci 5
reset; queue pr "$open"; queue checkruns '{"check_runs":[]}'; queue actionruns "$noruns"
grace0 expect 5 'unknown: no run for check check on aaa after 0 min; CI did not start' pr-ci 5
# Workflow runs on the head all completed, twice, and the check never came;
# a run still going in between restarts the count.
reset; queue pr "$open"; queue checkruns '{"check_runs":[]}'; queue actionruns "$done" "$active" "$done" "$done"
grace0 expect 5 'unknown: workflow runs on aaa completed without check check' pr-ci 5
[ "$(grep -c '^actionruns' "$dir/calls")" -eq 4 ]
# Workflow runs on the head that cannot be read, twice.
reset; queue pr "$open"; queue checkruns '{"check_runs":[]}'; queue actionruns '!ERR'
grace0 expect 5 'unknown: no readable answer from: gh api -X GET repos/{owner}/{repo}/actions/runs' pr-ci 5
reset; queue watch '0 0'; queue runview '!EMPTY'
expect 5 'unknown:' run 77
reset; queue watch '0 1'; queue runview '{"status":"in_progress","conclusion":""}'
expect 5 'unknown: gh run watch 77 ended twice' run 77

# 6: deadline reached with nothing decided.
reset; queue pr "$open"
expect 6 'deadline: PR 5 not merged' --deadline 0 pr-merged 5
reset; queue pr "$open"; queue checkruns '{"check_runs":[]}'
expect 6 'deadline: no run for check' --deadline 0 pr-ci 5
# Past the grace period the deadline still wins over "CI did not start".
reset; queue pr "$open"; queue checkruns '{"check_runs":[]}'; queue actionruns "$noruns"
grace0 expect 6 'deadline: no run for check' --deadline 0 pr-ci 5
reset; queue watch '5 0'
expect 6 'deadline: run 77' --deadline 0 run 77

# Usage errors, and -R reaches gh as GH_REPO.
expect 64 '' pr-ci
expect 64 '' pr-ci abc
expect 64 '' merge 5
reset; queue pr "$(pr MERGED aaa UNKNOWN null)"
expect 0 'merged:' -R o/r pr-merged 5
grep -qx 'pr GH_REPO=o/r' "$dir/calls"
echo "wait-for self-test passed"
