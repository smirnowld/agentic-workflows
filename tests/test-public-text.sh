#!/bin/sh
# The repository is public: no file names its history or its author's private
# details. Scans every git-tracked file except this one and prints only
# path:line and the rule name, never the matched text (CI logs are public).
# Rules: history words; email addresses other than noreply@anthropic.com;
# the author's handle outside CODEOWNERS; private terms from PRIVATE_TERMS
# (comma- or newline-separated, case-insensitive; skipped when unset).
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

scan() { # scan REPO_DIR: prints "path:line rule" per hit, exit 1 on any hit
python3 -I - "$1" <<'PY'
import os, re, subprocess, sys
repo = sys.argv[1]
files = subprocess.run(["git", "-C", repo, "ls-files", "-z"], capture_output=True, check=True).stdout.decode().split("\0")
rules = [
    ("history-word", re.compile(r"(?<![\w.])v?(1\.0|2\.0)(?!\w|\.\d)|previous setup|old setup|first version|second version|agent-practices", re.I)),
    ("email", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")),
    ("author-handle", re.compile(r"@smirnowld", re.I)),
]
terms = [t.strip().lower() for t in re.split(r"[,\n]", os.environ.get("PRIVATE_TERMS", "")) if t.strip()]
hits = 0
for f in files:
    if not f or f == "tests/test-public-text.sh":
        continue
    try:
        data = open(os.path.join(repo, f), "rb").read()
    except OSError:
        continue
    if b"\0" in data:
        continue
    for n, line in enumerate(data.decode("utf-8", "ignore").splitlines(), 1):
        found = []
        for name, rx in rules:
            for m in rx.finditer(line):
                if name == "email" and m.group(0).lower() == "noreply@anthropic.com":
                    continue
                if name == "author-handle" and os.path.basename(f) == "CODEOWNERS":
                    continue
                found.append(name)
                break
        low = line.lower()
        if any(t in low for t in terms):
            found.append("private-term")
        for name in found:
            print("%s:%d %s" % (f, n, name))
            hits += 1
sys.exit(1 if hits else 0)
PY
}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
printf 'ok line\nversion 1.0 shipped\nversion 7.0.1 and 0.1.0 and 2.0.3 are fine\n' > "$tmp/hist.md"
printf 'the Previous Setup was\n' > "$tmp/hist2.md"
printf 'write to someone@example.org\nCo-Authored-By: x <noreply@anthropic.com>\n' > "$tmp/mail.md"
printf '@smirnowld owns it\n' > "$tmp/CODEOWNERS"
printf 'ping @smirnowld now\n' > "$tmp/handle.md"
printf 'the Zzquux project\n' > "$tmp/term.md"
git -C "$tmp" add -A
fail=0
out=$(PRIVATE_TERMS="other, zzquux" scan "$tmp"); rc=$?
[ "$rc" = 1 ] || { echo "FAIL: self-test found no violations"; fail=1; }
for want in "hist.md:2 history-word" "hist2.md:1 history-word" "mail.md:1 email" "handle.md:1 author-handle" "term.md:1 private-term"; do
  printf '%s\n' "$out" | grep -qxF "$want" || { echo "FAIL: self-test: rule did not fire: $want"; fail=1; }
done
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 5 ] || { echo "FAIL: self-test: unexpected hit count"; fail=1; }
case $out in *someone*|*example*|*Zzquux*|*zzquux*|*shipped*|*owns*|*Previous*) echo "FAIL: self-test: output contains matched text"; fail=1 ;; esac
n=$(PRIVATE_TERMS= scan "$tmp" | grep -c private-term); [ "$n" = 0 ] || { echo "FAIL: private-term fired with PRIVATE_TERMS unset"; fail=1; }
[ "$fail" = 0 ] || exit 1
echo "self-test ok"

[ -n "$PRIVATE_TERMS" ] || echo "note: PRIVATE_TERMS is not set; the private-terms rule is skipped"
if scan "$root"; then echo "ok"; else echo "FAIL: public text rules (see path:line above)"; exit 1; fi
