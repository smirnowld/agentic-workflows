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
import signal
import time

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as temporary:
    tmp = Path(temporary).resolve()
    (tmp / 'bin').mkdir()
    fake = tmp / 'bin/claude'
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys, subprocess, time
from pathlib import Path
if sys.argv[1:] == ['--help']:
    flags = ['--restricted', '--strict-mcp-config', '--tools', '--settings']
    print(' '.join(f for f in flags if f != os.environ.get('MISSING_FLAG')) + (' --permission-mode dontAsk default' if not os.environ.get('NO_DONTASK') else ' --permission-mode default'))
    sys.exit(0)
Path(os.environ['RECORD']).write_text(json.dumps({'argv':sys.argv[1:],'cwd':os.getcwd(),'stdin':sys.stdin.read(),'env':dict(os.environ),'temp_exists':Path(os.environ['CLAUDE_CODE_TMPDIR']).is_dir()}))
if os.environ.get('HOLD'):
    time.sleep(300)
if os.environ.get('BACKGROUND'):
    children = []
    for cwd, new_session in [(os.getcwd(), True), ('/', True), (os.environ['CLAUDE_CODE_TMPDIR'], True), ('/', False)]:
        children.append(subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'], cwd=cwd, start_new_session=new_session, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    Path(os.environ['BACKGROUND']).write_text(json.dumps([p.pid for p in children]))
print(json.dumps({'result':'page and screenshots','session_id':'child-session','usage':json.loads(os.environ.get('FAKE_USAGE', '{"input_tokens":12,"cache_creation_input_tokens":3,"cache_read_input_tokens":5,"output_tokens":7}'))}))
sys.exit(int(os.environ.get('FAKE_EXIT','0')))
''')
    fake.chmod(0o755)
    prompt = tmp / 'prompt'
    prompt.write_text('build the named states')
    env = dict(os.environ, PATH=str(tmp / 'bin') + os.pathsep + os.environ['PATH'],
               AGENTIC_LOG_DIR=str(tmp / 'log'), CLAUDE_CODE_SESSION_ID='parent-session', RECORD=str(tmp / 'record'))
    env.pop('ANTHROPIC_AUTH_TOKEN', None)
    env.update(ANTHROPIC_API_KEY='test-value', CLAUDE_CODE_OAUTH_TOKEN='test-value', ORDINARY='kept')
    scrubbed = ('GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN',
                'AWS_SECRET_ACCESS_KEY','SSH_AUTH_SOCK','GIT_ASKPASS','MY_PASSWORD','CLAUDECODE')
    env.update({key:'test-value' for key in scrubbed})
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
    settings = json.loads(recorded['argv'][recorded['argv'].index('--settings') + 1])
    expected = {'sandbox': {
        'enabled':True, 'failIfUnavailable':True, 'allowUnsandboxedCommands':False,
        'autoAllowBashIfSandboxed':True, 'network':{'allowedDomains':[], 'allowLocalBinding':True},
        'filesystem':{'denyRead':['~/.claude.json','~/.claude/.credentials.json','~/.claude/projects',
            '~/.config/gh','~/.git-credentials','~/.netrc','~/.ssh','~/.aws','~/.docker','~/.kube',
            '~/.gnupg','~/Library/Keychains']},
        'credentials':{'envVars':[{'name':key,'mode':'deny'} for key in ('ANTHROPIC_API_KEY','CLAUDE_CODE_OAUTH_TOKEN')]}}}
    assert settings == expected
    assert not any(key in recorded['env'] for key in scrubbed)
    assert recorded['env']['ANTHROPIC_API_KEY'] == recorded['env']['CLAUDE_CODE_OAUTH_TOKEN'] == 'test-value'
    assert recorded['env']['ORDINARY'] == 'kept' and recorded['env']['PATH'] == env['PATH']
    assert recorded['env']['DESIGNER_RUN'] == report.stem
    def check_temp(record):
        folder = Path(record['env']['CLAUDE_CODE_TMPDIR'])
        assert record['temp_exists'] and folder.parent == Path('/tmp').resolve()
        assert folder.name.startswith('designer.') and not folder.exists()
        return folder
    first_temp = check_temp(recorded)
    assert recorded['argv'] == ['-p', '--output-format', 'json', '--model', 'opus', '--effort', 'high',
                                '--restricted', '--strict-mcp-config', '--tools', 'Read', 'Grep', 'Glob', 'Bash', 'Edit', 'Write',
                                '--settings', recorded['argv'][recorded['argv'].index('--settings') + 1],
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
    assert check_temp(recorded) != first_temp
    assert run('--out', str(tmp / 'default-mode'), extra={'NO_DONTASK':'1'}).returncode == 0
    assert json.loads((tmp / 'record').read_text())['argv'][-1] == 'default'
    invalid = {'input_tokens':True,'cache_creation_input_tokens':-1,'cache_read_input_tokens':'bad'}
    assert run('--out', str(out), extra={'FAKE_USAGE':json.dumps(invalid)}).returncode == 0
    assert all(logs()[-1][k] is None for k in ('input_tokens','cache_creation_input_tokens','cache_read_input_tokens','output_tokens'))
    result = run('--out', str(out), extra={'FAKE_EXIT':'3'})
    assert result.returncode == 3 and Path(result.stdout.strip()).is_file()
    assert logs()[-1]['exit_code'] == 3
    check_temp(json.loads((tmp / 'record').read_text()))
    def refused(*args, extra=None):
        before = len(logs())
        (tmp / 'record').unlink(missing_ok=True)
        result = run(*args, extra=extra)
        assert result.returncode == 2 and len(result.stderr.splitlines()) == 1, result.stderr
        assert len(logs()) == before and not (tmp / 'record').exists()
    for flag in ('--restricted','--strict-mcp-config','--tools','--settings'):
        refused('--out', str(out), extra={'MISSING_FLAG':flag})
    source = tmp / 'style.md'
    source.write_text('project style')
    assert run('--out', str(out), '--read', str(source)).returncode == 0
    assert (out / 'input/style.md').read_text() == source.read_text()
    recorded = json.loads((tmp / 'record').read_text())
    assert recorded['stdin'].endswith('Output folder: %s\nProject file: %s (copy of %s)\n' % (out, out / 'input/style.md', source))
    other = tmp / 'other'
    other.mkdir()
    (other / source.name).write_text('other style')
    for files in ((str(other),), (str(tmp / 'missing'),), (str(source), str(other / source.name))):
        refused('--out', str(out), *[arg for file in files for arg in ('--read', file)])
    repo = tmp / 'product'
    subprocess.run(['git','init','-q',str(repo)], check=True)
    before = len(logs())
    result = run('--out', str(repo / 'nested/design'))
    assert result.returncode == 2 and 'outside a git work tree' in result.stderr
    assert not (repo / 'nested').exists() and len(logs()) == before
    link = tmp / 'linked'
    link.symlink_to(repo, target_is_directory=True)
    assert run('--out', str(link / 'design')).returncode == 2
    # Broad output permissions must not include a protected folder.
    for protected in (Path.home(), Path.home() / '.claude', tmp / 'log', root):
        for path in (protected, protected.parent):
            result = run('--out', str(path))
            assert result.returncode == 2 and 'protected folder' in result.stderr, result.stderr
            assert len(result.stderr.splitlines()) == 1
    for char in '()*?[]\n':
        path = tmp / ('unsafe' + char + 'out')
        result = run('--out', str(path))
        assert result.returncode == 2 and 'permission-rule characters' in result.stderr
        assert len(result.stderr.splitlines()) == 1 and not path.exists()
    protected_link = tmp / 'protected-link'
    protected_link.symlink_to(tmp / 'log', target_is_directory=True)
    assert run('--out', str(protected_link)).returncode == 2
    assert len(logs()) == before
    assert run().returncode == 0
    assert Path(json.loads((tmp / 'record').read_text())['cwd']).parent == tmp / 'log/designs'
    denies = json.loads((root / 'templates/track/pm/.claude/settings.json').read_text())['permissions']['deny']
    assert all(tool in denies for tool in ('Edit','Write','NotebookEdit'))
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        (tmp / 'record').unlink()
        runner = subprocess.Popen([tool, '--prompt-file', str(prompt), '--out', str(out)],
                                  env=dict(env, HOLD='1'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not (tmp / 'record').exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            assert (tmp / 'record').exists(), 'child did not start'
            runner.send_signal(sig)
            runner.communicate(timeout=10)
            assert runner.returncode == 128 + sig
            check_temp(json.loads((tmp / 'record').read_text()))
            assert logs()[-1]['decision'] == 'finished' and logs()[-1]['exit_code'] == 128 + sig
        finally:
            if runner.poll() is None:
                runner.kill()
                runner.wait()
    def alive(pid):
        try:
            os.kill(pid, 0)
            # A zombie cannot execute and is waiting for its parent to reap it.
            stat = Path('/proc/%d/stat' % pid)
            return not (stat.exists() and stat.read_text().split()[2] == 'Z')
        except ProcessLookupError:
            return False
    unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'], cwd=tmp,
                                 env={k:v for k,v in os.environ.items() if k != 'DESIGNER_RUN'})
    try:
        result = run('--out', str(out), extra={'BACKGROUND':str(tmp / 'pids')})
        assert result.returncode == 0, result.stderr
        assert unrelated.poll() is None
        pids = json.loads((tmp / 'pids').read_text())
        deadline = time.monotonic() + 3
        while any(alive(pid) for pid in pids) and time.monotonic() < deadline:
            time.sleep(0.05)
        assert not any(alive(pid) for pid in pids), (pids, result.stderr, logs()[-1])
        assert logs()[-1]['stopped'] >= 3, logs()[-1]
        assert unrelated.poll() is None
    finally:
        unrelated.terminate()
        unrelated.wait()
        for pid in json.loads((tmp / 'pids').read_text()) if (tmp / 'pids').exists() else []:
            if alive(pid):
                os.kill(pid, signal.SIGKILL)
print('designer-run: ok')
PY
