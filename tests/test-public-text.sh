#!/bin/sh
# The repository is public: no file names its history or its author's private
# details. Scans every git-tracked file except this one and prints only
# path:line and the rule name, never the matched text (CI logs are public).
# Rules: history words; email addresses other than noreply@anthropic.com;
# the author's handle outside CODEOWNERS; private terms from PRIVATE_TERMS
# (comma- or newline-separated, case-insensitive; skipped when unset).
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

scan() { # scan REPO_DIR: prints "where rule" per hit, exit 1 on any hit
python3 -I - "$1" <<'PY'
import os, re, subprocess, sys
repo = sys.argv[1]
def git(*a):
    return subprocess.run(["git", "-C", repo] + list(a), capture_output=True, check=True).stdout.decode("utf-8", "ignore")
files = git("ls-files", "-z").split("\0")
rules = [
    ("history-word", re.compile(r"(?<![\w.])v?(1\.0|2\.0)(?!\w|\.\d)|previous setup|old setup|first version|second version|agent-practices", re.I)),
    ("email", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")),
    ("author-handle", re.compile(r"@smirnowld", re.I)),
]
terms = [t.strip().lower() for t in re.split(r"[,\n]", os.environ.get("PRIVATE_TERMS", "")) if t.strip()]
hits = 0

def check(text, exempt_handle=False):
    """Names of the rules that fire on one line of text."""
    found = []
    for name, rx in rules:
        for m in rx.finditer(text):
            if name == "email" and m.group(0).lower() == "noreply@anthropic.com":
                continue
            if name == "author-handle" and exempt_handle:
                continue
            found.append(name)
            break
    if any(t in text.lower() for t in terms):
        found.append("private-term")
    return found

def report(where, names):
    global hits
    for name in names:
        print("%s %s" % (where, name))
        hits += 1

def scan_text(where, text):
    names = []
    for line in text.splitlines():
        for n in check(line):
            if n not in names:
                names.append(n)
    report(where, names)

idx = 0
for f in files:
    if not f:
        continue
    idx += 1
    # the path itself: a private-term hit names the path's index, not the path
    exempt = os.path.basename(f) == "CODEOWNERS"
    path_hits = check(f, exempt)
    # a path with a private term is never printed: every hit in that file uses its index
    label = "path-name #%d" % idx if "private-term" in path_hits else f
    report(label, path_hits)
    if f == "tests/test-public-text.sh":
        continue
    try:
        data = open(os.path.join(repo, f), "rb").read()
    except OSError:
        continue
    if b"\0" in data:
        continue
    for n, line in enumerate(data.decode("utf-8", "ignore").splitlines(), 1):
        for name in check(line, exempt):
            print("%s:%d %s" % (label, n, name))
            hits += 1

# commit messages: the range CI passes, or origin/main..HEAD when it exists
rng = os.environ.get("PT_RANGE")
if not rng:
    ok = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "-q", "origin/main"], capture_output=True).returncode == 0
    rng = "origin/main..HEAD" if ok else None
if rng:
    for sha in git("rev-list", rng).split():
        scan_text("commit %s" % sha[:10], git("log", "-1", "--format=%B", sha))
if os.environ.get("PR_TITLE"):
    scan_text("pr-title", os.environ["PR_TITLE"])
if os.environ.get("PR_BODY"):
    scan_text("pr-body", os.environ["PR_BODY"])
sys.exit(1 if hits else 0)
PY
}

mask_terms() { # in GitHub Actions, make the runner redact each private term before anything else runs
  [ -n "$GITHUB_ACTIONS" ] || return 0
  python3 -I -c '
import os, re
for t in re.split(r"[,\n]", os.environ.get("PRIVATE_TERMS", "")):
    if t.strip():
        print("::add-mask::" + t.strip())'
}
mask_terms

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
printf 'ok line\nversion 1.0 shipped\nversion 7.0.1 and 0.1.0 and 2.0.3 are fine\n' > "$tmp/hist.md"
printf 'the Previous Setup was\n' > "$tmp/hist2.md"
printf 'write to someone@example.org\nCo-Authored-By: x <noreply@anthropic.com>\n' > "$tmp/mail.md"
printf '@smirnowld owns it\n' > "$tmp/CODEOWNERS"
printf 'ping @smirnowld now\n' > "$tmp/handle.md"
printf 'the Zzquux project\n' > "$tmp/term.md"
printf 'x\n' > "$tmp/zzquux-notes.txt"
printf 'bad 2.0 name\n' > "$tmp/v-2.0-plan.txt"
printf 'mail someone@example.org\n' > "$tmp/zzsecret-1.0.txt"
g() { git -C "$tmp" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
g add -A
g commit -q -m "base"
printf 'more\n' > "$tmp/more.txt"; g add -A
g commit -q -m "first version mail someone@example.org Zzquux" -m "Co-Authored-By: x <noreply@anthropic.com>"
fail=0
out=$(PT_RANGE=HEAD~1..HEAD PR_TITLE="the Zzquux title" PR_BODY="line
ping @smirnowld" PRIVATE_TERMS="other, zzquux, zzsecret" scan "$tmp"); rc=$?
[ "$rc" = 1 ] || { echo "FAIL: self-test found no violations"; fail=1; }
for want in "hist.md:2 history-word" "hist2.md:1 history-word" "mail.md:1 email" "handle.md:1 author-handle" "term.md:1 private-term" "path-name #9 private-term" "v-2.0-plan.txt history-word" "pr-title private-term" "pr-body author-handle"; do
  printf '%s\n' "$out" | grep -qxF "$want" || { echo "FAIL: self-test: rule did not fire: $want"; fail=1; }
done
printf '%s\n' "$out" | grep -qE '^commit [0-9a-f]{10} history-word$' && printf '%s\n' "$out" | grep -qE '^commit [0-9a-f]{10} email$' && printf '%s\n' "$out" | grep -qE '^commit [0-9a-f]{10} private-term$' || { echo "FAIL: self-test: commit rules did not fire"; fail=1; }
printf '%s\n' "$out" | grep -qE '^path-name #[0-9]+ history-word$' && printf '%s\n' "$out" | grep -qE '^path-name #[0-9]+:1 email$' || { echo "FAIL: self-test: private-term path not reported by index"; fail=1; }
printf '%s\n' "$out" | grep -q 'base' && { echo "FAIL: self-test: out-of-range commit scanned"; fail=1; }
case $out in *someone*|*example*|*Zzquux*|*zzquux-notes*|*zzsecret*|*zzquux*|*shipped*|*owns*|*Previous*) echo "FAIL: self-test: output contains matched text"; fail=1 ;; esac
n=$(PRIVATE_TERMS= scan "$tmp" | grep -c private-term); [ "$n" = 0 ] || { echo "FAIL: private-term fired with PRIVATE_TERMS unset"; fail=1; }
m=$(GITHUB_ACTIONS=true PRIVATE_TERMS="alpha, ,beta
gamma" mask_terms)
[ "$m" = "::add-mask::alpha
::add-mask::beta
::add-mask::gamma" ] || { echo "FAIL: self-test: mask lines wrong"; fail=1; }
m=$(GITHUB_ACTIONS= PRIVATE_TERMS="alpha" mask_terms); [ -z "$m" ] || { echo "FAIL: self-test: mask lines printed outside GitHub Actions"; fail=1; }
[ "$fail" = 0 ] || exit 1
echo "self-test ok"

if [ -z "$PRIVATE_TERMS" ]; then
  if [ -n "$GITHUB_ACTIONS" ] && [ "$PUBLIC_TEXT_FORK" != true ]; then
    echo "FAIL: PRIVATE_TERMS is empty in CI; set the PRIVATE_TERMS secret"; exit 1
  elif [ -n "$GITHUB_ACTIONS" ]; then
    echo "note: a fork's run has no secrets; the private-terms rule could not run"
  else
    echo "note: PRIVATE_TERMS is not set; the private-terms rule is skipped"
  fi
fi
if scan "$root"; then echo "ok"; else echo "FAIL: public text rules (see path:line above)"; exit 1; fi
