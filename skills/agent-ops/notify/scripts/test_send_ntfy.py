#!/usr/bin/env python3

import importlib.util
import unittest
from email.header import decode_header, make_header
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import MagicMock, patch

SCRIPT = Path(__file__).with_name("send_ntfy.py")
SPEC = importlib.util.spec_from_file_location("send_ntfy", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class SendNtfyTest(unittest.TestCase):
    @patch.object(MODULE.urllib.request, "urlopen")
    def test_sends_attachment_without_exposing_token(self, urlopen: MagicMock) -> None:
        response = MagicMock(status=200)
        urlopen.return_value.__enter__.return_value = response
        with TemporaryDirectory() as directory:
            attachment = Path(directory) / "qr.jpg"
            attachment.write_bytes(b"jpeg-data")
            status = MODULE.send_notification(
                {
                    "base_url": "https://ntfy.sh",
                    "topic": "push-www-test-abcdefg",
                    "token": "tk_test",
                    "allow_short_topic": True,
                },
                "登录｜掘金",
                "请扫描二维码。",
                attachment,
                4,
            )
        request = urlopen.call_args.args[0]
        self.assertEqual(200, status)
        self.assertEqual("PUT", request.method)
        self.assertEqual("qr.jpg", request.get_header("Filename"))
        self.assertEqual("Bearer tk_test", request.get_header("Authorization"))
        self.assertEqual("登录｜掘金", str(make_header(decode_header(request.get_header("Title")))))

    def test_rejects_insecure_endpoint_and_short_topic(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "HTTPS 根地址"):
            MODULE.validate_config({"base_url": "https://ntfy.sh/path", "topic": "x" * 32})
        with self.assertRaisesRegex(RuntimeError, "至少 32 字符"):
            MODULE.validate_config({"base_url": "https://ntfy.sh", "topic": "short"})


if __name__ == "__main__":
    unittest.main()
