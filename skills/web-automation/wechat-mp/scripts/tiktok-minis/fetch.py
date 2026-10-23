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
2. 下载 <minis_url>/<htmlEntry>，从 script/link 标签取入口 JS/CSS。
3. BFS 扫 JS/CSS 里的 /assets/、/static/ 相对引用，逐个下载（每个 3 次重试）。
   正则会误匹配库里的字符串（mux.js、qq.svg 等），这些 404 属正常，只看 js/css 是否有失败。
4. --pretty 用 npx prettier 格式化 assets/*.js 到 pretty/（需 node）。
限制: 只适用 asset_type=0 且 config.build.htmlEntry 存在的 H5 型 Minis；原生/游戏型包不在 web 上，需从 App 侧拿。
    产物无 sourcemap，看到的是 Vite 压缩后代码；按 pages-<路由>.<hash>.js 分包定位页面。
"""
import collections, json, os, re, subprocess, sys, urllib.error, urllib.request

UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
REF = re.compile(r'["\'(]((?:\.\.?/|/)?(?:assets/|static/)?[\w\-.@/]+\.(?:js|css|png|jpe?g|webp|svg|gif|woff2?|ttf|json|mp3))["\')]')


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
        sys.exit(f"无 minis_url，可能非 H5 型或 token 失效: {json.dumps(data)[:300]}")
    config = json.loads(meta.get("config") or "{}")
    json.dump({"link": link, "meta": meta, "config": config}, open(f"{out}/meta.json", "w"), ensure_ascii=False, indent=2)
    entry = (config.get("build") or {}).get("htmlEntry") or "index.html"
    html = get(f"{base}/{entry}").decode("utf-8", "ignore")
    open(f"{out}/{entry}", "w").write(html)

    q = collections.deque("/" + p.lstrip("/") for p in re.findall(r'(?:src|href)="(/?(?:assets|static)/[^"]+)"', html))
    seen, fail = set(q), []
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
        if p.endswith((".js", ".css")):
            for m in REF.findall(b.decode("utf-8", "ignore")):
                n = "/" + m if m.startswith(("assets/", "static/")) else m if m.startswith("/") else os.path.normpath(os.path.join(os.path.dirname(p), m))
                if n.startswith(("/assets/", "/static/")) and n not in seen:
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
        os.makedirs(f"{out}/pretty", exist_ok=True)
        for n in os.listdir(f"{out}/assets"):
            if n.endswith(".js"):
                with open(f"{out}/pretty/{n}", "w") as fh:
                    subprocess.run(["npx", "-y", "prettier@3", "--no-config", "--parser", "babel", f"{out}/assets/{n}"], stdout=fh, stderr=subprocess.DEVNULL)
        print("pretty ->", f"{out}/pretty")


if __name__ == "__main__":
    main()
