#!/bin/sh
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export AGENTIC_LOG_DIR="$tmp/state"
python3 - "$here/../bin/report-lead" <<'PY'
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import time
helper = sys.argv[1]
def run(*args):
    return subprocess.run([sys.executable, helper, *args], capture_output=True, text=True)
def send(kind='done', text='proof', lead='lead'):
    return run('--lead', lead, '--kind', kind, '--message', text)
for kind in ('done', 'blocked', 'decision', 'plan-change'):
    r = send(kind)
    assert r.returncode == 0 and r.stdout == kind + ': proof\n', r
r = send()
assert r.returncode == 1 and not r.stdout and len(r.stderr.splitlines()) == 1
assert send(text='other proof').returncode == 0
assert send(lead='other lead').returncode == 0
state = Path(os.environ['AGENTIC_LOG_DIR']) / 'report-lead.json'
data = json.loads(state.read_text())
state.write_text(json.dumps({k: time.time() - 601 for k in data}))
assert send().returncode == 0
for args in ((), ('--lead','lead','--message','proof'),
             ('--lead','lead','--kind','unknown','--message','proof')):
    r = run(*args)
    assert r.returncode == 64 and not r.stdout and len(r.stderr.splitlines()) == 1, r
with concurrent.futures.ThreadPoolExecutor() as pool:
    results = list(pool.map(lambda _: send(text='simultaneous'), range(2)))
assert sorted(r.returncode for r in results) == [0, 1]
assert all('proof' not in k for k in json.loads(state.read_text()))
print('ok: report kinds, duplicate window, text, lead, arguments and concurrent gate')
PY
