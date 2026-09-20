#!/usr/bin/env python3
"""全设备类型 User-Agent 解析器。

输入一条浏览器 UA，离线解析出设备（类型/品牌/型号/消费者型号/上市年月）、
操作系统、浏览器、渲染内核与 WebView 容器信息，输出 JSON。

准确性原则：每个字段带 confidence（certain/likely/unknown），有据则给、
无据则明确 unknown，绝不猜测。UA 本身看不见的信息（iOS 具体机型、
Windows 10/11 区分、缩减 UA 的真实版本）如实标注盲区原因。

用法：
    python3 parse_ua.py --stdin          # 从标准输入读取一条 UA（推荐）
    python3 parse_ua.py --stdin --compact  # 单行 JSON 输出

零第三方依赖，Python 3.8+。
"""
import argparse
import json
import re
import sys
from pathlib import Path

CERTAIN = "certain"
LIKELY = "likely"
UNKNOWN = "unknown"

MODELS_FILE = Path(__file__).resolve().parent.parent / "data" / "device-models.json"

# ---------------------------------------------------------------------------
# 爬虫 / 自动化客户端
# ---------------------------------------------------------------------------

BOT_RULES = [
    (r"Googlebot", "Googlebot"),
    (r"Baiduspider", "Baiduspider"),
    (r"bingbot", "Bingbot"),
    (r"Bytespider", "Bytespider"),
    (r"YandexBot", "YandexBot"),
    (r"DuckDuckBot", "DuckDuckBot"),
    (r"Sogou web spider", "搜狗爬虫"),
    (r"360Spider", "360Spider"),
    (r"AhrefsBot", "AhrefsBot"),
    (r"SemrushBot", "SemrushBot"),
    (r"facebookexternalhit", "Facebook 抓取器"),
    (r"HeadlessChrome", "HeadlessChrome"),
    (r"(?i)\b(?:bot|spider|crawler)\b", None),  # 兜底：名称从 UA 中截取
]

# ---------------------------------------------------------------------------
# 容器（App 内嵌 WebView）宿主识别，顺序即优先级
# ---------------------------------------------------------------------------

HOST_APP_RULES = [
    (r"wxwork/([\d.]+)", "企业微信"),
    (r"MicroMessenger/([\d.]+)", "微信"),
    (r"AlipayClient/([\d.]+)", "支付宝"),
    (r"DingTalk/([\d.]+)", "钉钉"),
    (r"aweme[_/]?([\d.]*)", "抖音"),
    (r"NewsArticle/([\d.]+)", "今日头条"),
    (r"baiduboxapp/([\d.]+)", "百度App"),
    (r"[Ww]eibo.*?__weibo__([\d.]*)", "微博"),
    (r"\bQQ/([\d.]+)", "QQ"),
]

# ---------------------------------------------------------------------------
# 独立浏览器识别，顺序敏感：细分标记必须排在 Chrome/Safari 之前
# ---------------------------------------------------------------------------

BROWSER_RULES = [
    ("三星浏览器", r"SamsungBrowser/([\d.]+)"),
    ("华为浏览器", r"HuaweiBrowser/([\d.]+)"),
    ("荣耀浏览器", r"HONORBrowser/([\d.]+)"),
    ("小米浏览器", r"Mi(?:ui)?Browser/([\d.]+)"),
    ("OPPO浏览器", r"HeyTapBrowser/([\d.]+)"),
    ("vivo浏览器", r"VivoBrowser/([\d.]+)"),
    ("UC浏览器", r"(?:UCBrowser|UBrowser|UCWEB)/?([\d.]*)"),
    ("夸克浏览器", r"Quark/([\d.]+)"),
    ("QQ浏览器", r"MQQBrowser/([\d.]+)"),
    ("百度浏览器", r"(?:BIDUBrowser|baidubrowser)[/ ]([\d.]+)"),
    ("搜狗浏览器", r"MetaSr ?([\d.]*)"),
    ("Opera", r"OPR/([\d.]+)"),
    ("Opera", r"Opera[/ ]([\d.]+)"),
    ("Edge", r"Edg(?:A|iOS)?/([\d.]+)"),
    ("Edge", r"Edge/([\d.]+)"),
    ("Vivaldi", r"Vivaldi/([\d.]+)"),
    ("Yandex Browser", r"YaBrowser/([\d.]+)"),
    ("Firefox (iOS)", r"FxiOS/([\d.]+)"),
    ("Firefox", r"Firefox/([\d.]+)"),
    ("Internet Explorer", r"MSIE ([\d.]+)"),
    ("Chrome (iOS)", r"CriOS/([\d.]+)"),
    ("Chrome", r"Chrome/([\d.]+)"),
    ("Safari", r"Version/([\d.]+).*Safari/"),
]

WINDOWS_NT_VERSIONS = {
    "5.1": "XP",
    "5.2": "XP x64 / Server 2003",
    "6.0": "Vista",
    "6.1": "7",
    "6.2": "8",
    "6.3": "8.1",
}

# 型号代码前缀 → 品牌推断规则（mapping 未命中时使用，confidence=likely）
BRAND_PATTERNS = [
    (r"^SM-", "三星", False),
    (r"^(?:MI|Mi|Redmi|POCO|M2\d{2,}|2\d{3}[0-9A-Z]{4,})", "小米", False),
    (r"^Pixel\b", "谷歌", True),   # True = 型号即营销名，可直接作为消费者型号
    (r"^ONEPLUS\b", "一加", False),
    (r"^[A-Z]{3}-[A-Z]{1,2}\d{2}$", "华为/荣耀", False),
    (r"^P[A-Z]{2}\d{3}$", "OPPO/一加（欧加系）", False),
    (r"^V\d{4}[A-Z]{0,2}$", "vivo/iQOO", False),
    (r"^RMX\d{4}$", "realme", False),
    (r"^NX\d", "努比亚", False),
    (r"^ASUS", "华硕", False),
    (r"^moto\b", "摩托罗拉", True),
    (r"^Nokia", "诺基亚", True),
]

# Android 平台段里不是机型的已知噪音段
NON_MODEL_SEGMENT = re.compile(
    r"^(?:Linux|U|wv|Mobile|Tablet|HarmonyOS|HMSCore[ \d.]*|arm[\w-]*"
    r"|[a-z]{2}(?:[-_][A-Za-z]{2,4})?|Android[ \d.]*|SAMSUNG|like .*)$"
)


def load_models():
    try:
        with open(MODELS_FILE, encoding="utf-8") as f:
            data = json.load(f)
        return {k.upper(): v for k, v in data.items() if not k.startswith("_")}
    except (OSError, json.JSONDecodeError):
        return {}


def _search(pattern, ua, flags=0):
    return re.search(pattern, ua, flags)


# ---------------------------------------------------------------------------
# 各维度解析
# ---------------------------------------------------------------------------


def detect_bot(ua):
    for pattern, name in BOT_RULES:
        m = _search(pattern, ua)
        if m:
            if name is None:
                name = m.group(0)
            ver = _search(re.escape(name) + r"/([\d.]+)", ua)
            return name, (ver.group(1) if ver else None)
    return None, None


def detect_os(ua, notes):
    """返回 (name, version, confidence)。"""
    m = _search(r"OpenHarmony ?([\d.]+)", ua)
    if m:
        return "HarmonyOS NEXT", m.group(1), CERTAIN
    if "HarmonyOS" in ua:
        notes.append("UA 中的 Android 版本是鸿蒙的安卓兼容层版本，非 HarmonyOS 自身版本。")
        return "HarmonyOS", None, CERTAIN
    m = _search(r"Windows Phone(?: OS)? ?([\d.]*)", ua)
    if m:
        return "Windows Phone", m.group(1) or None, CERTAIN
    m = _search(r"Windows NT ([\d.]+)", ua)
    if m:
        nt = m.group(1)
        if nt == "10.0":
            notes.append("Windows 10 与 11 的 UA 同为 NT 10.0，无法从 UA 区分。")
            return "Windows", "10 或 11", LIKELY
        if nt in WINDOWS_NT_VERSIONS:
            return "Windows", WINDOWS_NT_VERSIONS[nt], CERTAIN
        return "Windows", f"NT {nt}", LIKELY
    m = _search(r"iPhone OS ([\d_]+) like Mac OS X", ua)
    if m:
        return "iOS", m.group(1).replace("_", "."), CERTAIN
    m = _search(r"\(iPad; CPU OS ([\d_]+)", ua)
    if m:
        return "iPadOS", m.group(1).replace("_", "."), CERTAIN
    if "iPhone" in ua or "iPod" in ua:
        return "iOS", None, CERTAIN
    if "iPad" in ua:
        return "iPadOS", None, CERTAIN
    m = _search(r"Mac OS X ([\d_.]+)", ua)
    if m:
        ver = m.group(1).replace("_", ".")
        if ver == "10.15.7":
            notes.append(
                "macOS 版本自 10.15.7 起在 UA 中冻结，真实系统可能是任意更新版本；"
                "iPad 桌面模式也会伪装成此 UA。"
            )
            return "macOS", ver, LIKELY
        return "macOS", ver, CERTAIN
    if "CrOS" in ua:
        m = _search(r"CrOS \S+ ([\d.]+)", ua)
        return "ChromeOS", (m.group(1) if m else None), CERTAIN
    m = _search(r"Android ([\d.]+)", ua)
    if m:
        return "Android", m.group(1), CERTAIN
    m = _search(r"Tizen ([\d.]+)", ua)
    if m:
        return "Tizen", m.group(1), CERTAIN
    if _search(r"[Ww]eb0?OS", ua):
        return "webOS", None, CERTAIN
    if "Linux" in ua or "X11" in ua:
        return "Linux", None, LIKELY
    return None, None, UNKNOWN


def detect_container(ua):
    """返回 (host_app, host_version)。"""
    for pattern, host in HOST_APP_RULES:
        m = _search(pattern, ua)
        if m:
            ver = m.group(1) if m.groups() and m.group(1) else None
            return host, ver
    return None, None


def detect_browser(ua, host_app, host_version, os_name, notes):
    """返回 (name, version, confidence)。"""
    if host_app:
        return f"{host_app}内置浏览器", host_version, CERTAIN
    for name, pattern in BROWSER_RULES:
        m = _search(pattern, ua)
        if m:
            ver = m.group(1) if m.groups() and m.group(1) else None
            return name, ver, CERTAIN
    if "Trident/" in ua:
        m = _search(r"rv:([\d.]+)", ua)
        return "Internet Explorer", (m.group(1) if m else None), CERTAIN
    if os_name in ("iOS", "iPadOS") and "AppleWebKit" in ua:
        notes.append("iOS UA 含 WebKit 但无 Safari 标记，通常为 App 内嵌 WebView。")
        return "iOS 应用内 WebView", None, LIKELY
    return None, None, UNKNOWN


def detect_engine(ua, browser_name, os_name):
    """返回 (name, version, note)。"""
    if os_name in ("iOS", "iPadOS"):
        m = _search(r"AppleWebKit/([\d.]+)", ua)
        return (
            "WebKit",
            m.group(1) if m else None,
            "iOS/iPadOS 上所有浏览器均被要求使用系统 WebKit 内核。",
        )
    m = _search(r"ArkWeb/([\d.]+)", ua)
    if m:
        return "ArkWeb", m.group(1), None
    if browser_name == "Internet Explorer" or "Trident/" in ua:
        m = _search(r"Trident/([\d.]+)", ua)
        return "Trident", m.group(1) if m else None, None
    if browser_name == "Firefox":
        m = _search(r"rv:([\d.]+)", ua)
        return "Gecko", m.group(1) if m else None, None
    m = _search(r"Chrome/([\d.]+)", ua)
    if m:
        note = None
        if _search(r"XWEB/[\d.]+", ua):
            note = "微信安卓端使用自研 XWEB 内核（基于 Blink）。"
        return "Blink", m.group(1), note
    if "AppleWebKit" in ua:
        m = _search(r"AppleWebKit/([\d.]+)", ua)
        return "WebKit", m.group(1) if m else None, None
    if "Gecko/" in ua:
        m = _search(r"rv:([\d.]+)", ua)
        return "Gecko", m.group(1) if m else None, None
    return None, None, None


def extract_android_model(ua):
    """从 Android UA 的平台段提取硬件型号代码。"""
    m = _search(r";\s*([^;)]+?)\s+Build/", ua)
    if m:
        return m.group(1).strip()
    paren = _search(r"\(([^)]*Android[^)]*)\)", ua)
    if not paren:
        return None
    segments = [s.strip() for s in paren.group(1).split(";")]
    candidates = [s for s in segments if s and not NON_MODEL_SEGMENT.match(s)]
    return candidates[-1] if candidates else None


def resolve_device_identity(model_code, ua, models, notes):
    """返回 (brand, consumer_name, release_date, confidence)。

    release_date 为上市年月（YYYY-MM）。UA 本身不含发布日期，
    只有映射表命中才能给出；其余情况一律 None，由网查流程确认。
    """
    if not model_code:
        return None, None, None, UNKNOWN
    entry = models.get(model_code.upper())
    if entry:
        return entry["brand"], entry["name"], entry.get("released"), CERTAIN
    for pattern, brand, self_describing in BRAND_PATTERNS:
        if re.match(pattern, model_code):
            if self_describing:
                return brand, model_code, None, LIKELY
            if brand == "华为/荣耀" and "HuaweiBrowser" in ua:
                brand = "华为"
            if "/" in brand:
                notes.append(f"型号代码 {model_code} 的前缀由多个品牌共用（{brand}），需权威来源确认。")
            return brand, None, None, LIKELY
    # Redmi/小米部分机型直接以营销名做型号
    if re.match(r"^(?:Redmi|POCO|MI|Mi)\b", model_code):
        return "小米", model_code, None, LIKELY
    return None, None, None, UNKNOWN


def detect_device_type(ua, os_name, is_bot, notes):
    if is_bot:
        return "bot", CERTAIN
    if _search(r"SMART-?TV|Tizen.*\bTV\b|[Ww]eb0?OS\.?TV|BRAVIA|CrKey|Android TV|GoogleTV|AFT[A-Z]", ua):
        return "tv", CERTAIN
    if _search(r"PlayStation|Xbox|Nintendo", ua):
        return "console", CERTAIN
    if os_name == "iPadOS" or "iPad" in ua:
        return "tablet", CERTAIN
    if "iPhone" in ua or "iPod" in ua:
        return "mobile", CERTAIN
    if os_name in ("Android", "HarmonyOS", "HarmonyOS NEXT"):
        if _search(r"\bTablet\b", ua):
            return "tablet", CERTAIN
        if _search(r"\bMobile\b", ua):
            return "mobile", CERTAIN
        notes.append("Android UA 无 Mobile 标记，按惯例判定为平板（个别 TV/车机也可能如此）。")
        return "tablet", LIKELY
    if os_name in ("iOS", "Windows Phone"):
        return "mobile", CERTAIN
    if os_name in ("Windows", "macOS", "Linux", "ChromeOS"):
        return "desktop", CERTAIN
    if os_name in ("Tizen", "webOS"):
        return "tv", LIKELY
    return "unknown", UNKNOWN


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------


def parse_ua(ua):
    ua = ua.strip()
    notes = []
    models = load_models()

    bot_name, bot_version = detect_bot(ua)
    is_bot = bot_name is not None

    os_name, os_version, os_conf = detect_os(ua, notes)
    host_app, host_version = detect_container(ua)

    ua_reduced = False
    model_code = None
    if os_name in ("Android", "HarmonyOS") or (os_name is None and "Android" in ua):
        model_code = extract_android_model(ua)
        if model_code == "K" or (model_code and model_code.lower() == "k"):
            ua_reduced = True
            model_code = None
            if os_version == "10":
                os_version = "10 或更高"
                os_conf = UNKNOWN
            notes.append(
                "该 UA 已被 Chrome 缩减（Reduced UA）：机型固定为 K、版本固定为 Android 10，"
                "真实机型与版本需从 Client Hints 获取，UA 中不可见。"
            )

    brand, consumer_name, release_date, dev_conf = resolve_device_identity(
        model_code, ua, models, notes
    )

    if os_name in ("iOS", "iPadOS"):
        brand = "苹果"
        dev_conf = CERTAIN
        notes.append(
            "iOS/iPadOS 的 UA 不包含具体机型（所有 iPhone 报同一 UA），"
            "只能识别到 iPhone/iPad 粒度。"
        )
    elif os_name == "macOS":
        brand = "苹果"
        dev_conf = CERTAIN

    is_webview = False
    if host_app:
        is_webview = True
    elif _search(r";\s*wv\)", ua) or "; wv;" in ua:
        is_webview = True
        notes.append("UA 含 wv 标记：来自 Android System WebView（App 内嵌页面）。")

    browser_name, browser_version, browser_conf = detect_browser(
        ua, host_app, host_version, os_name, notes
    )
    if browser_name == "iOS 应用内 WebView":
        is_webview = True

    if is_bot:
        browser_name, browser_version, browser_conf = bot_name, bot_version, CERTAIN

    engine_name, engine_version, engine_note = detect_engine(ua, browser_name, os_name)
    if engine_note:
        notes.append(engine_note)

    device_type, type_conf = detect_device_type(ua, os_name, is_bot, notes)

    needs_web_lookup = bool(model_code and not consumer_name and not is_bot)

    return {
        "device": {
            "type": device_type,
            "type_confidence": type_conf,
            "brand": brand,
            "model_code": model_code,
            "consumer_name": consumer_name,
            "release_date": release_date,
            "confidence": dev_conf,
        },
        "os": {"name": os_name, "version": os_version, "confidence": os_conf},
        "browser": {
            "name": browser_name,
            "version": browser_version,
            "confidence": browser_conf,
        },
        "engine": {"name": engine_name, "version": engine_version},
        "container": {"is_webview": is_webview, "host_app": host_app},
        "flags": {
            "is_bot": is_bot,
            "ua_reduced": ua_reduced,
            "needs_web_lookup": needs_web_lookup,
        },
        "notes": notes,
    }


def main():
    ap = argparse.ArgumentParser(description="全设备类型 User-Agent 解析器")
    ap.add_argument("--stdin", action="store_true", help="从标准输入读取一条 UA（推荐）")
    ap.add_argument("--compact", action="store_true", help="单行 JSON 输出")
    args = ap.parse_args()

    if not args.stdin:
        ap.error("请使用 --stdin 并通过标准输入传入 UA，避免 UA 进入命令行历史。")
    ua = sys.stdin.read().strip()
    if not ua:
        print(json.dumps({"error": "标准输入为空，未收到 UA。"}, ensure_ascii=False))
        return 1

    result = parse_ua(ua)
    if args.compact:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
