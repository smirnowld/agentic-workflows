#!/bin/sh
# codex-run against a fake codex on PATH that records its arguments.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tool="$root/bin/codex-run"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/work"
cat > "$tmp/bin/codex" <<FAKE
#!/bin/sh
printf '%s\n' "\$@" > "$tmp/argv"
cat > "$tmp/stdin"
# find the -o file and write a final message there
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && echo "final message" > "\$2"; shift; done
[ -n "\${FAKE_CODEX_EVENTS:-}" ] && cat "\$FAKE_CODEX_EVENTS"
exit \${FAKE_CODEX_EXIT:-0}
FAKE
chmod +x "$tmp/bin/codex"
PATH="$tmp/bin:$PATH"; AGENTIC_LOG_DIR="$tmp/log"; CLAUDE_PLUGIN_ROOT="$root"; export PATH AGENTIC_LOG_DIR CLAUDE_PLUGIN_ROOT
echo "do the thing" > "$tmp/prompt"
fail=0
bad() { echo "FAIL: $*"; fail=1; }
argv() { tr '\n' ' ' < "$tmp/argv"; }

report=$("$tool" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" 2>/dev/null) || bad "specified primary failed"
echo "specified primary: $(argv)"
[ "$(argv)" = "exec --json -C $tmp/work -m gpt-6.1-sol -c model_reasoning_effort=\"medium\" -s workspace-write -o $report - " ] || bad "unexpected argv for specified primary"
[ "$(cat "$report")" = "final message" ] || bad "report file lacks the final message"
# The prompt codex receives: RULES.md, then the role body, then the brief.
body=$(awk 'f>=2{print} /^---$/{f++}' "$root/agents/implementer.md" | sed '1{/^$/d;}')
first=$(printf '%s\n' "$body" | head -n 1)
rules_first=$(head -n 1 "$root/RULES.md")
[ "$(head -n 1 "$tmp/stdin")" = "$rules_first" ] && [ -n "$rules_first" ] || bad "stdin does not start with RULES.md"
grep -q '^name: implementer$' "$tmp/stdin" && bad "frontmatter leaked into the prompt"
rules_last=$(grep -v '^[[:space:]]*$' "$root/RULES.md" | tail -n 1)
grep -qxF -- "$rules_last" "$tmp/stdin" || bad "RULES.md text missing from stdin"
rules_line=$(grep -nxF -- "$rules_last" "$tmp/stdin" | head -n 1 | cut -d: -f1)
body_line=$(grep -nxF -- "$first" "$tmp/stdin" | tail -n 1 | cut -d: -f1)
brief_line=$(grep -nx 'do the thing' "$tmp/stdin" | tail -n 1 | cut -d: -f1)
[ -n "$rules_line" ] && [ -n "$body_line" ] && [ "$rules_line" -lt "$body_line" ] && [ "$body_line" -lt "$brief_line" ] || bad "order is not RULES.md, role body, brief"
[ "$(tail -n 1 "$tmp/stdin")" = "do the thing" ] || bad "brief not at the end of stdin"
grep -q 'commit, push' "$tmp/stdin" || bad "implementer rules missing from stdin"

"$tool" --role implementer --kind trivial --fallback --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1 || bad "trivial fallback failed"
echo "trivial fallback: $(argv)"
case $(argv) in *"-m gpt-6.1-sol -c model_reasoning_effort=\"low\" -s workspace-write"*) ;; *) bad "trivial fallback argv" ;; esac

"$tool" --role critical-reviewer --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1 || bad "critical-reviewer failed"
echo "critical-reviewer: $(argv)"
case $(argv) in *"-m gpt-6.1-sol -c model_reasoning_effort=\"high\" -s read-only"*) ;; *) bad "critical-reviewer argv" ;; esac
grep -q 'RULES.md critical criteria' "$tmp/stdin" || bad "critical-reviewer body not prepended"

"$tool" --role critical-reviewer-strongest --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1 || bad "critical-reviewer-strongest failed"
echo "critical-reviewer-strongest: $(argv)"
case $(argv) in *"-m gpt-6-astra -c model_reasoning_effort=\"xhigh\" -s read-only"*) ;; *) bad "critical-reviewer-strongest argv" ;; esac
grep -q 'strongest critical reviewer' "$tmp/stdin" && grep -q 'RULES.md critical criteria' "$tmp/stdin" || bad "strongest body not prepended"

"$tool" --role spec-critic --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1 || bad "spec-critic failed"
case $(argv) in *"-m gpt-6.1-sol -c model_reasoning_effort=\"high\" -s read-only"*) ;; *) bad "spec-critic argv" ;; esac
grep -q 'Read one spec cold' "$tmp/stdin" || bad "spec-critic body missing"
grep -q '^name: spec-critic$' "$tmp/stdin" && bad "spec critic frontmatter in prompt"

# A route that is not codex: exit 2 and codex is not run.
rm -f "$tmp/argv"
"$tool" --role implementer --kind symptom-bug --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>"$tmp/err"; rc=$?
[ "$rc" = 2 ] && grep -q 'not codex' "$tmp/err" && [ ! -e "$tmp/argv" ] || bad "non-codex route: rc=$rc"
"$tool" --role implementer --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1; [ $? = 2 ] || bad "missing --kind should exit 2"
"$tool" --role reviewer --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1; [ $? = 2 ] || bad "claude-only role should exit 2"
"$tool" --role implementer --kind specified --cwd "$tmp/nope" --prompt-file "$tmp/prompt" >/dev/null 2>&1; [ $? = 2 ] || bad "missing cwd should exit 2"

# A missing or empty RULES.md: exit 2, codex not run, no launch logged.
mkdir "$tmp/plug" && cp -R "$root/bin" "$root/agents" "$root/routing.json" "$tmp/plug/"
rm -f "$tmp/argv"; rm -rf "$tmp/log2"
AGENTIC_LOG_DIR="$tmp/log2" "$tmp/plug/bin/codex-run" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>"$tmp/err"; rc=$?
[ "$rc" = 2 ] && grep -q 'RULES.md' "$tmp/err" && [ ! -e "$tmp/argv" ] && [ ! -e "$tmp/log2/launch-log.jsonl" ] || bad "missing RULES.md: rc=$rc"
: > "$tmp/plug/RULES.md"
"$tmp/plug/bin/codex-run" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>"$tmp/err"; rc=$?
[ "$rc" = 2 ] && grep -q 'empty' "$tmp/err" && [ ! -e "$tmp/argv" ] || bad "empty RULES.md: rc=$rc"
# A symlinked launcher still finds the plugin root.
cp "$root/RULES.md" "$tmp/plug/RULES.md"; ln -s "$tmp/plug/bin/codex-run" "$tmp/link"
"$tmp/link" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1 && [ -e "$tmp/argv" ] || bad "symlinked launcher failed"

# Codex failing passes its exit code through and still prints the report path.
out=$(FAKE_CODEX_EXIT=3 "$tool" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" 2>/dev/null); rc=$?
[ "$rc" = 3 ] && [ -f "$out" ] || bad "exit passthrough: rc=$rc out=$out"

# Usage events are summed; the event stream goes to a file beside the report, not to stderr, and the report stays plain text.
cat > "$tmp/events" <<'EVENTS'
{"type":"turn.completed","usage":{"input_tokens":12,"cached_input_tokens":4,"output_tokens":3}}
{"type":"turn.completed","usage":{"input_tokens":7,"cached_input_tokens":2,"output_tokens":5}}
EVENTS
out=$(FAKE_CODEX_EVENTS="$tmp/events" "$tool" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" 2>"$tmp/events-out") || bad "usage run failed"
cmp "$tmp/events" "${out%.md}.events.jsonl" || bad "event stream not saved unchanged"
[ ! -s "$tmp/events-out" ] || bad "event stream leaked to stderr"
[ "$(cat "$out")" = "final message" ] || bad "usage altered report"
python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).readlines()[-1]); assert [e[k] for k in ("input_tokens","cached_input_tokens","output_tokens")]==[19,6,8]' "$tmp/log/launch-log.jsonl" || bad "usage totals"
printf '%s\n' 'not json' '{"type":"turn.completed","usage":{"input_tokens":"bad","cached_input_tokens":true}}' > "$tmp/events"
FAKE_CODEX_EVENTS="$tmp/events" "$tool" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1 || bad "malformed usage changed exit"
python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).readlines()[-1]); assert all(e[k] is None for k in ("input_tokens","cached_input_tokens","output_tokens"))' "$tmp/log/launch-log.jsonl" || bad "unreadable usage must be null"
"$tool" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1
python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).readlines()[-1]); assert all(e[k] is None for k in ("input_tokens","cached_input_tokens","output_tokens"))' "$tmp/log/launch-log.jsonl" || bad "missing usage must be null"

# A codex killed by a signal exits 128+n and the log says the same.
cat > "$tmp/bin/codex" <<'FAKE'
#!/bin/sh
kill -TERM $$
FAKE
"$tool" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1; rc=$?
[ "$rc" = 143 ] && tail -n 1 "$tmp/log/launch-log.jsonl" | grep -q '"exit_code": 143' || bad "signal exit: rc=$rc"

# The launch log has launch and finished lines.
grep -q '"decision": "launch"' "$tmp/log/launch-log.jsonl" && grep -q '"decision": "finished"' "$tmp/log/launch-log.jsonl" || bad "launch log lacks launch/finished"
echo "log lines: $(wc -l < "$tmp/log/launch-log.jsonl" | tr -d ' ')"
[ "$fail" = 0 ] && echo "ok"
exit "$fail"
