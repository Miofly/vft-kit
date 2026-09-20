#!/usr/bin/env python3
"""Offline regression: real temporary Git repos, mocked hosting CLIs, no user config/network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SCRIPT = Path(__file__).with_name('git-pr.sh')
REAL_GIT = shutil.which('git')

# The wrapper redirects only transport to a local bare repo. All other Git behavior is real.
MOCK = r'''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
kind = Path(sys.argv[0]).name
with open(os.environ['CALLS'], 'a') as log:
    log.write(json.dumps([kind, *args]) + '\n')
if kind == 'git':
    if any(command in args[:3] for command in ('fetch', 'push', 'ls-remote')):
        args = [os.environ['BARE'] if a == 'origin' else a for a in args]
    sys.exit(subprocess.run([os.environ['REAL_GIT'], *args]).returncode)
mode = os.environ.get('SCENARIO', '')
created = Path(os.environ['CREATED'])
github = kind == 'gh'
if args[1] == 'list':
    if mode == 'query-fails': sys.exit(4)
    exists = created.exists() or mode == 'existing'
    print(json.dumps([{'number' if github else 'iid': 7}] if exists else []))
elif args[1] == 'create':
    if mode != 'create-fails': created.write_text(json.dumps(args))
    sys.exit(1 if mode in ('timeout-created', 'create-fails') else 0)
elif args[1] == 'view':
    sha = subprocess.check_output([os.environ['REAL_GIT'], 'rev-parse', 'HEAD'], text=True).strip()
    if mode == 'wrong-sha': sha = '0' * 40
    body = Path(os.environ['BODY']).read_text()
    if mode == 'wrong-body': body = 'unexpected'
    draft = created.exists() and '--draft' in json.loads(created.read_text())
    if github:
        result = dict(url='https://github.com/team/repo/pull/7', state='OPEN',
                      baseRefName='main', headRefName='feature', headRefOid=sha,
                      isDraft=draft, title='fix: preserve behavior', body=body)
    else:
        result = dict(web_url='https://gitlab.com/team/repo/-/merge_requests/7', state='opened',
                      target_branch='main', source_branch='feature', sha=sha, draft=draft,
                      title='fix: preserve behavior', description=body)
    print(json.dumps(result))
else:
    sys.exit(9)
'''


def main():
    with tempfile.TemporaryDirectory(prefix='git-ops-selftest-') as temp:
        root = Path(temp)
        repo, bare, bin_dir = root / 'repo', root / 'remote.git', root / 'bin'
        repo.mkdir()
        bin_dir.mkdir()
        env = {**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
               'GIT_TERMINAL_PROMPT': '0', 'REAL_GIT': REAL_GIT, 'BARE': str(bare),
               'CALLS': str(root / 'calls'), 'CREATED': str(root / 'created'),
               'BODY': str(root / 'body.md'), 'PATH': str(bin_dir) + os.pathsep + os.environ['PATH']}
        for key in tuple(env):
            if key.startswith(('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_', 'GIT_CONFIG_VALUE_')):
                env.pop(key)
        for name in ('git', 'gh', 'glab'):
            file = bin_dir / name
            file.write_text(MOCK)
            file.chmod(0o755)
        body = Path(env['BODY'])
        body.write_text('## Behavior\n\nLiteral `code` and $(do-not-execute).\n')

        def git(*args):
            result = subprocess.run([REAL_GIT, *args], cwd=repo, env=env, text=True, capture_output=True)
            assert result.returncode == 0, result.stderr
            return result.stdout.strip()

        git('init', '-q', '-b', 'main')
        git('config', 'user.email', 'selftest@example.invalid')
        git('config', 'user.name', 'Selftest')
        git('config', 'commit.gpgsign', 'false')
        git('config', 'core.hooksPath', str(root / 'no-hooks'))
        (repo / 'file.txt').write_text('base\n')
        git('add', 'file.txt')
        git('commit', '-qm', 'chore: initial')
        git('init', '--bare', '-q', str(bare))
        git('push', str(bare), 'main')
        git('remote', 'add', 'origin', 'https://github.com/team/repo.git')
        git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
        git('switch', '-qc', 'feature')
        (repo / 'file.txt').write_text('base\nfeature\n')
        git('add', 'file.txt')
        git('commit', '-qm', 'fix: preserve behavior')

        cases = 0

        def check(expected=0, mode='', extra=(), no_transport=False):
            nonlocal cases
            Path(env['CALLS']).write_text('')
            Path(env['CREATED']).unlink(missing_ok=True)
            before = (git('rev-parse', 'HEAD'), git('status', '--porcelain'), git('remote', 'get-url', 'origin'))
            result = subprocess.run(['bash', str(SCRIPT), '--title', 'fix: preserve behavior',
                                     '--body-file', str(body), *extra], cwd=repo,
                                    env={**env, 'SCENARIO': mode}, text=True, capture_output=True)
            assert result.returncode == expected, (mode, result.returncode, result.stdout, result.stderr)
            assert before == (git('rev-parse', 'HEAD'), git('status', '--porcelain'), git('remote', 'get-url', 'origin'))
            calls = [json.loads(line) for line in Path(env['CALLS']).read_text().splitlines()]
            if no_transport:
                assert not any(c[0] != 'git' or any(v in c[1:4] for v in ('fetch', 'push', 'ls-remote')) for c in calls)
            creates = sum(c[:3] in (['gh', 'pr', 'create'], ['glab', 'mr', 'create']) for c in calls)
            assert creates <= 1
            if mode in ('existing', 'query-fails'):
                assert creates == 0
            if mode == 'query-fails':
                assert not any('push' in c[1:4] for c in calls)
            cases += 1
            return result.stdout

        check(extra=('--dry-run',), no_transport=True)
        check(2, extra=('--base',), no_transport=True)
        (repo / 'unrelated.txt').write_text('keep me')
        check(1, extra=('--dry-run',), no_transport=True)
        (repo / 'unrelated.txt').unlink()
        check(mode='query-fails', expected=1)
        check()
        check(extra=('--draft',))
        check(mode='existing')
        check(mode='timeout-created')
        check(mode='create-fails', expected=1)
        check(mode='wrong-sha', expected=1)
        check(mode='wrong-body', expected=1)
        git('remote', 'set-url', 'origin', 'https://gitlab.com/team/repo.git')
        check()
        check(extra=('--draft',))
        check(mode='existing')
        git('remote', 'set-url', 'origin', 'https://gitee.com/team/repo.git')
        assert 'PR 尚未创建' in check()
        check(2, extra=('--draft', '--dry-run'), no_transport=True)
        git('switch', '-q', 'main')
        check(1, extra=('--dry-run',), no_transport=True)
        git('switch', '-q', 'feature')
        git('switch', '-q', '--detach')
        check(1, extra=('--dry-run',), no_transport=True)
        git('switch', '-q', 'feature')
        marker = repo / '.git' / 'MERGE_HEAD'
        marker.write_text(git('rev-parse', 'main') + '\n')
        check(1, extra=('--dry-run',), no_transport=True)
        marker.unlink()
        (repo / '.env').write_text('DEMO=fake-test-value\n')
        git('add', '.env')
        git('commit', '-qm', 'chore: test history')
        git('rm', '-q', '.env')
        git('commit', '-qm', 'chore: remove test file')
        check(3, extra=('--dry-run',), no_transport=True)
        print(f'PASS: {cases} offline cases; local Git transport + mocked gh/glab; no external PRs created.')


if __name__ == '__main__':
    main()
