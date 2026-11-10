#!/usr/bin/env python3
"""Archive cached wxapkg code, split desktop wrappers, and preserve visited Cocos assets.

Never executes target JavaScript or changes WeChat data. Remote bundle configs are
optional public downloads via wget; this is not an original Cocos project export.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit

WXID = re.compile(r"wx[0-9a-f]{16}")
# Desktop entry wrappers may follow the loader's }; on the same line.
MODULE = re.compile(r'(?:^\s*|(?<=;)[ \t]*)define\("([^"\n]+)", function\(require, module, exports\)\{', re.M)


def inside(root, name):
    rel = Path(name)
    if rel.is_absolute() or not rel.parts or any(p == '..' for p in rel.parts):
        raise ValueError(f'unsafe relative path: {name}')
    target = (root / rel).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError(f'path escapes output: {name}')
    return target


def put_copy(src, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def split_modules(unpacked, dest):
    count = 0
    seen = set()
    for source in sorted(unpacked.rglob('game.js')):
        text = source.read_text()
        hits = list(MODULE.finditer(text))
        for i, match in enumerate(hits):
            name = match.group(1)
            if name in seen:
                raise ValueError(f'duplicate module: {name}')
            seen.add(name)
            target = inside(dest, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            end = hits[i + 1].start() if i + 1 < len(hits) else len(text)
            target.write_text(text[match.start():end])
            count += 1
    if not count:
        raise ValueError('no supported desktop define wrappers; original unpacked files retained')
    return count


def resource_path(url):
    parsed = urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('expected public HTTPS resource URL')
    if parsed.query or parsed.fragment:
        raise ValueError('signed/query URLs are not archived by this tool')
    return parsed.hostname + '/' + unquote(parsed.path).lstrip('/')


def copy_assets(user_dir, dest):
    index = user_dir / 'usr/gamecaches/cacheList.json'
    if not index.exists():
        raise ValueError('missing cacheList.json; visit the game before exporting resources')
    files = json.loads(index.read_text()).get('files', {})
    count, missing = 0, []
    for url, entry in files.items():
        local = entry.get('url', '')
        if not local.startswith('wxfile://usr/'):
            raise ValueError('unsupported cache path; expected wxfile://usr/')
        src = inside(user_dir, local.removeprefix('wxfile://'))
        target = inside(dest, resource_path(url))
        if not src.is_file():
            missing.append(url)
            continue
        put_copy(src, target)
        count += 1
    return count, missing


def download_configs(unpacked, dest, proxy):
    result = []
    for settings in sorted(unpacked.glob('src/settings*.json')):
        assets = json.loads(settings.read_text()).get('assets', {})
        server = assets.get('server', '').rstrip('/')
        for bundle in assets.get('remoteBundles', []):
            version = assets.get('bundleVers', {}).get(bundle)
            if not re.fullmatch(r'[\w-]+', bundle) or (version and not re.fullmatch(r'[\w-]+', version)):
                raise ValueError('unsafe bundle name or version')
            suffix = f'.{version}' if version else ''
            url = f'{server}/remote/{bundle}/config{suffix}.json'
            target = inside(dest, resource_path(url))
            target.parent.mkdir(parents=True, exist_ok=True)
            # Keep an interrupted transfer separate from a validated JSON file.
            partial = target.with_name(target.name + '.part')
            cmd = ['wget', '-q', '-c', '--tries=2', '--timeout=25', '-O', str(partial)]
            if proxy:
                cmd += ['-e', 'use_proxy=yes', '-e', f'https_proxy={proxy}']
            else:
                cmd += ['-e', 'use_proxy=no']
            subprocess.run(cmd + [url], check=True, timeout=65)
            config = json.loads(partial.read_text())
            if config.get('name') != bundle:
                raise ValueError(f'unexpected bundle config: {bundle}')
            partial.replace(target)
            result.append({'bundle': bundle, 'url': url, 'path': str(target.relative_to(dest))})
    return result


def inventory(root):
    result = []
    for p in sorted(root.rglob('*')):
        if p.is_file() and p.name != 'manifest.json':
            result.append({'path': str(p.relative_to(root)), 'bytes': p.stat().st_size,
                           'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
    return result


def export(args):
    packages = Path(args.packages).resolve()
    user_dir = Path(args.user_dir).resolve()
    output = Path(args.output).resolve()
    if not WXID.fullmatch(args.wxid):
        raise ValueError('invalid wxid')
    if not packages.is_dir() or not user_dir.is_dir():
        raise ValueError('package version and user data directories must exist')
    if packages.parent.name != args.wxid or user_dir.name != args.wxid:
        raise ValueError('package and user directories must match the supplied wxid')
    if output.exists():
        raise ValueError('output already exists; use a fresh directory to preserve prior exports')
    if output.is_relative_to(packages) or output.is_relative_to(user_dir):
        raise ValueError('output must be outside WeChat input directories')
    sources = sorted(packages.glob('*.wxapkg'))
    if not sources:
        raise ValueError('no wxapkg files')
    output.mkdir(parents=True)
    manifest = {'wxid': args.wxid, 'package_version': packages.name, 'complete': False,
                'scope': 'published cached code + visited assets; not original source/project or all remote assets'}
    try:
        for src in sources:
            put_copy(src, output / 'packages' / src.name)
        subprocess.run([str(Path(args.unpacker).resolve()), 'unpack', str(output / 'packages'),
                        '-wxid', args.wxid, '-o', str(output / 'unpacked'), '-no-beautify'], check=True)
        unpacked = output / 'unpacked' / args.wxid
        manifest['modules'] = split_modules(unpacked, output / 'modules')
        manifest['cached_assets'], manifest['missing_cached_assets'] = copy_assets(user_dir, output / 'resources')
        manifest['remote_configs'] = download_configs(unpacked, output / 'resources', args.proxy) if args.remote_configs else []
        manifest['complete'] = not manifest['missing_cached_assets']
    except Exception as exc:
        manifest['error'] = str(exc)
        raise
    finally:
        manifest['files'] = inventory(output)
        (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: manifest[k] for k in ['wxid', 'modules', 'cached_assets', 'complete']}, ensure_ascii=False))
    print(f"files={len(manifest['files'])} bytes={sum(x['bytes'] for x in manifest['files'])} output={output}")
    if not manifest['complete']:
        raise ValueError('some cache entries are missing; see manifest.json')


def selftest():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for bad in ['../escape', '/absolute', 'a/../../escape']:
            try:
                inside(root, bad)
            except ValueError:
                pass
            else:
                raise AssertionError(bad)
        src = root / 'input'
        src.mkdir()
        (src / 'game.js').write_text('var loader = {};\tdefine("a.js", function(require, module, exports){\nexports.a=1;\n});\n\tdefine("src/b.js", function(require, module, exports){\nexports.b=2;\n});\nrequire("a.js");')
        assert split_modules(src, root / 'modules') == 2
        assert 'exports.b=2' in (root / 'modules/src/b.js').read_text()
        user = root / 'user'
        (user / 'usr/gamecaches').mkdir(parents=True)
        (user / 'usr/gamecaches/a.json').write_text('{}')
        url = 'https://example.com/remote/main/config.123.json'
        (user / 'usr/gamecaches/cacheList.json').write_text(json.dumps({'files': {url: {'url': 'wxfile://usr/gamecaches/a.json'}}}))
        assert copy_assets(user, root / 'resources') == (1, [])
        assert (root / 'resources/example.com/remote/main/config.123.json').read_text() == '{}'
        try:
            resource_path('https://example.com/file?token=secret')
        except ValueError:
            pass
        else:
            raise AssertionError('query URL accepted')
        assert len(inventory(root / 'resources')) == 1
        (user / 'usr/gamecaches/a.json').unlink()
        assert copy_assets(user, root / 'resources') == (0, [url])
        try:
            copy_assets(root / 'missing-user', root / 'resources')
        except ValueError:
            pass
        else:
            raise AssertionError('missing cache index accepted')
        (root / 'link').symlink_to(root.parent, target_is_directory=True)
        try:
            inside(root, 'link/escape')
        except ValueError:
            pass
        else:
            raise AssertionError('symlink escape accepted')
    print('selftest ok: path validation, wrapper splitting, cache mapping/missing entries, URL policy, SHA inventory')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--packages', help='absolute cached wxapkg version directory')
    ap.add_argument('--user-dir', help='absolute applet/local/<wxid> directory')
    ap.add_argument('--wxid')
    ap.add_argument('--output', help='fresh absolute archive directory')
    ap.add_argument('--unpacker', default=os.path.expanduser('~/.cache/vft-kit/wxapkg/bin/wxapkg-cli'))
    ap.add_argument('--remote-configs', action='store_true', help='download public remote bundle config JSON via wget')
    ap.add_argument('--proxy', default='', help='explicit HTTP proxy for remote configs; empty means direct')
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return
    for key in ['packages', 'user_dir', 'wxid', 'output']:
        if not getattr(args, key):
            ap.error(f'--{key.replace("_", "-")} is required')
    for key in ['packages', 'user_dir', 'output', 'unpacker']:
        if not Path(getattr(args, key)).is_absolute():
            ap.error(f'--{key.replace("_", "-")} must be absolute')
    export(args)


if __name__ == '__main__':
    main()
