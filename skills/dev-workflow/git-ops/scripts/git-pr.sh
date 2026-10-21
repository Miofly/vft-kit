#!/usr/bin/env bash
# Deliver an already committed branch. No staging, commits, branch changes or remote rewrites.
# Requires Python 3.9+ (stdlib), git and gh/glab for the selected platform.
set -euo pipefail
exec python3 - "$@" <<'PY'
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote, urlsplit


def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def run(*args, check=True, stdin=None):
    try:
        result = subprocess.run(args, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        fail(f'未找到 {args[0]}；请先配置该工具，脚本不会自动安装。')
    if check and result.returncode:
        # Do not echo argv/remote stderr: either may contain credentials.
        operation = args[3] if args[1] == '-c' else args[1]
        hint = {
            ('git', 'fetch'): '检查网络、origin 读取权限及目标分支是否存在。',
            ('git', 'push'): '检查写权限、保护规则及 non-fast-forward；不要自动强推。',
            ('git', 'ls-remote'): '推送可能已完成，先回查远端分支 SHA，不要重复创建 PR。',
            ('gh', 'pr'): '本地检查 gh auth status --hostname github.com 和仓库权限；若已创建，先回查 PR。',
            ('glab', 'mr'): '本地检查 glab auth status --hostname gitlab.com 和仓库权限；若已创建，先回查 MR。',
        }.get((args[0], operation), '请在本地检查仓库及引用状态，勿盲目重试。')
        fail(f'{args[0]} {operation} 失败（退出码 {result.returncode}）；{hint}')
    return result


def output(*args):
    return run(*args).stdout.decode('utf-8').strip()


def data(*args):
    return json.loads(output(*args))


def main():
    if sys.version_info < (3, 9):
        fail('需要 Python 3.9+；请使用已有的兼容解释器。')
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
    if '\0' in body:
        parser.error('正文不能包含 NUL 字符')

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
    if not args.dry_run and host != 'gitee.com':
        required_cli = 'gh' if host == 'github.com' else 'glab'
        if not shutil.which(required_cli):
            fail(f'未找到 {required_cli}；请先配置该工具，或使用 --dry-run 只做本地预检。')

    base = args.base
    if not base:
        ref = run('git', 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD', check=False)
        if ref.returncode:
            fail('未找到本地 origin/HEAD；请用 --base 显式指定目标分支。')
        base = ref.stdout.decode('utf-8').strip().removeprefix('origin/')
    if base.startswith('-') or run('git', 'check-ref-format', f'refs/heads/{base}', check=False).returncode:
        parser.error('无效目标分支')
    if branch == base:
        fail('当前分支就是 PR 目标；脚本不会自动创建分支。')
    base_ref = f'refs/remotes/origin/{base}'
    if not args.dry_run:
        run('git', 'fetch', '--no-tags', 'origin', f'+refs/heads/{base}:{base_ref}')
    if run('git', 'rev-parse', '--verify', base_ref, check=False).returncode:
        fail('缺少目标分支的本地远端引用；请先 git fetch origin，再核对 --base。')
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
    # Include the host so GITHUB_HOST/GITLAB_HOST cannot redirect platform operations.
    platform_repo = f'https://{host}/{repo}'

    def same_repository(pr):
        if github:
            if type(pr['isCrossRepository']) is not bool:
                fail('平台返回的仓库身份无效，停止操作。')
            return not pr['isCrossRepository']
        if any(type(pr[key]) is not int or pr[key] <= 0 for key in ('source_project_id', 'target_project_id')):
            fail('平台返回的项目身份无效，停止操作。')
        return pr['source_project_id'] == pr['target_project_id']

    def find_existing():
        if github:
            candidates = data('gh', 'pr', 'list', '--repo', platform_repo, '--state', 'open', '--head', branch,
                              '--base', base, '--limit', '100', '--json', 'number,url,isCrossRepository')
        else:
            candidates = data('glab', 'mr', 'list', '--repo', platform_repo, '--source-branch', branch,
                              '--target-branch', base, '--per-page', '100', '--output', 'json')
        if not isinstance(candidates, list) or any(not isinstance(pr, dict) for pr in candidates):
            fail('PR/MR 查询返回结构异常，停止操作。')
        # ponytail: stop on a full page; use explicit pagination if this limit is reached.
        if len(candidates) >= 100:
            fail('PR/MR 候选达到查询上限，不能确认是否重复；请分页核对。')
        return [pr for pr in candidates if same_repository(pr)]

    existing = [] if host == 'gitee.com' else find_existing()
    if len(existing) > 1:
        fail('发现多个匹配 PR/MR，请先明确目标。')
    # Freeze the refspec at the reviewed SHA; disable automatic tag following.
    if (output('git', 'rev-parse', 'HEAD') != head
            or output('git', 'branch', '--show-current') != branch
            or output('git', 'status', '--porcelain', '--untracked-files=all')
            or output('git', 'remote', 'get-url', 'origin') != remote
            or output('git', 'remote', 'get-url', '--push', '--all', 'origin').splitlines() != push_urls):
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
            command = ['gh', 'pr', 'create', '--repo', platform_repo, '--base', base, '--head', branch,
                       '--title', args.title, '--body-file', '-']
        else:
            command = ['glab', 'mr', 'create', '--repo', platform_repo, '--source-branch', branch,
                       '--target-branch', base, '--title', args.title, '--description', body, '--yes']
        if args.draft:
            command.append('--draft')
        result = run(*command, check=False, stdin=body.encode('utf-8') if github else None)
        # Always query after create, including timeout/failure; never blindly recreate.
        existing = find_existing()
        if len(existing) != 1:
            fail(f'创建后未查到唯一 PR/MR（create 退出码 {result.returncode}）；请回查，勿直接重复创建。')
    number = str(existing[0]['number' if github else 'iid'])
    if github:
        pr = data(cli, 'pr', 'view', number, '--repo', platform_repo, '--json',
                  'url,state,baseRefName,headRefName,headRefOid,isDraft,title,body,isCrossRepository')
        actual = (pr['baseRefName'], pr['headRefName'], pr['headRefOid'], pr['state'])
        expected = (base, branch, head, 'OPEN')
        actual_body, draft, url = pr['body'], pr['isDraft'], pr['url']
    else:
        pr = data(cli, 'mr', 'view', number, '--repo', platform_repo, '--output', 'json')
        actual = (pr['target_branch'], pr['source_branch'], pr['sha'], pr['state'])
        expected = (base, branch, head, 'opened')
        actual_body, draft, url = pr['description'], pr['draft'], pr['web_url']
    if not same_repository(pr) or actual != expected:
        fail('PR/MR 回读的仓库、分支、SHA 或状态不符；已推送，请回查。')
    titles = {args.title}
    if not github and args.draft:
        titles.add(f'Draft: {args.title}')
    if created and (pr['title'] not in titles or actual_body.rstrip() != body.rstrip() or draft != args.draft):
        fail('PR/MR 已创建，但标题、正文或草稿状态回读不符，请回查。')
    print(('已创建并验证：' if created else '已复用并验证（保留原描述）：') + url)
    print('CI 与合并状态未验证。')


try:
    main()
except (OSError, ValueError, KeyError, TypeError) as error:
    fail(f'环境或平台返回数据异常（{type(error).__name__}）；请检查现状后再重试。')
PY
