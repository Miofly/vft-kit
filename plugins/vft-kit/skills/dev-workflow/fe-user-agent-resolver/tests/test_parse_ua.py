#!/usr/bin/env python3
"""parse_ua.py 的单元测试：覆盖桌面、手机、平板、TV、爬虫与各类 WebView 容器。

运行方式：
    python3 tests/test_parse_ua.py
"""
import sys
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SKILL_DIR / "scripts"))

import parse_ua  # noqa: E402


def parse(ua: str) -> dict:
    return parse_ua.parse_ua(ua)


class TestDesktop(unittest.TestCase):
    def test_windows10_chrome(self):
        r = parse(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        )
        self.assertEqual(r["device"]["type"], "desktop")
        self.assertEqual(r["os"]["name"], "Windows")
        self.assertEqual(r["os"]["version"], "10 或 11")
        self.assertEqual(r["os"]["confidence"], "likely")
        self.assertEqual(r["browser"]["name"], "Chrome")
        self.assertTrue(r["browser"]["version"].startswith("126"))
        self.assertEqual(r["engine"]["name"], "Blink")
        self.assertFalse(r["container"]["is_webview"])

    def test_windows7_chrome(self):
        r = parse(
            "Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"
        )
        self.assertEqual(r["os"]["version"], "7")
        self.assertEqual(r["os"]["confidence"], "certain")

    def test_macos_safari(self):
        r = parse(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        )
        self.assertEqual(r["device"]["type"], "desktop")
        self.assertEqual(r["device"]["brand"], "苹果")
        self.assertEqual(r["os"]["name"], "macOS")
        # 10.15.7 是冻结版本，真实系统可能更新
        self.assertEqual(r["os"]["confidence"], "likely")
        self.assertEqual(r["browser"]["name"], "Safari")
        self.assertEqual(r["browser"]["version"], "17.5")
        self.assertEqual(r["engine"]["name"], "WebKit")

    def test_windows_edge(self):
        r = parse(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.2592.87"
        )
        self.assertEqual(r["browser"]["name"], "Edge")
        self.assertTrue(r["browser"]["version"].startswith("126"))
        self.assertEqual(r["engine"]["name"], "Blink")

    def test_windows_firefox(self):
        r = parse(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) "
            "Gecko/20100101 Firefox/127.0"
        )
        self.assertEqual(r["browser"]["name"], "Firefox")
        self.assertEqual(r["engine"]["name"], "Gecko")

    def test_ie11(self):
        r = parse(
            "Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko"
        )
        self.assertEqual(r["browser"]["name"], "Internet Explorer")
        self.assertEqual(r["engine"]["name"], "Trident")


class TestIOS(unittest.TestCase):
    def test_iphone_safari(self):
        r = parse(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 "
            "Mobile/15E148 Safari/604.1"
        )
        self.assertEqual(r["device"]["type"], "mobile")
        self.assertEqual(r["device"]["brand"], "苹果")
        self.assertIsNone(r["device"]["model_code"])
        self.assertIsNone(r["device"]["consumer_name"])
        self.assertEqual(r["os"]["name"], "iOS")
        self.assertEqual(r["os"]["version"], "17.5.1")
        self.assertEqual(r["browser"]["name"], "Safari")
        self.assertEqual(r["engine"]["name"], "WebKit")
        # iOS UA 不含具体机型，机型未知则发布日期同样未知
        self.assertIsNone(r["device"]["release_date"])
        # iOS UA 不含具体机型，查也查不到，不应触发网查
        self.assertFalse(r["flags"]["needs_web_lookup"])

    def test_ipad_safari(self):
        r = parse(
            "Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 "
            "(KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
        )
        self.assertEqual(r["device"]["type"], "tablet")
        self.assertEqual(r["os"]["name"], "iPadOS")
        self.assertEqual(r["os"]["version"], "16.6")

    def test_iphone_chrome(self):
        r = parse(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.6478.54 "
            "Mobile/15E148 Safari/604.1"
        )
        self.assertEqual(r["browser"]["name"], "Chrome (iOS)")
        # iOS 上所有浏览器都只能用系统 WebKit
        self.assertEqual(r["engine"]["name"], "WebKit")

    def test_iphone_wechat(self):
        r = parse(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 "
            "MicroMessenger/8.0.44(0x18002c2d) NetType/WIFI Language/zh_CN"
        )
        self.assertTrue(r["container"]["is_webview"])
        self.assertEqual(r["container"]["host_app"], "微信")
        self.assertEqual(r["browser"]["name"], "微信内置浏览器")
        self.assertEqual(r["browser"]["version"], "8.0.44")


class TestAndroid(unittest.TestCase):
    def test_reduced_ua(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        )
        self.assertTrue(r["flags"]["ua_reduced"])
        self.assertEqual(r["device"]["type"], "mobile")
        self.assertIsNone(r["device"]["model_code"])
        self.assertEqual(r["os"]["name"], "Android")
        # 缩减 UA 固定报 Android 10，真实版本 >= 10
        self.assertEqual(r["os"]["version"], "10 或更高")
        self.assertEqual(r["os"]["confidence"], "unknown")
        self.assertFalse(r["flags"]["needs_web_lookup"])

    def test_samsung_webview_with_mapping(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 13; SM-S9180 Build/TP1A.220624.014; wv) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 "
            "Chrome/110.0.5481.154 Mobile Safari/537.36"
        )
        self.assertEqual(r["device"]["model_code"], "SM-S9180")
        self.assertEqual(r["device"]["brand"], "三星")
        self.assertEqual(r["device"]["consumer_name"], "Galaxy S23 Ultra")
        self.assertEqual(r["device"]["confidence"], "certain")
        # 映射命中时同时给出上市年月
        self.assertEqual(r["device"]["release_date"], "2023-02")
        self.assertTrue(r["container"]["is_webview"])
        self.assertFalse(r["flags"]["needs_web_lookup"])

    def test_huawei_harmonyos(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 12; HarmonyOS; NOH-AN00; HMSCore 6.11.0.302) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.88 "
            "HuaweiBrowser/13.0.5.303 Mobile Safari/537.36"
        )
        self.assertEqual(r["os"]["name"], "HarmonyOS")
        self.assertEqual(r["device"]["model_code"], "NOH-AN00")
        self.assertEqual(r["device"]["brand"], "华为")
        self.assertEqual(r["device"]["consumer_name"], "Mate 40 Pro")
        self.assertEqual(r["browser"]["name"], "华为浏览器")

    def test_xiaomi_miui_browser_needs_lookup(self):
        r = parse(
            "Mozilla/5.0 (Linux; U; Android 13; zh-cn; 23127PN0CC Build/TKQ1.221114.001) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 "
            "Chrome/118.0.0.0 MiuiBrowser/17.6.0"
        )
        self.assertEqual(r["device"]["model_code"], "23127PN0CC")
        self.assertEqual(r["device"]["brand"], "小米")
        self.assertIsNone(r["device"]["consumer_name"])
        self.assertTrue(r["flags"]["needs_web_lookup"])
        self.assertEqual(r["browser"]["name"], "小米浏览器")

    def test_oneplus_mapping(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 14; PJD110 Build/UKQ1.230924.001) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 "
            "HeyTapBrowser/45.10.7.1 Mobile Safari/537.36"
        )
        self.assertEqual(r["device"]["model_code"], "PJD110")
        self.assertEqual(r["device"]["brand"], "一加")
        self.assertEqual(r["device"]["consumer_name"], "OnePlus 12")
        self.assertEqual(r["browser"]["name"], "OPPO浏览器")

    def test_vivo_unknown_model(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 13; V2244A Build/TP1A.220624.014) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 "
            "VivoBrowser/17.2.10.5 Mobile Safari/537.36"
        )
        self.assertEqual(r["device"]["model_code"], "V2244A")
        self.assertTrue(r["device"]["brand"].startswith("vivo"))
        # 映射未命中时发布日期不可知，明确输出 null 而非猜测
        self.assertIsNone(r["device"]["release_date"])
        self.assertTrue(r["flags"]["needs_web_lookup"])
        self.assertEqual(r["browser"]["name"], "vivo浏览器")

    def test_vivo_mapping_with_release_date(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 14; V2357A Build/UP1A.231005.007; wv) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 "
            "Chrome/116.0.0.0 Mobile Safari/537.36"
        )
        self.assertEqual(r["device"]["brand"], "vivo")
        self.assertEqual(r["device"]["consumer_name"], "Y37")
        self.assertEqual(r["device"]["release_date"], "2024-07")
        self.assertEqual(r["device"]["confidence"], "certain")
        self.assertFalse(r["flags"]["needs_web_lookup"])

    def test_pixel_self_describing(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        )
        self.assertEqual(r["device"]["brand"], "谷歌")
        self.assertEqual(r["device"]["consumer_name"], "Pixel 8 Pro")
        self.assertFalse(r["flags"]["needs_web_lookup"])

    def test_wechat_android(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 14; 2304FPN6DC Build/UKQ1.230804.001; wv) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/116.0.0.0 "
            "Mobile Safari/537.36 XWEB/1160065 MMWEBSDK/20231202 "
            "MicroMessenger/8.0.47.2560(0x28002F35) WeChat/arm64 Weixin NetType/WIFI"
        )
        self.assertTrue(r["container"]["is_webview"])
        self.assertEqual(r["container"]["host_app"], "微信")
        self.assertEqual(r["device"]["brand"], "小米")
        self.assertEqual(r["device"]["model_code"], "2304FPN6DC")

    def test_android_tablet_no_mobile_token(self):
        r = parse(
            "Mozilla/5.0 (Linux; Android 13; SM-X710) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        )
        self.assertEqual(r["device"]["type"], "tablet")
        self.assertEqual(r["device"]["brand"], "三星")

    def test_harmonyos_next_arkweb(self):
        r = parse(
            "Mozilla/5.0 (Phone; OpenHarmony 5.0) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 "
            "ArkWeb/4.1.6.1 Mobile"
        )
        self.assertEqual(r["os"]["name"], "HarmonyOS NEXT")
        self.assertEqual(r["os"]["version"], "5.0")
        self.assertEqual(r["engine"]["name"], "ArkWeb")
        self.assertEqual(r["device"]["type"], "mobile")


class TestOtherDeviceTypes(unittest.TestCase):
    def test_googlebot(self):
        r = parse(
            "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
        )
        self.assertEqual(r["device"]["type"], "bot")
        self.assertTrue(r["flags"]["is_bot"])
        self.assertEqual(r["browser"]["name"], "Googlebot")

    def test_samsung_tizen_tv(self):
        r = parse(
            "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.5) AppleWebKit/537.36 "
            "(KHTML, like Gecko) 85.0.4183.93/6.5 TV Safari/537.36"
        )
        self.assertEqual(r["device"]["type"], "tv")
        self.assertEqual(r["os"]["name"], "Tizen")


class TestCli(unittest.TestCase):
    def test_stdin_outputs_json(self):
        import json
        import subprocess

        script = SKILL_DIR / "scripts" / "parse_ua.py"
        proc = subprocess.run(
            [sys.executable, str(script), "--stdin"],
            input="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)
        self.assertEqual(data["browser"]["name"], "Chrome")


if __name__ == "__main__":
    unittest.main(verbosity=2)
