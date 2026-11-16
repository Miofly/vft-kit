#!/usr/bin/env python3
"""抓取 TikTok Minis（H5 型小程序）前端产物到本地，仅供学习研究，不分发。

用法: fetch.py <minis_url | minis 链接 | link 接口 JSON 文件> <输出目录> [--pretty]
  例: fetch.py https://minis-xxx.tiktokminis.us /tmp/minis-demo --pretty
link 接口要 TikTok 登录态（无 cookie 返回 status_code=8 Login expired）：
  用 ego-browser 已登录页 page.fetch("https://www.tiktok.com/tiktok/minis/link/<token>")，
  把 body 存成 JSON 文件传进来，或直接传其中的 minis_link_meta.minis_url。
代理: 走 urllib 默认环境变量 HTTPS_PROXY/https_proxy；境外直连常超时，先 export HTTPS_PROXY=http://127.0.0.1:7890。

流程:
1. GET https://www.tiktok.com/tiktok/minis/link/<token> 拿 minis_link_meta.minis_url（静态站点根）
   与 minis_meta（client_key、config 里 htmlEntry、domain.allowList 即后端接口域名）。存 meta.json。
2. 下载 <minis_url>/<htmlEntry>（404 时回退 basename 与 index.html），取 html 里所有本站 JS/CSS/HTML 引用。
3. BFS：html 页继续解析；JS/CSS 里扫 assets/、static/ 及入口 html 出现过的顶层目录（多页站 js/、css/），JS 里的 *.html 按文档根解析，逐个下载（每个 3 次重试）。
   正则会误匹配库里的字符串（mux.js、qq.svg 等），这些 404 属正常，只看 js/css 是否有失败。
4. --pretty 一次 npx prettier 格式化全部 JS 到 pretty/（Vite 站 pretty/<文件名>，多页站保留目录 pretty/js/<文件名>；需 node）。
限制: 只适用 asset_type=0 的 H5 型 Minis（Vite/uni-app 单页或多页原生 JS 站都行）；原生/游戏型包不在 web 上，需从 App 侧拿。
    产物无 sourcemap，看到的是 Vite 压缩后代码；按 pages-<路由>.<hash>.js 分包定位页面。
"""
import collections, json, os, re, shutil, subprocess, sys, urllib.error, urllib.request

UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
REF = re.compile(r'["\'(]((?:\.\.?/|/)?(?:assets/|static/)?[\w\-.@/]+\.(?:js|css|png|jpe?g|webp|svg|gif|woff2?|ttf|json|mp3|html))["\')]')


def get(url, tries=3):
    err = None
    for _ in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=40).read()
        except urllib.error.HTTPError:
            raise
        except Exception as e:
            err = e
    raise err


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], os.path.abspath(sys.argv[2])
    os.makedirs(out, exist_ok=True)
    if os.path.isfile(src):
        data = json.load(open(src))
    elif "tiktokminis" in src:
        data = {"minis_link_meta": {"minis_url": src}}
    else:
        token = src.rstrip("/").split("/")[-1].split("?")[0]
        data = json.loads(get(f"https://www.tiktok.com/tiktok/minis/link/{token}"))
    link, meta = data.get("minis_link_meta") or {}, data.get("minis_meta") or {}
    base = (link.get("minis_url") or "").rstrip("/")
    if not base:
        # status_code=8 未登录；200002 链接不存在；minis_meta 只剩 minis_status=4（218B）推测为小程序下架/不可用
        sys.exit(f"无 minis_url（status_code={data.get('status_code')} minis_status={meta.get('minis_status')}），"
                 f"可能未登录、链接失效或小程序下架: {json.dumps(data)[:300]}")
    config = json.loads(meta.get("config") or "{}")
    json.dump({"link": link, "meta": meta, "config": config}, open(f"{out}/meta.json", "w"), ensure_ascii=False, indent=2)
    entry = (config.get("build") or {}).get("htmlEntry") or "index.html"
    # htmlEntry 可能是源码路径（如 public/index.html + outputDir=dist），线上实际在站点根，404 时回退
    for cand in dict.fromkeys([entry, os.path.basename(entry), "index.html"]):
        try:
            html = get(f"{base}/{cand}").decode("utf-8", "ignore")
            entry = cand
            break
        except urllib.error.HTTPError:
            continue
    else:
        sys.exit(f"htmlEntry 404: {entry}")
    os.makedirs(os.path.dirname(f"{out}/{entry}"), exist_ok=True)
    open(f"{out}/{entry}", "w").write(html)

    # 非 Vite 的多页站（js/、css/、*.html）也要收：html 里所有本站相对引用都入队，html 页继续解析
    LOCAL = re.compile(r'(?:src|href)="(?!https?:|//|data:|#|mailto:|javascript:)([^"?#]+\.(?:js|css|html))[^"]*"')
    q = collections.deque("/" + os.path.normpath(p.lstrip("./")).lstrip("/") for p in LOCAL.findall(html))
    roots = {p.split("/")[1] for p in q if p.count("/") > 1} | {"assets", "static"}
    seen, fail = set(q) | {"/" + entry}, []
    while q:
        p = q.popleft()
        f = out + p
        if os.path.exists(f):
            b = open(f, "rb").read()
        else:
            try:
                b = get(base + urllib.request.quote(p))
            except Exception as e:
                fail.append((p, str(e)[:60]))
                continue
            os.makedirs(os.path.dirname(f), exist_ok=True)
            open(f, "wb").write(b)
        if p.endswith(".html"):
            for m in LOCAL.findall(b.decode("utf-8", "ignore")):
                n = "/" + os.path.normpath(m.lstrip("./")).lstrip("/")
                if n not in seen:
                    seen.add(n)
                    q.append(n)
        if p.endswith((".js", ".css")):
            for m in REF.findall(b.decode("utf-8", "ignore")):
                if m.endswith(".html"):  # JS 里跳转的页面相对文档根，不相对 JS 文件
                    n = "/" + os.path.normpath(m.lstrip("./")).lstrip("/")
                    if "/" not in n[1:] and n not in seen:
                        seen.add(n)
                        q.append(n)
                    continue
                n = "/" + m if m.split("/")[0] in roots else m if m.startswith("/") else os.path.normpath(os.path.join(os.path.dirname(p), m))
                if n.split("/")[1:2] and n.split("/")[1] in roots and n not in seen:
                    seen.add(n)
                    q.append(n)

    # 外部 SDK（如 connect.tiktok-minis.com/drama/sdk.js）一并存下
    for i, u in enumerate(re.findall(r'<script[^>]+src="(https?://[^"]+)"', html)):
        try:
            open(f"{out}/external-{i}-{os.path.basename(u.split('?')[0])}", "wb").write(get(u))
        except Exception as e:
            fail.append((u, str(e)[:60]))

    code_fail = [x for x in fail if x[0].endswith((".js", ".css"))]
    print(f"name={link.get('title')} client_key={meta.get('client_key')} base={base}")
    print(f"files={len(seen) - len(fail)} fail={len(fail)} js/css_fail={code_fail[:10]}")
    print("pages:", sorted(x for x in os.listdir(f"{out}/assets") if x.startswith("pages-")) if os.path.isdir(f"{out}/assets") else [])

    if "--pretty" in sys.argv:
        dsts = []
        for p in sorted(seen):
            if p.endswith(".js") and os.path.isfile(out + p):
                # Vite 站保持 pretty/<文件名>；多页站保留相对目录（pretty/js/api.js）
                dst = f"{out}/pretty/{p[len('/assets/'):] if p.startswith('/assets/') else p.lstrip('/')}"
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(out + p, dst)
                dsts.append(dst)
        # 只起一次 npx：逐文件 npx 在代理下每次都要查 registry，几十个文件能卡十几分钟
        env = {k: v for k, v in os.environ.items() if k.lower() not in ("http_proxy", "https_proxy")}
        if dsts:
            subprocess.run(["npx", "-y", "prettier@3", "--no-config", "--parser", "babel", "--log-level", "silent", "--write", *dsts], env=env, stdout=subprocess.DEVNULL)
        print("pretty ->", f"{out}/pretty")


if __name__ == "__main__":
    main()
