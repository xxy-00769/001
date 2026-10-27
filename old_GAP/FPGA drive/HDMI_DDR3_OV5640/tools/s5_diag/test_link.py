"""Host tests and independent zlib/struct packet vectors for RTL."""
from __future__ import annotations

import argparse
from dataclasses import asdict
import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("mes50hp_link", ROOT / "host/mes50hp_link/link.py")
link = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = link
SPEC.loader.exec_module(link)
SESSION = 0x12345678


def packet(kind, seq, value=0, lease=0, detail=0, session=SESSION):
    return link.Packet(kind, session, seq, value, lease, detail)


class ProtocolTests(unittest.TestCase):
    def test_roundtrip(self):
        for kind in link.NAMES:
            original = packet(kind, 0x1020304, 1, 5000, 0)
            self.assertEqual(link.Packet.decode(original.encode()), original)

    def test_crc_known_answer(self):
        self.assertEqual(zlib.crc32(b"123456789"), 0xCBF43926)
        self.assertEqual(packet(link.HELLO, 1).encode().hex(),
                         "4d35443101010000123456780000000100000000000000000000000080fe8ea1")

    def test_all_single_bit_corruption_rejected(self):
        original = packet(link.LED, 3, 1, 2000).encode()
        for bit in range(256):
            data = bytearray(original)
            data[bit // 8] ^= 1 << (bit % 8)
            with self.assertRaises(ValueError, msg=f"bit {bit}"):
                link.Packet.decode(data)

    def test_bad_lengths(self):
        data = packet(link.HELLO, 1).encode()
        for n in range(32):
            with self.assertRaises(ValueError):
                link.Packet.decode(data[:n])
        with self.assertRaises(ValueError):
            link.Packet.decode(data + b"\0")

    def test_command_fields(self):
        for p in (packet(link.PING, 2, 1), packet(link.LED, 2, 2, 5),
                  packet(link.LED, 2, 1, 0), packet(link.LED, 2, 1, 5001),
                  packet(link.HELLO, 2, detail=1), packet(link.STATUS, 2)):
            self.assertFalse(p.command_valid())

    def test_model_no_replay_lease_extension(self):
        model = link.DiagnosticModel()
        self.assertEqual(model.handle(packet(link.HELLO, 1), 0).detail, link.OK)
        self.assertEqual(model.handle(packet(link.LED, 2, 1, 2000), 0).detail, link.OK)
        self.assertEqual(model.handle(packet(link.LED, 2, 1, 2000), 1).detail, link.DUPLICATE)
        self.assertEqual(model.handle(packet(link.PING, 3), 2.1).value, 0)
        self.assertEqual(model.handle(packet(link.PING, 1), 2.2).detail, link.STALE)

    def test_model_sessions(self):
        model = link.DiagnosticModel()
        self.assertEqual(model.handle(packet(link.PING, 1), 0).detail, link.BAD_SESSION)
        model.handle(packet(link.HELLO, 1), 0)
        self.assertEqual(model.handle(packet(link.HELLO, 1, session=42), 1).detail, link.BUSY)
        self.assertEqual(model.handle(packet(link.PING, 2), 5).detail, link.BAD_SESSION)
        self.assertEqual(model.handle(packet(link.HELLO, 1, session=42), 5).detail, link.OK)

    def test_real_udp_client_subprocess(self):
        # Real OS UDP sockets exercise the portable CLI; the peer is software.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
            server.bind(("127.0.0.1", 0))
            port = server.getsockname()[1]
            server.settimeout(3)
            errors = []

            def peer():
                model = link.DiagnosticModel()
                try:
                    import time
                    for _ in range(5):  # HELLO, LED, three PINGs
                        data, address = server.recvfrom(2048)
                        response = model.handle(link.Packet.decode(data), time.monotonic())
                        server.sendto(response.encode(), address)
                except BaseException as exc:
                    errors.append(str(exc))

            worker = threading.Thread(target=peer)
            worker.start()
            with tempfile.TemporaryDirectory(prefix="mes50hp_host_test_") as temp:
                log = Path(temp) / "result.json"
                proc = subprocess.run(
                    [sys.executable, str(ROOT / "host/mes50hp_link/link.py"), "client",
                     "--board", "127.0.0.1", "--bind", "127.0.0.2", "--port", str(port),
                     "--count", "3", "--interval", "0.01", "--timeout", "1",
                     "--led", "1", "--lease-ms", "2000", "--log", str(log)],
                    capture_output=True, text=True, timeout=8)
                worker.join(timeout=4)
                self.assertFalse(worker.is_alive())
                self.assertEqual(errors, [])
                self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                summary = json.loads(log.read_text(encoding="utf-8"))
                self.assertEqual((summary["sent"], summary["received"], summary["timeouts"]), (5, 5, 0))
                self.assertEqual([row["value"] for row in summary["records"]], [1, 1, 1])

    def test_client_timeout(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as silent:
            silent.bind(("127.0.0.1", 0))
            client = link.Client("127.0.0.1", "127.0.0.2", silent.getsockname()[1], 0.03)
            try:
                self.assertIsNone(client.exchange(link.HELLO))
                self.assertEqual(client.stats()["timeouts"], 1)
            finally:
                client.close()


def vectors(directory: Path):
    directory.mkdir(parents=True, exist_ok=False)
    commands = [
        packet(link.HELLO, 1),
        packet(link.PING, 2),
        packet(link.LED, 3, 1, 20),
        packet(link.LED, 3, 0, 5000),  # same seq, changed body: no side effect
        packet(link.LED, 2, 1, 20),
        packet(link.PING, 4),
        packet(link.PING, 5, session=42),
        packet(link.HELLO, 1, session=42),
        packet(link.LED, 5, 1, 5001),
        packet(link.LED, 5, 2, 20),
        packet(link.LED, 5, 1, 0),
        packet(link.LED, 5, 1, 5000),
        packet(link.HELLO, 1, session=42),
        packet(link.PING, 2, session=42),
        packet(link.HELLO, 1),
        packet(link.LED, 2, 1, 20),
        packet(link.PING, 3),
        packet(link.PING, 0xFFFFFFFF),
        packet(link.PING, 1),
    ]
    replies = [
        packet(link.ACK, 1),
        packet(link.STATUS, 2, detail=2),
        packet(link.ACK, 3, 1, 20),
        packet(link.ACK, 3, 1, 10, link.DUPLICATE),
        packet(link.ACK, 2, 1, 10, link.STALE),
        packet(link.STATUS, 4, 0, 0, 4),
        packet(link.ACK, 5, detail=link.BAD_SESSION, session=42),
        packet(link.ACK, 1, detail=link.BUSY, session=42),
        packet(link.ACK, 5, 1, 5000),
        packet(link.ACK, 1, session=42),
        packet(link.STATUS, 2, detail=7, session=42),
        packet(link.ACK, 1),
        packet(link.ACK, 2, 1, 20),
        packet(link.STATUS, 3, 1, 20, 3),
        packet(link.STATUS, 0xFFFFFFFF, 1, 20, 4),
        packet(link.ACK, 1, 1, 20, link.STALE),
    ]
    (directory / "commands.hex").write_text(
        "\n".join(p.encode().hex() for p in commands) + "\n", encoding="ascii")
    (directory / "replies.hex").write_text(
        "\n".join(p.encode().hex() for p in replies) + "\n", encoding="ascii")
    (directory / "vectors.json").write_text(
        json.dumps({"commands": [asdict(p) for p in commands],
                    "replies": [asdict(p) for p in replies]}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--vectors", type=Path)
    args, rest = parser.parse_known_args()
    if args.vectors:
        vectors(args.vectors)
    else:
        unittest.main(argv=[sys.argv[0], *rest])
