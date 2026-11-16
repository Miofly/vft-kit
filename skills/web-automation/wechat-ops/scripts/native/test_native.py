"""Offline native safety regression; starts only a standalone harness, never WeChat."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent


class NativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="wxs-tests-")
        cls.root = Path(cls.temp.name)
        for mode in ("WXS_SELF_TEST", "WXS_HOST_TEST"):
            subprocess.run([
                "clang", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                "-D" + mode, str(HERE / "wechat_send.c"), "-o", str(cls.root / mode),
            ], check=True, capture_output=True, text=True)
        subprocess.run([
            "clang", "-Wall", "-Wextra", "-Werror", str(HERE / "wechat_probe.c"),
            "-o", str(cls.root / "probe"),
        ], check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_internal_guards(self):
        subprocess.run([str(self.root / "WXS_SELF_TEST")], check=True)
        subprocess.run([str(self.root / "probe"), "--self-test"], check=True)

    def test_build_refuses_overwrite_and_clone_never_launches(self):
        destination = self.root / "already-loaded.dylib"
        destination.write_bytes(b"keep existing image")
        result = subprocess.run(["bash", str(HERE / "build_dylib.sh"), str(destination)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(destination.read_bytes(), b"keep existing image")
        # Preparation must not regain a hidden launch/send side effect.
        prepare = (HERE / "make_clone.sh").read_text()
        self.assertNotIn("nohup", prepare)
        self.assertNotIn("nc -U", prepare)

    def test_socket_refuses_mutations_and_preserves_existing_endpoint(self):
        # Keep sun_path short; macOS limits Unix socket paths to 104 bytes.
        path = f"/tmp/wxs-test-{os.getpid()}.sock"
        self.assertFalse(os.path.lexists(path))
        env = dict(os.environ, WXS_SOCKET=path)
        proc = subprocess.Popen([str(self.root / "WXS_HOST_TEST")], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not os.path.exists(path) and time.monotonic() < deadline:
                self.assertIsNone(proc.poll())
                time.sleep(0.02)
            self.assertTrue(os.path.exists(path))
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)

            def request(payload):
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                    client.settimeout(4)
                    client.connect(path)
                    client.sendall(payload)
                    client.shutdown(socket.SHUT_WR)
                    chunks = []
                    while True:
                        chunk = client.recv(4096)
                        if not chunk:
                            break
                        chunks.append(chunk)
                    return json.loads(b"".join(chunks))

            for payload in (b"hello", b"send\n", b"probe\ntext", b'{"op":"send"}'):
                self.assertEqual(request(payload)["status"], "refused")
            self.assertEqual(request(b"probe\n")["status"], "not_ready")
            # A second harness must neither unlink nor replace the first socket.
            inode = os.stat(path).st_ino
            other = subprocess.Popen([str(self.root / "WXS_HOST_TEST")], env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as idle:
                    idle.settimeout(4)
                    idle.connect(path)
                    reply = json.loads(idle.recv(4096))
                    self.assertEqual(reply["status"], "refused")
                self.assertEqual(os.stat(path).st_ino, inode)
                self.assertEqual(request(b"hello")["status"], "refused")
            finally:
                other.terminate()
                other.communicate(timeout=5)
        finally:
            proc.terminate()
            proc.communicate(timeout=5)
            if os.path.lexists(path):
                os.unlink(path)


if __name__ == "__main__":
    unittest.main()
