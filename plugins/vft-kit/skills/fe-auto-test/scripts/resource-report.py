#!/usr/bin/env python3
"""
resource-report.py — 把资源清单压成一份「资源拆解 + 缓存/压缩实测」摘要，
供 fe-auto-test 的全维度体检报告使用。

吃两种输入（两条路径产出的格式不同，这里统一消化）：
  · MCP 路径：lighthouse MCP 的 analyze_resources 结果（常因过大而落盘的那个 .txt）。
    它的 JSON 动辄 70k+ 字符，直接进上下文会报 "exceeds maximum allowed tokens"。
  · 脚本路径：lighthouse-audit.mjs --resources=<path> 落的盘。

缺失字段会自己补：没有 summary 就按 resources 现算 resourceCounts；没有 filename 就从
url 推导。两条路径的字段本来对不齐，不补的话脚本路径下「按 type 拆解」和「图片明细」会整块变空。

缓存与压缩为什么要单独测：资源清单本身 **不含缓存 TTL / 压缩状态**（analyze_resources 实测
只有 filename/type/sizeKB/mimeType/url），只能自己发请求拿。探针走 probe-headers.mjs
（node http/https 直连），不用 curl —— curl 会被本机 context-mode hook 拦。

用法：
  python3 resource-report.py <资源清单文件路径> [--no-probe] [--top N]
"""
import sys, json, subprocess
from pathlib import Path
from urllib.parse import urlparse
from collections import defaultdict

PROBE = Path(__file__).parent / "probe-headers.mjs"


def load_inner(path):
    raw = open(path, encoding="utf-8").read()
    # 优先当作 [{type,text}] 包装解析；text 里才是真正的资源 JSON
    try:
        outer = json.loads(raw)
    except json.JSONDecodeError:
        # 整个文件本身就是资源 JSON
        return json.loads(raw)
    if isinstance(outer, dict):
        return outer
    if isinstance(outer, list):
        for el in outer:
            txt = el.get("text", "") if isinstance(el, dict) else ""
            try:
                obj = json.loads(txt)
                if isinstance(obj, dict) and ("resources" in obj or "summary" in obj):
                    return obj
            except (json.JSONDecodeError, TypeError):
                continue
    raise SystemExit("无法在文件里定位资源 JSON（既不是资源对象，也不是含 text 的包装）")


def fmt(kb):
    return f"{kb:.1f}KB" if kb < 1024 else f"{kb/1024:.2f}MB"


def normalize(res):
    """补齐两条路径的字段差异：filename 缺就从 url 推。"""
    for r in res:
        if not r.get("filename"):
            path = urlparse(r.get("url", "")).path
            r["filename"] = path.rsplit("/", 1)[-1] or path or r.get("url", "")[:40]
    return res


def build_summary(res, summ):
    """MCP 给了 summary 就用；脚本路径没有，就按 resources 现算，别让整块输出消失。"""
    if summ.get("resourceCounts"):
        return summ
    counts = defaultdict(lambda: {"count": 0, "sizeKB": 0.0})
    for r in res:
        t = r.get("type") or "other"
        counts[t]["count"] += 1
        counts[t]["sizeKB"] += r.get("sizeKB", 0)
    return {
        "totalResources": len(res),
        "totalSizeKB": sum(r.get("sizeKB", 0) for r in res),
        "resourceCounts": dict(counts),
    }


def probe_all(urls):
    """批量拿 cache-control / content-encoding 真值。

    返回 {url: {...}}；每项要么 ok:True（真值），要么 ok:False + err（**探测失败**）。
    绝不把失败当成「站点没配」—— 那会把配了长缓存 + brotli 的站误报成什么都没配。
    """
    if not urls:
        return {}
    try:
        out = subprocess.run(
            ["node", str(PROBE)],
            input=json.dumps(urls), capture_output=True, text=True, timeout=180,
        )
    except Exception as e:
        return {u: {"ok": False, "err": f"探针启动失败: {e}"} for u in urls}
    if out.returncode != 0:
        err = (out.stderr or "").strip()[:80] or f"exit {out.returncode}"
        return {u: {"ok": False, "err": err} for u in urls}
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return {u: {"ok": False, "err": "探针输出不是 JSON"} for u in urls}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if not args:
        raise SystemExit(__doc__)
    do_probe = "--no-probe" not in flags and "--no-curl" not in flags  # --no-curl 兼容旧调用
    topn = 6
    for f in flags:
        if f.startswith("--top"):
            try: topn = int(f.split("=")[1] if "=" in f else sys.argv[sys.argv.index(f) + 1])
            except Exception: pass

    inner = load_inner(args[0])
    res = normalize(inner.get("resources", []))
    summ = build_summary(res, inner.get("summary", {}))

    print("===== 资源总览 =====")
    print(f"总资源数: {summ.get('totalResources', len(res))}   总体积: {fmt(summ.get('totalSizeKB', 0))}")
    for t, info in sorted(summ["resourceCounts"].items(), key=lambda x: -x[1].get("sizeKB", 0)):
        print(f"  {t:12} {info.get('count',0):>3}个  {fmt(info.get('sizeKB',0))}")

    # 按域名
    host = defaultdict(lambda: [0, 0.0])
    for r in res:
        h = urlparse(r.get("url", "")).netloc or "(空)"
        host[h][0] += 1
        host[h][1] += r.get("sizeKB", 0)
    print("\n===== 按域名（区分自有 vs 第三方）=====")
    for h, (c, s) in sorted(host.items(), key=lambda x: -x[1][1]):
        print(f"  {fmt(s):>9}  {c:>2}个  {h}")

    # Top-N 最大
    print(f"\n===== Top {max(topn,12)} 最大资源 =====")
    for r in sorted(res, key=lambda a: -a.get("sizeKB", 0))[:max(topn, 12)]:
        print(f"  {fmt(r.get('sizeKB',0)):>9}  {r.get('type',''):11}  {r.get('url','')[:78]}")

    # CSS 明细（未用占比由 lighthouse 的 unused-css-rules 量化，这里给体积分布）
    css = sorted([r for r in res if r.get("type") == "stylesheet"], key=lambda a: -a.get("sizeKB", 0))
    if css:
        print("\n===== stylesheet 明细 =====")
        for r in css:
            print(f"  {fmt(r.get('sizeKB',0)):>9}  {r.get('url','')[:80]}")

    # legacy 重复包检测（现代浏览器不该下载 nomodule legacy chunk）
    legacy = [r for r in res if "legacy" in r.get("url", "").lower()]
    if legacy:
        print("\n===== ⚠ legacy 包被下载（现代浏览器本不该下，检查 @vitejs/plugin-legacy）=====")
        for r in sorted(legacy, key=lambda a: -a.get("sizeKB", 0)):
            print(f"  {fmt(r.get('sizeKB',0)):>9}  {r['filename'][:70]}")

    # 图片：标注非 webp / 偏大
    imgs = sorted([r for r in res if r.get("type") == "image"], key=lambda a: -a.get("sizeKB", 0))
    big_imgs = [r for r in imgs if r.get("sizeKB", 0) >= 20 or (r.get("mimeType", "") not in ("image/webp", "image/svg+xml") and r.get("sizeKB", 0) >= 10)]
    if big_imgs:
        print("\n===== 图片（≥20KB 或非 webp 的较大图，考虑转 webp/avif + 尺寸压缩）=====")
        for r in big_imgs:
            print(f"  {fmt(r.get('sizeKB',0)):>9}  {(r.get('mimeType') or '?'):16}  {r['filename'][:50]}")

    # 缓存 / 压缩实测
    if do_probe:
        cacheable = [r for r in sorted(res, key=lambda a: -a.get("sizeKB", 0))
                     if r.get("type") in ("script", "stylesheet", "document", "font")
                     or (r.get("type") == "other" and "javascript" in (r.get("mimeType") or ""))]
        targets = cacheable[:topn]
        print(f"\n===== 缓存 / 压缩实测（探测最大的 {len(targets)} 个静态资源）=====")
        print("  资源清单本身不含这些头，只能实发请求拿。关注：带 hash 的产物有没有长缓存；文本资源有没有 br。")
        probes = probe_all([r["url"] for r in targets])
        failed = 0
        for r in targets:
            p = probes.get(r["url"]) or {"ok": False, "err": "无结果"}
            print(f"  {r.get('url','')[:70]}")
            if not p.get("ok"):
                failed += 1
                print(f"      ⚠ 探测失败（{p.get('err','?')}）—— 缓存/压缩状态未知，**不代表站点没配**")
                continue
            cc = p.get("cacheControl")
            enc = p.get("encoding")
            flag = ""
            if not cc:
                flag += " ❗无Cache-Control(每次都协商)"
            elif "immutable" not in cc and "max-age=315" not in cc:
                flag += " ⚠缓存偏短"
            is_text = r.get("type") in ("script", "stylesheet", "document") or "javascript" in (r.get("mimeType") or "")
            if enc == "gzip":
                flag += " ⚠仅gzip未开br"
            elif not enc and is_text:
                flag += " ❗文本资源未压缩"
            print(f"      Cache-Control: {cc or '（无）'}   编码: {enc or '（未压缩）'}{flag}")
        if failed:
            print(f"\n  ⚠ {failed}/{len(targets)} 个资源探测失败。这几个的缓存/压缩结论**不要写进报告**——"
                  f"没测到 ≠ 没配置。排查：网络不通 / node 不可用 / 资源需鉴权。")

    print("\n（提示：CSS/JS 的「未用占比」由 lighthouse 的 unused-css-rules / unused-javascript 量化，不在本脚本里。）")


if __name__ == "__main__":
    main()
