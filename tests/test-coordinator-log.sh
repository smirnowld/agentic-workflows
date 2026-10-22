#!/bin/sh
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export AGENTIC_LOG_DIR="$tmp/log"
python3 - "$here/../hooks/launch-check.py" "$tmp" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
hook, tmp = sys.argv[1], Path(sys.argv[2])
repo = tmp / 'repo'; repo.mkdir()
track = tmp / 'track'; track.mkdir()
(track / 'track.md').touch(); (track / 'CLAUDE.md').touch()
def git(*args):
    subprocess.run(['git','-C',str(repo),*args], check=True, capture_output=True)
git('init','-b','main')
git('config','user.name','Test'); git('config','user.email','noreply@anthropic.com')
(repo / 'untouched').write_text('base\n'); (repo / 'touched').write_text('base\n')
git('add','.'); git('-c','commit.gpgsign=false','commit','-m','base')
git('checkout','-b','work'); (repo / 'touched').write_text('branch\n')
git('add','.'); git('-c','commit.gpgsign=false','commit','-m','work')
log = Path(os.environ['AGENTIC_LOG_DIR']) / 'launch-log.jsonl'; log.parent.mkdir()
log.write_text(json.dumps({'result':'started','started_session_id':'c1','cwd':str(track)})+'\n')
def call(tool, ti, session='c1', **extra):
    before = log.read_text().splitlines()
    r = subprocess.run([sys.executable, hook], input=json.dumps(dict(session_id=session,
        cwd=str(repo), tool_name=tool, tool_input=ti, **extra)), text=True, capture_output=True)
    assert r.returncode == 0 and not r.stdout, r
    rows = log.read_text().splitlines()[len(before):]
    return json.loads(rows[0]) if rows else None
assert call('Edit',{'file_path':'untouched'})['detail'] == 'first-version'
assert call('Edit',{'file_path':'touched'})['detail'] == 'fix'
assert call('Write',{'file_path':'created'})['detail'] == 'first-version'
(repo / 'untouched').write_text('working\n')
assert call('Edit',{'file_path':'untouched'})['detail'] == 'fix'
assert call('Bash',{'command':'echo x > touched'})['detail'] == 'fix'
assert call('Bash',{'command':'touch created'})['decision'] == 'coordinator-edit'
assert call('Bash',{'command':'echo x > touched && touch created'})['detail'] == 'first-version'
assert call('Bash',{'command':'touch touched created'})['detail'] == 'first-version'
for tool in ('Read','Grep','Glob'):
    assert call(tool,{})['decision'] == 'coordinator-read'
assert call('Bash',{'command':'git diff'})['decision'] == 'coordinator-read'
assert call('Edit',{'file_path':'untouched'}, session='other') is None
assert call('Edit',{'file_path':'touched'}, agent_id='worker', agent_type='implementer') is None
# Git failure allows the call, logs error and makes the failure visible.
(repo / '.git').rename(repo / '.git-hidden')
assert call('Edit',{'file_path':'touched'})['decision'] == 'error'
print('ok: coordinator edits, working and committed changes, shell, reads, role and error')
PY
