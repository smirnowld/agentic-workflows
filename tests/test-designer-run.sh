#!/bin/sh
# Exercise the independent designer session with a local fake Claude.
root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as temporary:
    tmp = Path(temporary).resolve()
    (tmp / 'bin').mkdir()
    fake = tmp / 'bin/claude'
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
if sys.argv[1:] == ['--help']:
    print('--permission-mode dontAsk default' if not os.environ.get('NO_DONTASK') else '--permission-mode default')
    sys.exit(0)
Path(os.environ['RECORD']).write_text(json.dumps({'argv':sys.argv[1:],'cwd':os.getcwd(),'stdin':sys.stdin.read()}))
print(json.dumps({'result':'page and screenshots','session_id':'child-session','usage':json.loads(os.environ.get('FAKE_USAGE', '{"input_tokens":12,"cache_creation_input_tokens":3,"cache_read_input_tokens":5,"output_tokens":7}'))}))
sys.exit(int(os.environ.get('FAKE_EXIT','0')))
''')
    fake.chmod(0o755)
    prompt = tmp / 'prompt'
    prompt.write_text('build the named states')
    env = dict(os.environ, PATH=str(tmp / 'bin') + os.pathsep + os.environ['PATH'],
               AGENTIC_LOG_DIR=str(tmp / 'log'), CLAUDE_CODE_SESSION_ID='parent-session', RECORD=str(tmp / 'record'))
    tool = str(root / 'bin/designer-run')
    def run(*args, extra=None):
        return subprocess.run([tool, '--prompt-file', str(prompt), *args], env=dict(env, **(extra or {})), capture_output=True, text=True)
    out = tmp / 'design'
    result = run('--out', str(out))
    assert result.returncode == 0, result.stderr
    report = Path(result.stdout.strip())
    assert report.read_text() == 'page and screenshots'
    raw = json.loads(report.with_suffix('.json').read_text())
    assert raw['session_id'] == 'child-session'
    recorded = json.loads((tmp / 'record').read_text())
    assert recorded['cwd'] == str(out)
    assert recorded['argv'] == ['-p', '--output-format', 'json', '--model', 'opus', '--effort', 'high',
                                '--allowedTools', 'Read', 'Grep', 'Glob', 'Bash',
                                'Edit(/%s/**)' % out, 'Write(/%s/**)' % out,
                                '--disallowedTools', 'NotebookEdit', '--permission-mode', 'dontAsk']
    rules = (root / 'RULES.md').read_text().strip()
    body = re.sub(r'\A---\n.*?\n---\n', '', (root / 'agents/designer.md').read_text(), flags=re.S).strip()
    assert recorded['stdin'] == rules + '\n\n---\n\n' + body + '\n\n---\n\n' + prompt.read_text() + '\n\nOutput folder: ' + str(out) + '\n'
    def logs():
        return [json.loads(line) for line in (tmp / 'log/launch-log.jsonl').read_text().splitlines()]
    entries = logs()
    assert [e['decision'] for e in entries] == ['launch', 'finished']
    for entry in entries:
        assert entry['role'] == 'designer' and entry['design'] is True and entry['tool'] == 'designer-run'
        assert entry['session'] == 'parent-session' and entry['out'] == str(out)
        assert entry['model'] == 'opus' and entry['effort'] == 'high' and entry['route'] == 'primary'
    assert entries[1]['session_id'] == 'child-session' and entries[1]['exit_code'] == 0
    assert [entries[1][k] for k in ('input_tokens','cache_creation_input_tokens','cache_read_input_tokens','output_tokens')] == [12,3,5,7]
    assert run('--fallback').returncode == 0
    recorded = json.loads((tmp / 'record').read_text())
    assert recorded['argv'][recorded['argv'].index('--model') + 1] == 'fable'
    assert recorded['argv'][recorded['argv'].index('--effort') + 1] == 'high'
    assert Path(recorded['cwd']).parent == tmp / 'log/designs'
    assert logs()[-1]['route'] == 'fallback'
    assert run('--out', str(tmp / 'default-mode'), extra={'NO_DONTASK':'1'}).returncode == 0
    assert json.loads((tmp / 'record').read_text())['argv'][-1] == 'default'
    invalid = {'input_tokens':True,'cache_creation_input_tokens':-1,'cache_read_input_tokens':'bad'}
    assert run('--out', str(out), extra={'FAKE_USAGE':json.dumps(invalid)}).returncode == 0
    assert all(logs()[-1][k] is None for k in ('input_tokens','cache_creation_input_tokens','cache_read_input_tokens','output_tokens'))
    result = run('--out', str(out), extra={'FAKE_EXIT':'3'})
    assert result.returncode == 3 and Path(result.stdout.strip()).is_file()
    assert logs()[-1]['exit_code'] == 3
    repo = tmp / 'product'
    subprocess.run(['git','init','-q',str(repo)], check=True)
    before = len(logs())
    result = run('--out', str(repo / 'nested/design'))
    assert result.returncode == 2 and 'outside a git work tree' in result.stderr
    assert not (repo / 'nested').exists() and len(logs()) == before
    link = tmp / 'linked'
    link.symlink_to(repo, target_is_directory=True)
    assert run('--out', str(link / 'design')).returncode == 2
    denies = json.loads((root / 'templates/track/pm/.claude/settings.json').read_text())['permissions']['deny']
    assert all(tool in denies for tool in ('Edit','Write','NotebookEdit'))
print('designer-run: ok')
PY
