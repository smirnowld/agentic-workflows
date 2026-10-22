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
(repo / 'sub').mkdir(); (repo / 'sub' / 'nested').write_text('base\n')
(repo / 'untouched').write_text('base\n'); (repo / 'touched').write_text('base\n')
git('add','.'); git('-c','commit.gpgsign=false','commit','-m','base')
git('checkout','-b','work'); (repo / 'touched').write_text('branch\n')
git('add','.'); git('-c','commit.gpgsign=false','commit','-m','work')
log = Path(os.environ['AGENTIC_LOG_DIR']) / 'launch-log.jsonl'; log.parent.mkdir()
log.write_text('garbage\n')
transcript = tmp / 'transcript.jsonl'
transcript.write_text('malformed\n' + json.dumps({'type':'system'}) + '\n' + json.dumps({
    'type':'user', 'message':{'role':'user', 'content':[{'type':'text',
    'text':'# Brief\n**Lead session:** local_x\nDo the work.'}]}}) + '\n')
plain = tmp / 'plain.jsonl'
plain.write_text(json.dumps({'type':'user', 'message':{'role':'user', 'content':'Read this.'}})+'\n')
def call(tool, ti, session='c1', **extra):
    before = log.read_text().splitlines()
    r = subprocess.run([sys.executable, hook], input=json.dumps(dict(session_id=session,
        cwd=extra.pop('cwd', str(repo)), transcript_path=extra.pop('transcript_path', str(transcript)), tool_name=tool, tool_input=ti, **extra)), text=True, capture_output=True)
    assert r.returncode == 0 and not r.stdout, r
    rows = log.read_text().splitlines()[len(before):]
    return json.loads(rows[0]) if rows else None
assert call('Edit',{'file_path':'untouched'})['detail'] == 'first-version'
assert call('Edit',{'file_path':'touched'})['detail'] == 'fix'
assert call('Write',{'file_path':'created'})['detail'] == 'first-version'
(repo / 'untouched').write_text('working\n')
assert call('Edit',{'file_path':'untouched'})['detail'] == 'first-version'
assert call('Bash',{'command':'echo x > touched'})['detail'] == 'fix'
assert call('Bash',{'command':'touch created'})['decision'] == 'coordinator-edit'
assert call('Bash',{'command':'echo x > touched && touch created'})['detail'] == 'first-version'
assert call('Bash',{'command':'touch touched created'})['detail'] == 'first-version'
# The cached role survives removal of the transcript; reads only update state.
transcript.unlink()
for tool in ('Read','Grep','Glob'):
    assert call(tool,{}) is None
state = log.parent / 'sessions' / 'c1'
assert json.loads(state.read_text())['reads'] == 3
assert call('Bash',{'command':'git diff'}) is None
(repo / 'untracked').write_text('worker content\n')
assert call('Edit',{'file_path':'untracked'})['detail'] == 'fix'
(repo / 'sub' / 'nested').write_text('worker content\n')
assert call('Edit',{'file_path':'nested'}, cwd=str(repo / 'sub'))['detail'] == 'fix'
(repo / 'sub' / 'untracked').write_text('worker content\n')
assert call('Edit',{'file_path':'untracked'}, cwd=str(repo / 'sub'))['detail'] == 'fix'
link = tmp / 'alias'; link.symlink_to(repo, target_is_directory=True)
assert call('Edit',{'file_path':str(link / 'touched')})['detail'] == 'fix'
assert call('Edit',{'file_path':'untouched'}, session='other', transcript_path=str(plain)) is None
assert call('Edit',{'file_path':'touched'}, agent_id='worker', agent_type='implementer') is None
assert call('Read',{}, session='other', transcript_path=str(plain)) is None
assert call('Bash',{'command':'git commit -m test'}, session='lead', cwd=str(track))['decision'] == 'lead-write'
# Corrupt state cannot suppress a lead write; other calls fail open visibly.
(log.parent / 'sessions' / 'lead').write_text('{')
assert call('Bash',{'command':'git commit -m test'}, session='lead', cwd=str(track))['decision'] == 'lead-write'
state.write_text('{')
assert call('Read',{})['decision'] == 'error'
state.write_text(json.dumps({'coordinator':True}))
# Git failure allows the call, logs error and makes the failure visible.
(repo / '.git').rename(repo / '.git-hidden')
assert call('Edit',{'file_path':'touched'})['decision'] == 'error'
print('ok: coordinator edits, working and committed changes, shell, reads, role and error')
PY
