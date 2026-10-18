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
[ "$(argv)" = "exec -C $tmp/work -m gpt-6.1-sol -c model_reasoning_effort=\"medium\" -s workspace-write -o $report - " ] || bad "unexpected argv for specified primary"
[ "$(cat "$report")" = "final message" ] || bad "report file lacks the final message"
# The prompt codex receives starts with the role body and ends with the brief.
body=$(awk 'f>=2{print} /^---$/{f++}' "$root/agents/implementer.md" | sed '1{/^$/d;}')
first=$(printf '%s\n' "$body" | head -n 1)
[ "$(head -n 1 "$tmp/stdin")" = "$first" ] && [ -n "$first" ] || bad "stdin does not start with the implementer body"
case $(head -n 1 "$tmp/stdin") in ---*) bad "frontmatter leaked into the prompt" ;; esac
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

# A route that is not codex: exit 2 and codex is not run.
rm -f "$tmp/argv"
"$tool" --role implementer --kind symptom-bug --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>"$tmp/err"; rc=$?
[ "$rc" = 2 ] && grep -q 'not codex' "$tmp/err" && [ ! -e "$tmp/argv" ] || bad "non-codex route: rc=$rc"
"$tool" --role implementer --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1; [ $? = 2 ] || bad "missing --kind should exit 2"
"$tool" --role reviewer --cwd "$tmp/work" --prompt-file "$tmp/prompt" >/dev/null 2>&1; [ $? = 2 ] || bad "claude-only role should exit 2"
"$tool" --role implementer --kind specified --cwd "$tmp/nope" --prompt-file "$tmp/prompt" >/dev/null 2>&1; [ $? = 2 ] || bad "missing cwd should exit 2"

# Codex failing passes its exit code through and still prints the report path.
out=$(FAKE_CODEX_EXIT=3 "$tool" --role implementer --kind specified --cwd "$tmp/work" --prompt-file "$tmp/prompt" 2>/dev/null); rc=$?
[ "$rc" = 3 ] && [ -f "$out" ] || bad "exit passthrough: rc=$rc out=$out"

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
