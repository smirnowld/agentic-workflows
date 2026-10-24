#!/bin/sh
# Token accounting against isolated transcripts and launch logs.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" <<'PY'
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    log = tmp / "log" / "launch-log.jsonl"
    log.parent.mkdir()
    projects = tmp / "projects"
    project = projects / "product"
    project.mkdir(parents=True)
    track = tmp / "track"
    lead = track / "lead"
    lead.mkdir(parents=True)
    (track / "track.md").touch()
    (lead / "CLAUDE.md").touch()
    states = log.parent / "sessions"
    states.mkdir()
    (states / "work").write_text('{"coordinator": true}')
    def time(minute):
        return '2026-01-01T00:%02d:00Z' % minute
    def usage(n):
        return dict(input_tokens=n, cache_creation_input_tokens=1, cache_read_input_tokens=2, output_tokens=3)
    def message(ident, n, minute=5, cwd=None):
        return dict(type="assistant", timestamp=time(minute), cwd=str(cwd or tmp), message=dict(id=ident, usage=usage(n)))
    def transcript(session, rows):
        (project / (session + '.jsonl')).write_text(''.join(json.dumps(row)+'\n' for row in rows))
    transcript('lead', [message('lead-msg', 94, cwd=lead)] * 2)  # 100
    transcript('work', [message('work-msg', 194)])  # 200
    transcript('pm', [message('before', 900, 1), message('design', 4), message('after', 900, 9)])  # design 10
    transcript('private', [message('excluded', 900)])
    (states / "child").write_text('{"coordinator": true}')
    transcript('child', [message('runner-copy', 24)])  # runner accounted by its log
    def sub(name, meta, n):
        folder = project / 'work' / 'subagents'
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / ('agent-' + name + '.jsonl')
        path.write_text(json.dumps(message(name, n))+'\n')
        path.with_suffix('.meta.json').write_text(json.dumps(meta))
    sub('impl', dict(agentType='agentic-workflows:implementer', toolUseId='impl'), 44)  # 50
    sub('visual', dict(agentType='agentic-workflows:visual-reviewer', toolUseId='visual'), 14)  # 20
    sub('designer', dict(agentType='agentic-workflows:designer', toolUseId='designer'), 4)  # 10
    sub('other', dict(agentType='agentic-workflows:reviewer', toolUseId='shared'), 4)  # 10 implementation
    rows = [dict(decision='allow', tool='Agent', session='work', tool_use_id='visual', design=True),
            dict(decision='allow', tool='Agent', session='elsewhere', tool_use_id='shared', design=True),
            dict(decision='design-mark', mark='start', session='pm', time=time(2)),
            dict(decision='design-mark', mark='end', session='pm', time=time(8)),
            dict(decision='finished', tool='codex-run', session='work', time=time(5), input_tokens=30, cached_input_tokens=29, output_tokens=10),
            dict(decision='finished', tool='codex-run', session='pm', time=time(5), design=True, input_tokens=15, output_tokens=5),
            dict(decision='finished', tool='designer-run', session='pm', session_id='child', time=time(5), design=True, **usage(24)),
            dict(decision='finished', tool='codex-run', session='private', time=time(5), input_tokens=900, output_tokens=900),
            dict(decision='finished', tool='designer-run', session='pm', time=time(20), design=True, **usage(900))]
    def save():
        log.write_text(''.join(json.dumps(row)+'\n' for row in rows))
    save()
    def run(*args, expected=0):
        result = subprocess.run([str(root / 'bin/design-share'), '--log', str(log), '--projects', str(projects), *args], capture_output=True, text=True)
        assert result.returncode == expected, result.stderr + result.stdout
        return result
    result = run('--since', time(4), '--until', time(7))
    # Design = PM 10 + visual 20 + designer agent 10 + critic 20 + runner 30 = 90.
    # Lead = 100; implementation = main 200 + impl 50 + review 10 + Codex 40 = 300.
    assert result.stdout == 'design: 90 tokens\nlead: 100 tokens\nimplementation: 300 tokens\ndesign share: 18.37% (over 10% line)\n', result.stdout
    # Zone offsets must sort by instant; the mark starts before the window.
    rows[2]['time'] = '2026-01-01T01:02:00+01:00'
    save()
    assert 'design: 90 tokens' in run('--since', time(4), '--until', time(7)).stdout
    rows[2]['time'] = time(2)
    save()
    # Window excludes all five-minute messages and runner events.
    result = run('--since', time(6), '--until', time(7))
    assert 'design: 0 tokens' in result.stdout and 'at or under 10% line' in result.stdout
    # Exactly ten percent is on the permitted side; the next token crosses it.
    transcript('lead', [message('lead-msg', 804, cwd=lead)])  # lead 810
    transcript('work', [])
    transcript('child', [])
    for path in (project / 'work' / 'subagents').iterdir():
        path.unlink()
    transcript('pm', [])
    rows[:] = [dict(decision='finished', tool='codex-run', time=time(5), design=True, input_tokens=80, output_tokens=10)]
    save()
    assert '10.00% (at or under' in run().stdout
    rows[0]['output_tokens'] = 11
    save()
    assert '(over 10% line)' in run().stdout
    # Broken sources are visible and make the report incomplete.
    assert 'report incomplete' in run('--projects', str(tmp / 'missing'), expected=1).stderr
    rows.append(dict(decision='finished', tool='codex-run', time=123, design=True, input_tokens=1, output_tokens=1))
    save()
    assert 'invalid timestamp' in run(expected=1).stderr
    rows.pop()
    rows[0]['output_tokens'] = None
    save()
    assert 'invalid token counts' in run(expected=1).stderr
    log.write_text('{broken\n')
    assert 'invalid JSON' in run(expected=1).stderr
    assert 'No such file' in subprocess.run([str(root / 'bin/design-share'), '--log', str(tmp / 'absent'), '--projects', str(projects)], capture_output=True, text=True).stderr
    assert subprocess.run([str(root / 'bin/design-share'), '--since', 'wrong'], capture_output=True).returncode == 2
    # The PM helper requires an explicit session and item, and writes paired marks.
    env = dict(os.environ, AGENTIC_LOG_DIR=str(tmp / 'marks'))
    env.pop('CLAUDE_CODE_SESSION_ID', None)
    tool = str(root / 'bin/design-mark')
    assert subprocess.run([tool, 'start', '--item', 'https://example.test/item'], env=env, capture_output=True).returncode == 2
    env['CLAUDE_CODE_SESSION_ID'] = 'pm'
    assert subprocess.run([tool, 'start'], env=env, capture_output=True).returncode == 2
    assert subprocess.run([tool, 'start', '--item', ''], env=env, capture_output=True).returncode == 2
    for mark in ('start', 'end'):
        subprocess.run([tool, mark, '--item', 'https://example.test/item'], env=env, check=True)
    marks = [json.loads(line) for line in (tmp / 'marks/launch-log.jsonl').read_text().splitlines()]
    assert [row['mark'] for row in marks] == ['start', 'end']
    for row in marks:
        assert row['decision'] == 'design-mark' and row['tool'] == 'design-mark'
        assert row['session'] == 'pm' and row['item'] == 'https://example.test/item'
        datetime.datetime.fromisoformat(row['time'])
print('design-share and design-mark: OK')
PY
