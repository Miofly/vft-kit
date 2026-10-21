#!/usr/bin/env python3

import importlib.util
import os
import unittest
from email.header import decode_header, make_header
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import MagicMock, patch


SCRIPT = Path(__file__).with_name("notify-qr.py")
SPEC = importlib.util.spec_from_file_location("notify_qr", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class NtfyNotificationTest(unittest.TestCase):
    @patch.object(MODULE.urllib.request, "urlopen")
    def test_sends_same_content_and_attachment(self, urlopen: MagicMock) -> None:
        response = MagicMock()
        response.status = 200
        urlopen.return_value.__enter__.return_value = response

        with TemporaryDirectory() as directory:
            image_file = Path(directory) / "qr.jpg"
            image_file.write_bytes(b"\xff\xd8\xffjpeg-data")
            MODULE.send_ntfy_notification(
                {
                    "base_url": "https://ntfy.sh",
                    "topic": "push-www-test-abcdefg",
                    "token": "tk_test",
                    "allow_short_topic": True,
                },
                "登录｜掘金",
                "请使用微信扫描二维码完成登录。",
                image_file,
            )

        request = urlopen.call_args.args[0]
        self.assertEqual("https://ntfy.sh/push-www-test-abcdefg", request.full_url)
        self.assertEqual("PUT", request.method)
        self.assertEqual(b"\xff\xd8\xffjpeg-data", request.data)
        self.assertEqual("image/jpeg", request.get_header("Content-type"))
        self.assertEqual("qr.jpg", request.get_header("Filename"))
        self.assertEqual("登录｜掘金", str(make_header(decode_header(request.get_header("Title")))))
        self.assertEqual(
            "请使用微信扫描二维码完成登录。",
            str(make_header(decode_header(request.get_header("Message")))),
        )
        self.assertEqual("Bearer tk_test", request.get_header("Authorization"))

    def test_rejects_non_root_base_url(self) -> None:
        with TemporaryDirectory() as directory:
            image_file = Path(directory) / "qr.jpg"
            image_file.write_bytes(b"\xff\xd8\xffjpeg-data")
            with self.assertRaisesRegex(RuntimeError, "HTTPS 根地址"):
                MODULE.send_ntfy_notification(
                    {"base_url": "https://ntfy.sh/push-me", "topic": "x" * 32, "token": ""},
                    "title",
                    "message",
                    image_file,
                )

    def test_rejects_short_topic_even_with_token(self) -> None:
        with TemporaryDirectory() as directory:
            image_file = Path(directory) / "qr.jpg"
            image_file.write_bytes(b"\xff\xd8\xffjpeg-data")
            with self.assertRaisesRegex(RuntimeError, "至少 32 字符"):
                MODULE.send_ntfy_notification(
                    {"base_url": "https://ntfy.sh", "topic": "push-me", "token": "tk_test"},
                    "title",
                    "message",
                    image_file,
                )


class BuildNotificationTest(unittest.TestCase):
    def test_requires_action_and_subject(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "action 和 subject"):
            MODULE.build_notification("", "掘金", None)

    def test_title_with_prefix(self) -> None:
        title, content = MODULE.build_notification("登录", "掘金", None, "公众号")
        self.assertEqual("公众号登录｜掘金", title)
        self.assertIn("掘金", content)
        self.assertIn("登录", content)


class InputValidationTest(unittest.TestCase):
    def test_rejects_non_image(self) -> None:
        with TemporaryDirectory() as directory:
            image_file = Path(directory) / "secret.txt"
            image_file.write_text("not an image")
            with self.assertRaisesRegex(RuntimeError, "只支持 JPEG 或 PNG"):
                MODULE.validate_image_file(image_file)

    def test_rejects_insecure_endpoint(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "HTTPS 地址"):
            MODULE.validate_https_endpoint("http://example.com/send", "测试地址")


class EnvConfigTest(unittest.TestCase):
    def test_ntfy_env_parsing(self) -> None:
        env = {
            "NTFY_BASE_URL": "https://ntfy.example.com",
            "NTFY_TOPIC": "t" * 40,
            "NTFY_TOKEN": "tk",
            "NTFY_ALLOW_SHORT_TOPIC": "true",
        }
        with patch.dict(os.environ, env, clear=False):
            config = MODULE.load_ntfy_config_from_env()
        self.assertTrue(config["allow_short_topic"])
        self.assertEqual(config["base_url"], "https://ntfy.example.com")


if __name__ == "__main__":
    unittest.main()
