"""Exercise the real launcher scripts without connecting to the production host."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

remote_script, web_script = map(Path, sys.argv[1:])
bash = '/bin/bash' if not (path := __import__('shutil').which('bash')) else path
with tempfile.TemporaryDirectory(prefix='aiboard-ssh-check-') as temp:
    directory = Path(temp)
    log = directory / 'commands.jsonl'
    fake = '''import json, os, sys
from pathlib import Path
exe = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['AIBOARD_TEST_LOG'], 'a', encoding='utf-8') as out:
    print(json.dumps([exe, *args]), file=out)
if exe == 'ssh' and args[:2] == ['-T', '--']:
    shell = os.environ['AIBOARD_TEST_BASH']
    os.execve(shell, [shell, '-c', args[-1]], os.environ)
if exe == 'ssh' and '-O' in args:
    sys.exit(1)
'''
    for executable in ('ssh', 'aiboard', 'xdg-open'):
        launcher = directory / executable
        launcher.write_text(f'#!{sys.executable}\n' + fake, encoding='utf-8')
        launcher.chmod(0o700)
    env = os.environ | {
        'PATH': str(directory) + ':' + os.environ['PATH'],
        'AIBOARD_TEST_LOG': str(log),
        'AIBOARD_TEST_BASH': bash,
        'AIBOARD_DEFAULT_SSH_HOST': 'test@desktop-ts',
        'XDG_RUNTIME_DIR': str(directory),
    }
    env.pop('AIBOARD_SSH_HOST', None)
    marker = directory / 'must-not-exist'
    payload = "日本語 'quoted'\n$(touch " + shlex.quote(str(marker)) + ")"
    subprocess.run([bash, '-e', str(remote_script), 'reply', '42', payload], env=env, check=True)
    subprocess.run([bash, '-e', str(web_script)], env=env, check=True)
    commands = [json.loads(row) for row in log.read_text(encoding='utf-8').splitlines()]
    assert commands[0][:4] == ['ssh', '-T', '--', 'test@desktop-ts'], commands[0]
    assert commands[1] == ['aiboard', 'reply', '42', payload], commands[1]
    assert commands[2][-3:] == ['check', '--', 'test@desktop-ts'], commands[2]
    assert '127.0.0.1:25280:127.0.0.1:15280' in commands[3], commands[3]
    assert commands[4] == ['xdg-open', 'http://127.0.0.1:25280/'], commands[4]
    assert not marker.exists()
    print('SSH launcher: argument preservation and loopback forwarding passed')
