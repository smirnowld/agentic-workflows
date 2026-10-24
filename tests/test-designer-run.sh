#!/bin/sh
# Exercise the independent designer session with a local fake Claude.
root=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$root" <<'PY'
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import signal
import time
from unittest.mock import patch

root = Path(sys.argv[1])
launcher = runpy.run_path(str(root / 'bin/designer-run'))
# Partial process listings still protect existing pids and find run markers.
with patch('os.path.isdir', return_value=False), patch('subprocess.run') as command:
    command.return_value = subprocess.CompletedProcess([], 1, stdout='101\n102\n')
    assert launcher['user_pids']() == {101, 102}
    command.side_effect = [
        subprocess.CompletedProcess([], 1, stdout='101 cmd DESIGNER_RUN=example\n104 cmd DESIGNER_RUN=example\n'),
        subprocess.CompletedProcess([], 1, stdout='p102\nn/output\np103\nn/output\n')]
    assert launcher['run_processes']('example', ('/output',), {101,102}, 104) == {101,103}
# A process group that survives TERM is killed, then the child is reaped before scanning.
events = []
class Child:
    pid = 104
    def wait(self):
        events.append('reaped')
def scan(*args):
    assert events == ['reaped']
    return set()
with patch('os.killpg') as group, patch('time.monotonic', side_effect=[0,3,3]), patch.dict(
        launcher['stop_processes'].__globals__, run_processes=scan):
    assert launcher['stop_processes'](Child(), 'example', '/output', None, {101}) == 0
    assert group.call_args_list == [((104, signal.SIGTERM),), ((104, signal.SIGKILL),)]
print('designer-run helpers: ok', flush=True)
with tempfile.TemporaryDirectory() as temporary:
    tmp = Path(temporary).resolve()
    (tmp / 'bin').mkdir()
    fake = tmp / 'bin/claude'
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys, subprocess, time
from pathlib import Path
config = json.loads((Path(__file__).parent.parent / 'config').read_text())
# macOS adds this to every process it starts.
os.environ.pop('__CF_USER_TEXT_ENCODING', None)
if sys.argv[1:] == ['--help']:
    flags = ['--restricted', '--strict-mcp-config', '--tools', '--settings']
    print(' '.join(f for f in flags if f != config.get('MISSING_FLAG')) + (' --permission-mode dontAsk default' if not config.get('NO_DONTASK') else ' --permission-mode default'))
    Path(config['RECORD'] + '-help').write_text(json.dumps(dict(os.environ)))
    if config.get('LAUNCH_ERROR'):
        Path(__file__).chmod(0o644)
    sys.exit(0)
Path(config['RECORD']).write_text(json.dumps({'argv':sys.argv[1:],'cwd':os.getcwd(),'stdin':sys.stdin.read(),'env':dict(os.environ),'temp_exists':Path(os.environ['CLAUDE_CODE_TMPDIR']).is_dir()}))
if config.get('LINKS'):
    out = Path.cwd()
    (out / 'symlink').symlink_to(config['LINKS'])
    os.link(config['LINKS'], out / 'hardlink')
    os.mkfifo(out / 'fifo')
    (out / 'page.html').write_text('page')
if config.get('HOLD'):
    time.sleep(300)
if config.get('BACKGROUND'):
    children = []
    for cwd, new_session in [(os.getcwd(), True), ('/', True), (os.environ['CLAUDE_CODE_TMPDIR'], True), ('/', False)]:
        children.append(subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'], cwd=cwd, start_new_session=new_session, env={k:v for k,v in os.environ.items() if cwd == '/' or k != 'DESIGNER_RUN'}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    Path(config['BACKGROUND']).write_text(json.dumps([p.pid for p in children]))
print(json.dumps({'result':'page and screenshots','session_id':'child-session','usage':json.loads(config.get('FAKE_USAGE', '{"input_tokens":12,"cache_creation_input_tokens":3,"cache_read_input_tokens":5,"output_tokens":7}'))}))
sys.exit(int(config.get('FAKE_EXIT','0')))
''')
    fake.chmod(0o755)
    prompt = tmp / 'prompt'
    prompt.write_text('build the named states')
    # No real claude on PATH: a failed launch of the fake must not fall through to one.
    system = os.pathsep.join(dict.fromkeys([os.path.dirname(sys.executable), '/usr/bin', '/bin', '/usr/sbin', '/sbin']))
    assert shutil.which('claude', path=system) is None, 'a real claude is on the test PATH'
    env = dict(os.environ, PATH=str(tmp / 'bin') + os.pathsep + system,
               AGENTIC_LOG_DIR=str(tmp / 'log'), CLAUDE_CODE_SESSION_ID='parent-session', RECORD=str(tmp / 'record'))
    env.pop('ANTHROPIC_AUTH_TOKEN', None)
    env.update(ANTHROPIC_API_KEY='test-value', CLAUDE_CODE_OAUTH_TOKEN='test-value', ORDINARY='dropped', LC_MESSAGES='C')
    scrubbed = ('GH_TOKEN','GITHUB_TOKEN','GH_ENTERPRISE_TOKEN','GITHUB_ENTERPRISE_TOKEN',
                'AWS_SECRET_ACCESS_KEY','SSH_AUTH_SOCK','GIT_ASKPASS','MY_PASSWORD','CLAUDECODE',
                'OP_SESSION_test','DATABASE_URL','CLAUDE_CONFIG_DIR')
    env.update({key:'test-value' for key in scrubbed})
    tool = str(root / 'bin/designer-run')
    def configure(extra=None):
        (tmp / 'config').write_text(json.dumps(dict(RECORD=str(tmp / 'record'), **(extra or {}))))
    def run(*args, extra=None):
        configure(extra)
        before = len(logs())
        result = subprocess.run([tool, '--prompt-file', str(prompt), *args], env=env, capture_output=True, text=True)
        added = logs()[before:]
        assert [e['decision'] for e in added] in ([], ['launch', 'finished']), added
        return result
    def logs():
        path = tmp / 'log/launch-log.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
    sequence = 0
    def fresh():
        global sequence
        sequence += 1
        return tmp / ('out-%d' % sequence)
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
        'autoAllowBashIfSandboxed':True, 'network':{'allowedDomains':[]},
        'filesystem':{'denyRead':['~'], 'allowRead':[str(out),'~/Library/Caches/ms-playwright'],
            'denyWrite':['/tmp/claude','/private/tmp/claude','~/.npm','~/.claude/debug']},
        'credentials':{'envVars':[{'name':key,'mode':'deny'} for key in ('ANTHROPIC_API_KEY','CLAUDE_CODE_OAUTH_TOKEN')]}}}
    assert settings == expected
    assert not any(key in recorded['env'] for key in scrubbed)
    assert recorded['env']['ANTHROPIC_API_KEY'] == recorded['env']['CLAUDE_CODE_OAUTH_TOKEN'] == 'test-value'
    allowed = {'PATH','HOME','USER','LOGNAME','SHELL','LANG','TERM','TZ',
               'ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN'}
    expected_env = {k:v for k,v in env.items() if k in allowed or k.startswith('LC_')}
    expected_env.update(DESIGNER_RUN=report.stem, CLAUDE_CODE_TMPDIR=recorded['env']['CLAUDE_CODE_TMPDIR'],
                        CLAUDE_CODE_DISABLE_CLAUDE_MDS='1', CLAUDE_CODE_DISABLE_AUTO_MEMORY='1')
    assert recorded['env'] == expected_env, set(recorded['env']) ^ set(expected_env)
    help_env = dict(expected_env)
    del help_env['CLAUDE_CODE_TMPDIR']
    assert json.loads((tmp / 'record-help').read_text()) == help_env
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
                                '--allowedTools', 'Read', 'Grep', 'Glob',
                                'Edit(/%s/**)' % out, 'Write(/%s/**)' % out,
                                '--disallowedTools', 'NotebookEdit', '--permission-mode', 'dontAsk']
    rules = (root / 'RULES.md').read_text().strip()
    body = re.sub(r'\A---\n.*?\n---\n', '', (root / 'agents/designer.md').read_text(), flags=re.S).strip()
    assert recorded['stdin'] == rules + '\n\n---\n\n' + body + '\n\n---\n\n' + prompt.read_text() + '\n\nOutput folder: ' + str(out) + '\n'
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
    assert run('--out', str(fresh()), extra={'FAKE_USAGE':json.dumps(invalid)}).returncode == 0
    assert all(logs()[-1][k] is None for k in ('input_tokens','cache_creation_input_tokens','cache_read_input_tokens','output_tokens'))
    result = run('--out', str(fresh()), extra={'FAKE_EXIT':'3'})
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
        refused('--out', str(fresh()), extra={'MISSING_FLAG':flag})
    source = tmp / 'style.md'
    source.write_text('project style')
    out = fresh()
    assert run('--out', str(out), '--read', str(source)).returncode == 0
    assert (out / 'input/style.md').read_text() == source.read_text()
    recorded = json.loads((tmp / 'record').read_text())
    assert recorded['stdin'].endswith('Output folder: %s\nProject file: %s\n' % (out, out / 'input/style.md'))
    assert str(source) not in recorded['stdin']
    symlink = tmp / 'source-link'
    symlink.symlink_to(source)
    hidden = tmp / '.hidden'
    hidden.write_text('private')
    other = tmp / 'other'
    other.mkdir()
    (other / source.name).write_text('other style')
    for files in ((str(symlink),), (str(hidden),), (str(other),), (str(tmp / 'missing'),), (str(source), str(other / source.name))):
        refused('--out', str(fresh()), *[arg for file in files for arg in ('--read', file)])
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
    occupied = fresh()
    occupied.mkdir()
    (occupied / 'page').write_text('page')
    refused('--out', str(occupied))
    target = tmp / 'outside-file'
    target.write_text('untouched')
    links_out = fresh()
    result = run('--out', str(links_out), extra={'LINKS':str(target)})
    assert result.returncode == 0 and len(result.stderr.splitlines()) == 1, result.stderr
    assert sorted(p.name for p in links_out.iterdir()) == ['page.html']
    assert target.read_text() == 'untouched' and target.stat().st_nlink == 1
    assert logs()[-1]['removed'] == 3
    temp_before = set(Path('/tmp').glob('designer.*'))
    result = run('--out', str(fresh()), extra={'LAUNCH_ERROR':True})
    assert result.returncode == 2 and logs()[-1]['exit_code'] == 2, (result.returncode, result.stderr, logs()[-1])
    assert 'Permission denied' in logs()[-1]['error'] and 'unreadable result' not in logs()[-1]['error'], logs()[-1]
    assert set(Path('/tmp').glob('designer.*')) == temp_before
    fake.chmod(0o755)
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        (tmp / 'record').unlink(missing_ok=True)
        configure({'HOLD':'1'})
        before = len(logs())
        runner = subprocess.Popen([tool, '--prompt-file', str(prompt), '--out', str(fresh())],
                                  env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not (tmp / 'record').exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            assert (tmp / 'record').exists(), 'child did not start'
            runner.send_signal(sig)
            output = runner.communicate(timeout=10)
            assert runner.returncode == 128 + sig, (sig, runner.returncode, output[1])
            check_temp(json.loads((tmp / 'record').read_text()))
            assert [e['decision'] for e in logs()[before:]] == ['launch','finished']
            assert 'stopped' in logs()[-1]
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
    out = fresh()
    out.mkdir()
    unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'], cwd=out,
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
