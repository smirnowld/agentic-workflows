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
from concurrent.futures import ThreadPoolExecutor
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
# Hook attachments can precede the brief by more than the short transcript window.
brief = json.dumps({'type':'user', 'message':{'content':'# Brief\n**Lead session:** local_x'}}) + '\n'
attachments = json.dumps({'type':'queue-operation'}) + '\n' + (
    json.dumps({'type':'attachment', 'content':'x' * 25000}) + '\n') * 4
large = tmp / 'large.jsonl'
large.write_text(attachments + brief)
assert call('Read',{}, session='large', transcript_path=str(large)) is None
assert json.loads((log.parent / 'sessions' / 'large').read_text())['reads'] == 1
# A transcript without a user entry stays eligible for detection on later calls.
pending = tmp / 'pending.jsonl'; pending.write_text(attachments)
assert call('Read',{}, session='pending', transcript_path=str(pending)) is None
assert not (log.parent / 'sessions' / 'pending').exists()
with pending.open('a') as f:
    f.write(brief)
assert call('Read',{}, session='pending', transcript_path=str(pending)) is None
assert json.loads((log.parent / 'sessions' / 'pending').read_text())['reads'] == 1
# Missing, unreadable and capped transcripts do not log errors or cache a role.
missing = tmp / 'missing.jsonl'
for session, path in [('missing', missing), ('unreadable', tmp)]:
    assert call('Read',{}, session=session, transcript_path=str(path)) is None
    assert not (log.parent / 'sessions' / session).exists()
missing.write_text(brief)
assert call('Read',{}, session='missing', transcript_path=str(missing)) is None
assert json.loads((log.parent / 'sessions' / 'missing').read_text())['reads'] == 1
capped = tmp / 'capped.jsonl'
capped.write_text(attachments * 22 + brief)
assert call('Read',{}, session='capped', transcript_path=str(capped)) is None
assert not (log.parent / 'sessions' / 'capped').exists()
capped.write_text(brief)
assert call('Read',{}, session='capped', transcript_path=str(capped)) is None
assert json.loads((log.parent / 'sessions' / 'capped').read_text())['reads'] == 1
# Parallel calls share one state transaction and leave complete JSON.
before = log.read_text()
payload = json.dumps(dict(session_id='parallel', cwd=str(repo), transcript_path=str(large),
                          tool_name='Read', tool_input={}))
def read_parallel(_):
    r = subprocess.run([sys.executable, hook], input=payload, text=True, capture_output=True)
    assert r.returncode == 0 and not r.stdout and not r.stderr, r
with ThreadPoolExecutor(max_workers=50) as pool:
    list(pool.map(read_parallel, range(50)))
assert json.loads((log.parent / 'sessions' / 'parallel').read_text())['reads'] == 50
assert log.read_text() == before
assert call('Bash',{'command':'git commit -m test'}, session='lead', cwd=str(track))['decision'] == 'lead-write'
# Corrupt state cannot suppress a lead write; coordinator state recovers after one error.
(log.parent / 'sessions' / 'lead').write_text('{')
assert call('Bash',{'command':'git commit -m test'}, session='lead', cwd=str(track))['decision'] == 'lead-write'
state.write_text('{')
assert call('Read',{})['decision'] == 'error'
assert json.loads(state.read_text()) == {}
assert call('Read',{}, transcript_path=str(large)) is None
assert call('Read',{}, transcript_path=str(large)) is None
assert json.loads(state.read_text())['reads'] == 2
state.write_text('[]')
assert call('Read',{}, transcript_path=str(large))['decision'] == 'error'
assert call('Read',{}, transcript_path=str(large)) is None
assert json.loads(state.read_text())['reads'] == 2
# Git failure allows the call, logs error and makes the failure visible.
(repo / '.git').rename(repo / '.git-hidden')
assert call('Edit',{'file_path':'touched'})['decision'] == 'error'
print('ok: coordinator edits, working and committed changes, shell, reads, role and error')
PY
