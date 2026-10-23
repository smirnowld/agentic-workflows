#!/bin/sh
# launch-check.py against sample hook inputs: decisions, output and log lines.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
hook="$root/hooks/launch-check.py"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
AGENTIC_LOG_DIR="$tmp/log"; CLAUDE_PLUGIN_ROOT="$root"; export AGENTIC_LOG_DIR CLAUDE_PLUGIN_ROOT
log="$tmp/log/launch-log.jsonl"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

mkdir -p "$tmp/track/lead" "$tmp/plain" "$tmp/log"
echo "# track" > "$tmp/track/track.md"; echo "lead" > "$tmp/track/lead/CLAUDE.md"

agent() {
  effort=medium
  case "$1" in
    *critical-reviewer-strongest) effort=xhigh ;;
    *critical-reviewer) effort=high ;;
    *explorer) effort=low ;;
  esac
  printf '{"session_id":"s1","cwd":"/w","tool_name":"Agent","tool_input":{"subagent_type":"%s","effort":"%s"%s}}' "$1" "$effort" "${2:+,\"model\":\"$2\"}" | python3 "$hook"
}
bash_in() { printf '{"session_id":"s1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" "$2" | python3 "$hook"; }
# bash_json CWD CMD: like bash_in, but the command may contain quotes.
bash_json() { python3 -c 'import json,sys; print(json.dumps({"session_id":"s1","cwd":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$1" "$2" | python3 "$hook"; }
# expect_agent NAME TYPE MODEL DECISION
expect_agent() {
  : > "$log"
  out=$(agent "$2" "$3" 2>&1)
  d=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read().strip().splitlines()[-1])["decision"])' < "$log" 2>/dev/null)
  [ "$d" = "$4" ] || bad "$1: logged decision '$d', want $4"
  case $4 in
    deny) printf '%s' "$out" | grep -q '"permissionDecision": "deny"' || bad "$1: no deny output" ;;
    *) [ -z "$out" ] || bad "$1: expected no output, got: $out" ;;
  esac
  [ "$(wc -l < "$log" | tr -d ' ')" = 1 ] || bad "$1: want exactly one log line"
}
expect_agent "implementer sonnet" agentic-workflows:implementer sonnet allow
expect_agent "prefixed implementer opus" agentic-workflows:implementer opus allow
expect_agent "implementer no model" agentic-workflows:implementer "" allow
expect_agent "bare implementer no model" implementer "" pass
expect_agent "bare implementer gpt" implementer gpt-6.1-sol pass
expect_agent "prefixed implementer no model, file model" agentic-workflows:implementer "" allow
expect_agent "prefixed unknown role" agentic-workflows:nope "" pass
expect_agent "implementer gpt" agentic-workflows:implementer gpt-6.1-sol deny
expect_agent "critical-reviewer opus" agentic-workflows:critical-reviewer opus allow
expect_agent "critical-reviewer sonnet" agentic-workflows:critical-reviewer sonnet deny
expect_agent "critical-reviewer-strongest fable" agentic-workflows:critical-reviewer-strongest fable allow
expect_agent "critical-reviewer-strongest opus" agentic-workflows:critical-reviewer-strongest opus deny
expect_agent "critical-reviewer-strongest no model, file model" agentic-workflows:critical-reviewer-strongest "" allow
expect_agent "reviewer no model, file model" agentic-workflows:reviewer "" allow
expect_agent "critical-reviewer no model, file model" agentic-workflows:critical-reviewer "" allow
expect_agent "strategist Agent has no Claude route" agentic-workflows:strategist fable pass
expect_agent "spec critic Agent has no Claude route" agentic-workflows:spec-critic sonnet pass
expect_agent "PM like lead is maintainer started" agentic-workflows:pm sonnet pass
expect_agent "lead is maintainer started" agentic-workflows:lead sonnet pass
expect_agent "explorer sonnet" agentic-workflows:explorer sonnet allow
expect_agent "unrouted" Explore "" pass
expect_agent "full model id" agentic-workflows:reviewer claude-sonnet-4-5 allow
# A deny names the primary model first (sonnet before opus for the implementer).
out=$(agent agentic-workflows:implementer gpt-6.1-sol 2>&1); case $out in *"on sonnet or opus"*"Set model to sonnet"*) ;; *) bad "deny message order: $out" ;; esac
# No model and no readable agent file: denied.
mkdir -p "$tmp/noagents"; cp "$root/routing.json" "$tmp/noagents/"
: > "$log"; out=$(CLAUDE_PLUGIN_ROOT="$tmp/noagents" agent agentic-workflows:reviewer "" 2>&1)
case $out in *'"permissionDecision": "deny"'*"names no model"*) ;; *) bad "unresolvable model not denied: $out" ;; esac

mkdir -p "$tmp/track/pm" "$tmp/plain/pm" "$tmp/plain/lead"
echo pm > "$tmp/track/pm/CLAUDE.md"; echo pm > "$tmp/plain/pm/CLAUDE.md"
: > "$log"
bash_in "$tmp/track/pm" "touch f"
grep -q '"decision": "pm-write"' "$log" && grep -q '"role": "pm"' "$log" || bad "PM write not logged"
: > "$log"
bash_in "$tmp/track/pm" "git status"
[ ! -s "$log" ] || bad "PM read logged as write"
bash_in "$tmp/plain/pm" "touch f"
[ ! -s "$log" ] || bad "PM without parent track logged"

# Role detection requires a role folder, its instructions and the parent track.
bash_in "$tmp/track" "touch f"
[ ! -s "$log" ] || bad "bare track root was logged"
echo root > "$tmp/track/CLAUDE.md"
bash_in "$tmp/track" "touch f"
[ ! -s "$log" ] || bad "track root with instructions was logged"
rm "$tmp/track/CLAUDE.md"
echo lead > "$tmp/plain/lead/CLAUDE.md"
bash_in "$tmp/plain/lead" "touch f"
[ ! -s "$log" ] || bad "lead without parent track logged"
rm "$tmp/track/lead/CLAUDE.md"
bash_in "$tmp/track/lead" "touch f"
[ ! -s "$log" ] || bad "lead without instructions logged"
echo lead > "$tmp/track/lead/CLAUDE.md"

# Bash: lead writes are logged and never blocked.
: > "$log"
out=$(bash_in "$tmp/track/lead" "git status | cat"); [ -z "$out" ] && [ ! -s "$log" ] || bad "read-only command was logged"
for c in 'echo x > f' 'echo x >> f' 'ls | tee f' 'sed -i s/a/b/ f' 'mv a b' 'cp a b' 'rm a' 'mkdir d' 'touch f' 'git commit -m x' 'git push' 'git apply p' 'git -C /x commit -m x' 'git -c a=b push' 'sed --in-place s/a/b/ f' 'echo hi > out.txt' 'rm -f a'; do
  : > "$log"
  out=$(bash_in "$tmp/track/lead" "$c")
  [ -z "$out" ] || bad "'$c' was blocked or printed: $out"
  grep -q '"decision": "lead-write"' "$log" && grep -q '"role": "lead"' "$log" || bad "'$c' not logged as a lead write"
done
: > "$log"
bash_in "$tmp/plain" "rm a"; [ ! -s "$log" ] || bad "write outside a track folder was logged"
: > "$log"
bash_in "$tmp/track/lead" "echo x 2>&1 | cat"; [ ! -s "$log" ] || bad "2>&1 counted as a write"

for c in 'echo x > /dev/null' 'ls 2> /dev/null | cat' 'echo "rm a > b"' "echo 'git commit'" 'git -C /x status' 'cat >> "$AGENTIC_RETRO_NOTES/2026-01-01.md" <<EOF' 'mkdir -p "$AGENTIC_RETRO_NOTES"'; do
  : > "$log"
  bash_json "$tmp/track/lead" "$c" >/dev/null
  [ ! -s "$log" ] || bad "'$c' wrongly logged as a lead write"
done
# Written as writes: sh -c arguments, commands after a heredoc with an apostrophe, .. escapes, git writes.
for c in 'bash -c "rm -rf x"' "sh -c 'echo x > f'" "zsh -c 'touch f'" 'cat <<EOF
it'"'"'s fine
EOF
rm a' 'cat <<-"END"
x
	END
touch f' 'cat >> "$AGENTIC_RETRO_NOTES/../x.md"' 'git tag v1' 'git stash' 'git stash pop' 'git checkout -- f'; do
  : > "$log"
  bash_json "$tmp/track/lead" "$c" >/dev/null
  grep -q '"decision": "lead-write"' "$log" && grep -q '"role": "lead"' "$log" || bad "'$c' not logged as a lead write"
done
# Reads: a heredoc body's text, read-only git forms.
for c in 'cat <<EOF
rm a > b
EOF' 'git tag' 'git tag -l' 'git tag --list "v*"' 'git stash list' 'git stash show' 'git -C /x tag -l'; do
  : > "$log"
  bash_json "$tmp/track/lead" "$c" >/dev/null
  [ ! -s "$log" ] || bad "'$c' wrongly logged as a lead write"
done
# Read destinations and listing options do not count; mutation flags still do.
for c in 'echo x > /dev/stdout' 'echo x >> /dev/null' 'echo x >> /dev/stdout' 'echo x 2>> /dev/tty' 'echo x >> /dev/fd/2' 'echo x >> /dev/stderr' 'echo x 2> /dev/tty' 'echo x > /dev/fd/12' 'git tag -n' 'git tag -n20' 'git tag --list v*' 'git tag -l v*' 'git tag --contains HEAD' 'git tag --points-at HEAD' 'git tag --contains=HEAD' 'git tag --points-at=HEAD' 'git tag --sort=-creatordate' 'git tag --sort -v:refname -l' 'git tag --format=%(refname)' 'git tag --merged main' 'git tag --no-contains HEAD' 'python3 - <<EOF
print("touch f")
EOF' 'cat sh <<EOF
touch f
EOF' "sh <<'SCRIPT'
cat <<'DATA'
touch f
DATA
SCRIPT"; do
  : > "$log"
  bash_json "$tmp/track/lead" "$c" >/dev/null
  [ ! -s "$log" ] || bad "'$c' wrongly logged as a lead write"
done
for c in "sed -i 'w public' /tmp/claude-session/input" 'sed -i -f public-script /tmp/claude-session/input' 'cp -t public /tmp/claude-session/source' 'cp --target-directory=public /tmp/claude-session/source' 'echo x > /dev/stdout.txt' 'echo x > /dev/fd/1x' 'git tag -d v1' 'git tag -f v1' 'git tag --sort=refname v9' 'git tag --format=x v8' 'git tag -i v7' 'git tag -l -d v1' 'true;git tag -l -d v1' 'sh <<EOF
touch f
EOF' "bash <<'EOF'
rm f
EOF" 'zsh -s <<EOF
echo x > f
EOF' 'dash <<EOF
git tag v1
EOF'; do
  : > "$log"
  bash_json "$tmp/track/lead" "$c" >/dev/null
  grep -q '"decision": "lead-write"' "$log" && grep -q '"role": "lead"' "$log" || bad "'$c' not logged as a lead write"
done
# Scratchpad and retro-note destinations: redirects and utility writes are private.
export AGENTIC_RETRO_NOTES="$tmp/notes" TMPDIR="$tmp/temp"
mkdir -p "$AGENTIC_RETRO_NOTES" "$TMPDIR"
for target in "$tmp/notes/n.md" '/private/tmp/claude-session/project/s1/scratchpad/n.md' "$TMPDIR/claude-session/project/s1/scratchpad/n.md"; do
  for c in "echo x > '$target'" "echo x >> $target" "tee '$target'" "touch '$target'" "mkdir -p '$target'" "cp input '$target'" "sed -i s/a/b/ '$target'" "sed -i '' s/a/b/ '$target'" "rm -f '$target'"; do
    : > "$log"
    bash_json "$tmp/track/lead" "$c" >/dev/null
    [ ! -s "$log" ] || bad "private target was counted: $c"
  done
  for c in "echo x > '$target/../escape'" "touch '$target/../escape'" "echo x > '$target'; touch outside"; do
    : > "$log"
    bash_json "$tmp/track/lead" "$c" >/dev/null
    grep -q '"decision": "lead-write"' "$log" || bad "outside write was missed: $c"
  done
done
: > "$log"
bash_json "$tmp/track/lead" "echo x > '$tmp/notes-other/n.md'" >/dev/null
grep -q '"decision": "lead-write"' "$log" || bad "retro sibling write was missed"

for c in 'touch /tmp/claude-session/project/other/scratchpad/n.md' 'rm -rf /tmp/claude-501' 'cp -rt REPO /tmp/claude-session/project/s1/scratchpad/n.md' 'cp --target=REPO /tmp/claude-session/project/s1/scratchpad/n.md' 'git rm /tmp/claude-session/project/s1/scratchpad/n.md' 'git mv source /tmp/claude-session/project/s1/scratchpad/n.md'; do
  : > "$log"
  bash_json "$tmp/track/lead" "$c" >/dev/null
  grep -q '"decision": "lead-write"' "$log" || bad "write was missed: $c"
done

# Agent effort precedence, missing values, kind parsing and per-kind route logging.
python3 - "$hook" "$log" <<'PYTEST' || bad "Agent metadata"
import json, subprocess, sys
hook, log = sys.argv[1:]
def launch(**ti):
    subprocess.run([sys.executable, hook], input=json.dumps({"tool_name":"Agent", "tool_input":ti}), text=True, capture_output=True, check=True)
    return json.loads(open(log).readlines()[-1])
e = launch(subagent_type="agentic-workflows:implementer", model="sonnet", effort="high")
assert (e["effort"], e["effort_from"], e["kind"]) == ("high", "input", None)
e = launch(subagent_type="agentic-workflows:implementer")
assert e["effort"] is None and e["effort_from"] is None and e["decision"] == "deny"
for st in ("Explore", "agentic-workflows:nope"):
    e = launch(subagent_type=st)
    assert e["effort"] is None and e["effort_from"] is None
e = launch(subagent_type="Explore", effort="low")
assert (e["effort"], e["effort_from"]) == ("low", "input")
for kind in ("trivial", "specified", "symptom-bug", "native-mobile"):
    for model in ("sonnet", "opus", "gpt-6.1-sol"):
        e = launch(subagent_type="agentic-workflows:implementer", model=model, effort="low" if kind == "trivial" and model == "sonnet" else "medium", description="  " + kind.upper() + " : do work")
        assert e["kind"] == kind
        assert e["route_ok"] == (model == "sonnet" or (model == "opus" and kind in ("symptom-bug", "native-mobile")))
        assert e["decision"] == ("allow" if model in ("sonnet", "opus") else "deny")
e = launch(subagent_type="agentic-workflows:implementer", model="sonnet", effort="medium", description="trivial: do work")
assert e["decision"] == "deny" and "Set effort to low on the Agent call." in e["reason"]
e = launch(subagent_type="agentic-workflows:implementer", effort="medium", description="specified: do work")
assert e["route_ok"] is True
for description in ("do specified: work", "unknown: work", ""):
    e = launch(subagent_type="agentic-workflows:implementer", effort="medium", description=description)
    assert e["kind"] is None and "route_ok" not in e and e["decision"] == "allow"
e = launch(subagent_type="agentic-workflows:reviewer", model="sonnet", effort="medium")
assert e["decision"] == "allow"
for effort in (None, "high", "medium"):
    ti = dict(subagent_type="agentic-workflows:critical-reviewer-strongest", model="fable")
    if effort is not None:
        ti["effort"] = effort
    e = launch(**ti)
    assert e["decision"] == "deny" and "Set effort to xhigh" in e["reason"]
for effort in (None, "low", "high"):
    e = launch(subagent_type="agentic-workflows:reviewer", model="sonnet", effort=effort)
    assert e["decision"] == "deny" and "Set effort to medium" in e["reason"]
PYTEST

# The command text never reaches the log.
: > "$log"
bash_in "$tmp/track/lead" "echo SECRETWORD > f" >/dev/null
[ -s "$log" ] && ! grep -q SECRETWORD "$log" || bad "command text in the log (or no entry)"

# Never fails closed: bad input and a broken routing.json allow and log "error".
: > "$log"
out=$(echo 'not json' | python3 "$hook" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && grep -q '"decision": "error"' "$log" || bad "bad input: rc=$rc out=$out"
mkdir "$tmp/badroot"; echo '{' > "$tmp/badroot/routing.json"; : > "$log"
out=$(CLAUDE_PLUGIN_ROOT="$tmp/badroot" agent implementer sonnet 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && grep -q '"decision": "error"' "$log" || bad "broken routing.json: rc=$rc out=$out"
[ "$fail" = 0 ] && echo "ok"
exit "$fail"
