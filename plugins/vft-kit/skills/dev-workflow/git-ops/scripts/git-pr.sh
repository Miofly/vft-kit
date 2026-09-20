#!/usr/bin/env bash
# Deliver an already committed branch. No staging, commits, branch changes or remote rewrites.
# Requires Python 3.9+ (stdlib), git and gh/glab for the selected platform.
set -euo pipefail
exec python3 - "$@" <<'PY'
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote, urlsplit


def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def run(*args, check=True):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        # Do not echo argv/remote stderr: either may contain credentials.
        fail(f'{args[0]} {args[1]} 失败（退出码 {result.returncode}）；请在本地检查，勿盲目重试。')
    return result


def output(*args):
    return run(*args).stdout.decode('utf-8').strip()


def data(*args):
    return json.loads(output(*args))


def main():
    parser = argparse.ArgumentParser(description='推送已提交分支并创建/复用 PR；不暂存、不提交、不切分支。')
    parser.add_argument('--base', help='目标分支，默认使用本地 origin/HEAD')
    parser.add_argument('--title', required=True)
    parser.add_argument('--body-file', required=True, type=Path)
    parser.add_argument('--draft', action='store_true')
    parser.add_argument('--dry-run', action='store_true', help='仅本地预检，不联网或写入仓库')
    args = parser.parse_args()
    if not args.title.strip() or '\n' in args.title or '\r' in args.title:
        parser.error('标题必须是非空单行')
    try:
        body = args.body_file.read_text(encoding='utf-8')
    except (OSError, UnicodeError):
        parser.error('正文文件不可读或不是 UTF-8')
    if not body.strip():
        parser.error('正文不能为空')

    output('git', 'rev-parse', '--show-toplevel')
    branch = output('git', 'branch', '--show-current')
    if not branch:
        fail('当前为 detached HEAD；请明确目标分支。')
    head = output('git', 'rev-parse', '--verify', 'HEAD')
    for marker in ('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer'):
        if Path(output('git', 'rev-parse', '--git-path', marker)).exists():
            fail('存在未结束的 Git 操作，请先完成或按授权中止。')
    if output('git', 'status', '--porcelain', '--untracked-files=all'):
        fail('存在未提交修改；先核对并提交授权范围，脚本不会自动暂存或提交。')

    remote = output('git', 'remote', 'get-url', 'origin')
    push_urls = output('git', 'remote', 'get-url', '--push', '--all', 'origin').splitlines()
    if push_urls != [remote]:
        fail('origin 推送与读取地址不同或有多个推送地址；请使用明确目标的手动流程。')
    match = re.fullmatch(r'git@([^:]+):(.+)', remote)
    if match:
        host, repo = match.groups()
    else:
        parsed = urlsplit(remote)
        if parsed.scheme not in ('https', 'ssh') or parsed.password or parsed.port or parsed.query or parsed.fragment:
            fail('不支持的 remote 格式或包含凭据；请使用平台手动流程。')
        if parsed.scheme == 'https' and parsed.username:
            fail('remote 内含认证信息；不将其传入平台 CLI。')
        host, repo = parsed.hostname, parsed.path.lstrip('/')
    repo = repo.removesuffix('.git')
    if host not in ('github.com', 'gitlab.com', 'gitee.com') or not re.fullmatch(r'[\w.-]+(?:/[\w.-]+)+', repo):
        fail('脚本仅支持标准 GitHub/GitLab/Gitee 同仓库；其他目标使用平台手动流程。')
    if args.draft and host == 'gitee.com':
        parser.error('Gitee 路径仅提供待创建链接，不支持 --draft')

    base = args.base
    if not base:
        ref = output('git', 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD')
        base = ref.removeprefix('origin/')
    if base.startswith('-') or run('git', 'check-ref-format', f'refs/heads/{base}', check=False).returncode:
        parser.error('无效目标分支')
    if branch == base:
        fail('当前分支就是 PR 目标；脚本不会自动创建分支。')
    base_ref = f'refs/remotes/origin/{base}'
    if not args.dry_run:
        run('git', 'fetch', '--no-tags', 'origin', f'+refs/heads/{base}:{base_ref}')
    output('git', 'rev-parse', '--verify', base_ref)
    output('git', 'merge-base', base_ref, head)
    if output('git', 'rev-list', '--count', f'{base_ref}..{head}') == '0':
        fail('当前分支没有待交付提交。')
    if run('git', 'diff', '--quiet', f'{base_ref}...{head}', check=False).returncode == 0:
        fail('当前分支相对目标没有最终文件差异。')
    run('git', 'diff', '--check', f'{base_ref}...{head}')

    # Check history too: a secret added then deleted is still pushed.
    paths = run('git', 'log', '-m', '--format=', '--name-only', '-z', '--diff-filter=AM',
                '--no-renames', f'{base_ref}..{head}').stdout.split(b'\0')
    for raw in paths:
        path = raw.lstrip(b'\n').decode('utf-8', errors='surrogateescape')
        name = path.rsplit('/', 1)[-1]
        if name in ('.env.example', '.env.sample', '.env.template'):
            continue
        if name == '.env' or name.startswith('.env.') or name in ('id_rsa', 'id_ed25519', 'credentials.json') or name.endswith(('.pem', '.key', '.p12')):
            fail('待推送历史包含疑似敏感文件；请在本地检查并清理，未推送。', 3)

    print(f'{branch} → {base} | HEAD {head}', flush=True)
    if args.dry_run:
        print('本地预检通过；未联网，未验证远端权限、引用新鲜度或内容安全。')
        print(args.title)
        print(body)
        return

    github = host == 'github.com'
    cli = 'gh' if github else 'glab'

    def find_existing():
        if github:
            return data('gh', 'pr', 'list', '--repo', repo, '--state', 'open', '--head', branch,
                        '--base', base, '--json', 'number,url')
        return data('glab', 'mr', 'list', '--repo', repo, '--source-branch', branch,
                    '--target-branch', base, '--output', 'json')

    existing = [] if host == 'gitee.com' else find_existing()
    if len(existing) > 1:
        fail('发现多个匹配 PR/MR，请先明确目标。')
    # Freeze the refspec at the reviewed SHA; disable automatic tag following.
    if output('git', 'rev-parse', 'HEAD') != head or output('git', 'status', '--porcelain'):
        fail('预检后仓库状态发生变化，请重新检查。')
    run('git', '-c', 'push.followTags=false', 'push', 'origin', f'{head}:refs/heads/{branch}')
    remote_head = output('git', 'ls-remote', '--heads', 'origin', f'refs/heads/{branch}').split()
    if not remote_head or remote_head[0] != head:
        fail('远端分支 SHA 与预期不一致，停止创建 PR。')
    if host == 'gitee.com':
        print(f'分支已推送；PR 尚未创建：https://gitee.com/{repo}/compare/{quote(base, safe="")}...{quote(branch, safe="")}')
        return

    created = not existing
    if created:
        if github:
            command = ['gh', 'pr', 'create', '--repo', repo, '--base', base, '--head', branch,
                       '--title', args.title, '--body-file', str(args.body_file.resolve())]
        else:
            command = ['glab', 'mr', 'create', '--repo', repo, '--source-branch', branch,
                       '--target-branch', base, '--title', args.title, '--description', body, '--yes']
        if args.draft:
            command.append('--draft')
        result = run(*command, check=False)
        # Always query after create, including timeout/failure; never blindly recreate.
        existing = find_existing()
        if len(existing) != 1:
            fail(f'创建后未查到唯一 PR/MR（create 退出码 {result.returncode}）；请回查，勿直接重复创建。')
    number = str(existing[0]['number' if github else 'iid'])
    if github:
        pr = data(cli, 'pr', 'view', number, '--repo', repo, '--json',
                  'url,state,baseRefName,headRefName,headRefOid,isDraft,title,body')
        actual = (pr['baseRefName'], pr['headRefName'], pr['headRefOid'], pr['state'])
        expected = (base, branch, head, 'OPEN')
        actual_body, draft, url = pr['body'], pr['isDraft'], pr['url']
    else:
        pr = data(cli, 'mr', 'view', number, '--repo', repo, '--output', 'json')
        actual = (pr['target_branch'], pr['source_branch'], pr['sha'], pr['state'])
        expected = (base, branch, head, 'opened')
        actual_body, draft, url = pr['description'], pr['draft'], pr['web_url']
    if actual != expected:
        fail('PR/MR 回读的分支、SHA 或状态不符；已推送，请回查。')
    if created and (actual_body.rstrip() != body.rstrip() or draft != args.draft):
        fail('PR/MR 已创建，但正文或草稿状态回读不符，请回查。')
    print(('已创建并验证：' if created else '已复用并验证（保留原描述）：') + url)
    print('CI 与合并状态未验证。')


try:
    main()
except (OSError, ValueError, KeyError, TypeError) as error:
    fail(f'环境或平台返回数据异常（{type(error).__name__}）；请检查现状后再重试。')
PY
