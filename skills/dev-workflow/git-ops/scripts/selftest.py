#!/usr/bin/env python3
"""Offline regression: real temporary Git repos, mocked hosting CLIs, no user config/network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).with_name('git-pr.sh')
REAL_GIT = shutil.which('git')
BASH = shutil.which('bash')

# The wrapper redirects only transport to a local bare repo. All other Git behavior is real.
MOCK = r'''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
kind = Path(sys.argv[0]).name
with open(os.environ['CALLS'], 'a') as log:
    log.write(json.dumps([kind, *args]) + '\n')
if kind == 'git':
    if os.environ.get('SCENARIO') == 'push-fails' and 'push' in args[:3]:
        print('TEST_PRIVATE_ERROR_VALUE', file=sys.stderr)
        sys.exit(1)
    if any(command in args[:3] for command in ('fetch', 'push', 'ls-remote')):
        args = [os.environ['BARE'] if a == 'origin' else a for a in args]
    sys.exit(subprocess.run([os.environ['REAL_GIT'], *args]).returncode)
mode = os.environ.get('SCENARIO', '')
created = Path(os.environ['CREATED'])
github = kind == 'gh'
expected_repo = 'https://' + ('github.com' if github else 'gitlab.com') + '/team/repo'
if mode == 'explicit-host' and args[args.index('--repo') + 1] != expected_repo:
    sys.exit(8)
identity = {'isCrossRepository': False} if github else {'source_project_id': 1, 'target_project_id': 1}
foreign = {'isCrossRepository': True} if github else {'source_project_id': 2, 'target_project_id': 1}
if args[1] == 'list':
    if mode == 'query-fails': sys.exit(4)
    if mode == 'body-changed': Path(os.environ['BODY']).write_text('changed during query')
    if not created.exists():
        if mode == 'branch-changed':
            subprocess.run([os.environ['REAL_GIT'], 'switch', '-q', 'other'], check=True)
        if mode == 'remote-changed':
            subprocess.run([os.environ['REAL_GIT'], 'remote', 'set-url', 'origin', 'https://github.com/other/repo.git'], check=True)
        if mode == 'untracked-added': Path('concurrent.txt').write_text('keep this edit')
    exists = created.exists() or mode == 'existing'
    result = [{'number' if github else 'iid': 7, **identity}] if exists else []
    if mode == 'foreign-branch': result.append({'number' if github else 'iid': 8, **foreign})
    if mode == 'full-page': result = [{'number' if github else 'iid': i, **identity} for i in range(100)]
    if mode == 'invalid-list': result = {'message': 'unexpected response'}
    print(json.dumps(result))
elif args[1] == 'create':
    if github:
        body_path = args[args.index('--body-file') + 1]
        sent_body = sys.stdin.read() if body_path == '-' else Path(body_path).read_text()
    else:
        sent_body = args[args.index('--description') + 1]
    if mode != 'create-fails':
        created.write_text(json.dumps({'args': args, 'body': sent_body}))
    sys.exit(1 if mode in ('timeout-created', 'create-fails') else 0)
elif args[1] == 'view':
    sha = subprocess.check_output([os.environ['REAL_GIT'], 'rev-parse', 'HEAD'], text=True).strip()
    if mode == 'wrong-sha': sha = '0' * 40
    sent = json.loads(created.read_text()) if created.exists() else None
    body = sent['body'] if sent else Path(os.environ['BODY']).read_text()
    if mode == 'wrong-body': body = 'unexpected'
    draft = bool(sent and '--draft' in sent['args'])
    title = sent['args'][sent['args'].index('--title') + 1] if sent else 'existing title'
    if not github and draft: title = 'Draft: ' + title
    if mode == 'wrong-title': title = 'unexpected title'
    if github:
        result = dict(url='https://github.com/team/repo/pull/7', state='OPEN',
                      baseRefName='main', headRefName='feature', headRefOid=sha,
                      isDraft=draft, title=title, body=body, **identity)
    else:
        result = dict(web_url='https://gitlab.com/team/repo/-/merge_requests/7', state='opened',
                      target_branch='main', source_branch='feature', sha=sha, draft=draft,
                      title=title, description=body, **identity)
    if mode == 'foreign-view': result.update(foreign)
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
        (bin_dir / 'python3').symlink_to(sys.executable)
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
        git('branch', 'other')

        cases = 0

        def check(expected=0, mode='', extra=(), no_transport=False, body_text=None, message=None):
            nonlocal cases
            Path(env['CALLS']).write_text('')
            Path(env['CREATED']).unlink(missing_ok=True)
            body.write_text(body_text if body_text is not None else '## Behavior\n\nLiteral `code` and $(do-not-execute).\n')
            before = (git('rev-parse', 'HEAD'), git('status', '--porcelain'), git('remote', 'get-url', 'origin'))
            result = subprocess.run([BASH, str(SCRIPT), '--title', 'fix: preserve behavior',
                                     '--body-file', str(body), *extra], cwd=repo,
                                    env={**env, 'SCENARIO': mode}, text=True, capture_output=True)
            assert result.returncode == expected, (mode, result.returncode, result.stdout, result.stderr)
            assert 'TEST_PRIVATE_ERROR_VALUE' not in result.stdout + result.stderr
            if message:
                assert message in result.stderr, result.stderr
            if mode == 'branch-changed':
                assert git('branch', '--show-current') == 'other'
            elif mode == 'remote-changed':
                assert git('remote', 'get-url', 'origin') == 'https://github.com/other/repo.git'
            elif mode == 'untracked-added':
                assert (repo / 'concurrent.txt').read_text() == 'keep this edit'
            else:
                assert before == (git('rev-parse', 'HEAD'), git('status', '--porcelain'), git('remote', 'get-url', 'origin'))
            calls = [json.loads(line) for line in Path(env['CALLS']).read_text().splitlines()]
            if no_transport:
                assert not any(c[0] != 'git' or any(v in c[1:4] for v in ('fetch', 'push', 'ls-remote')) for c in calls)
            creates = sum(c[:3] in (['gh', 'pr', 'create'], ['glab', 'mr', 'create']) for c in calls)
            assert creates <= 1
            if mode in ('existing', 'query-fails', 'push-fails'):
                assert creates == 0
            if mode == 'query-fails':
                assert not any('push' in c[1:4] for c in calls)
            if mode in ('foreign-branch', 'explicit-host', 'body-changed'):
                assert creates == 1
            if mode in ('full-page', 'invalid-list', 'branch-changed', 'remote-changed', 'untracked-added'):
                assert not any('push' in c[1:4] for c in calls)
            cases += 1
            return result.stdout

        check(extra=('--dry-run',), no_transport=True)
        saved_path = env['PATH']
        env['PATH'] = str(bin_dir)
        (bin_dir / 'gh').rename(bin_dir / 'gh.disabled')
        check(1, no_transport=True, message='未找到 gh')
        check(extra=('--dry-run',), no_transport=True)
        (bin_dir / 'gh.disabled').rename(bin_dir / 'gh')
        env['PATH'] = saved_path
        check(2, extra=('--base',), no_transport=True)
        check(2, body_text='bad\0body', no_transport=True, message='NUL')
        git('symbolic-ref', '--delete', 'refs/remotes/origin/HEAD')
        check(1, extra=('--dry-run',), no_transport=True, message='--base')
        git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
        git('update-ref', '-d', 'refs/remotes/origin/main')
        check(1, extra=('--dry-run',), no_transport=True, message='git fetch origin')
        git('update-ref', 'refs/remotes/origin/main', 'main')
        (repo / 'unrelated.txt').write_text('keep me')
        check(1, extra=('--dry-run',), no_transport=True)
        (repo / 'unrelated.txt').unlink()
        check(mode='query-fails', expected=1)
        check(mode='push-fails', expected=1, message='不要自动强推')
        check(mode='branch-changed', expected=1)
        git('switch', '-q', 'feature')
        check(mode='remote-changed', expected=1)
        git('remote', 'set-url', 'origin', 'https://github.com/team/repo.git')
        git('config', 'status.showUntrackedFiles', 'no')
        check(mode='untracked-added', expected=1)
        (repo / 'concurrent.txt').unlink()
        git('config', '--unset', 'status.showUntrackedFiles')
        check()
        check(extra=('--draft',))
        check(mode='existing')
        check(mode='timeout-created')
        check(mode='create-fails', expected=1)
        check(mode='wrong-sha', expected=1)
        check(mode='wrong-body', expected=1)
        check(mode='wrong-title', expected=1)
        check(mode='foreign-branch')
        check(mode='foreign-view', expected=1)
        check(mode='explicit-host')
        check(mode='body-changed')
        check(mode='full-page', expected=1)
        check(mode='invalid-list', expected=1)
        git('remote', 'set-url', 'origin', 'https://gitlab.com/team/repo.git')
        check()
        check(extra=('--draft',))
        check(mode='existing')
        check(mode='wrong-title', expected=1)
        check(mode='foreign-branch')
        check(mode='foreign-view', expected=1)
        check(mode='explicit-host')
        check(mode='body-changed')
        check(mode='full-page', expected=1)
        check(mode='invalid-list', expected=1)
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
