"""MES50HP S5 diagnostics. Standard library only; no video transport."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import secrets
import socket
import struct
import time
import zlib
from dataclasses import asdict, dataclass

HELLO, PING, LED, STATUS, ACK = 1, 2, 3, 0x80, 0x81
OK, DUPLICATE, BAD_SESSION, STALE, BUSY = range(5)
NAMES = {HELLO: "HELLO", PING: "PING", LED: "LED", STATUS: "STATUS", ACK: "ACK"}
HEADER = struct.Struct("!4sBBBBIIIII")
PORT = 8000


@dataclass(frozen=True)
class Packet:
    kind: int
    session: int
    seq: int
    value: int = 0
    lease_ms: int = 0
    detail: int = 0

    def encode(self) -> bytes:
        if self.kind not in NAMES or not 1 <= self.session <= 0xFFFFFFFF:
            raise ValueError("Invalid kind or session")
        for n in (self.seq, self.value, self.lease_ms, self.detail):
            if not 0 <= n <= 0xFFFFFFFF:
                raise ValueError("Field outside uint32")
        head = HEADER.pack(b"M5D1", 1, self.kind, 0, 0, self.session,
                           self.seq, self.value, self.lease_ms, self.detail)
        return head + struct.pack("!I", zlib.crc32(head))

    @classmethod
    def decode(cls, data: bytes) -> Packet:
        if len(data) != 32:
            raise ValueError("Expected exactly 32 bytes, not image data")
        magic, version, kind, flags, reserved, *values = HEADER.unpack(data[:28])
        if (magic, version, flags, reserved) != (b"M5D1", 1, 0, 0):
            raise ValueError("Invalid magic/version/reserved fields")
        if kind not in NAMES or values[0] == 0:
            raise ValueError("Invalid kind or session")
        if zlib.crc32(data[:28]) != struct.unpack("!I", data[28:])[0]:
            raise ValueError("Application CRC32 mismatch")
        return cls(kind, *values)

    def command_valid(self) -> bool:
        return self.detail == 0 and (
            self.kind in (HELLO, PING) and self.value == self.lease_ms == 0
            or self.kind == LED and self.value in (0, 1) and 1 <= self.lease_ms <= 5000
        )


class DiagnosticModel:
    """Software peer for tool testing, not an RTL or physical-link result."""

    def __init__(self) -> None:
        self.session = 0
        self.last_seq = 0
        self.last_activity = 0.0
        self.led_until = 0.0
        self.led_value = 0
        self.accepted = 0

    def expire(self, now: float) -> None:
        if self.session and now - self.last_activity >= 5.0:
            self.session = 0
            self.led_until = 0
            self.led_value = 0

    def handle(self, command: Packet, now: float) -> Packet | None:
        self.expire(now)
        if not command.command_valid():
            return None
        left = max(0, int((self.led_until - now) * 1000))
        led = int(bool(self.led_value and left and self.session))
        if not self.session and command.kind == HELLO:
            self.session = command.session
            self.last_seq = command.seq
            self.last_activity = now
            self.led_until = 0
            self.led_value = 0
            self.accepted += 1
            return Packet(ACK, command.session, command.seq)
        if command.session != self.session or not self.session:
            code = BUSY if command.kind == HELLO and self.session else BAD_SESSION
            return Packet(ACK, command.session, command.seq, detail=code)
        if command.seq <= self.last_seq:
            code = DUPLICATE if command.seq == self.last_seq else STALE
            return Packet(ACK, command.session, command.seq, led, left, code)
        self.last_seq = command.seq
        self.last_activity = now
        self.accepted += 1
        if command.kind == LED:
            self.led_until = now + command.lease_ms / 1000
            self.led_value = command.value
            return Packet(ACK, command.session, command.seq, command.value, command.lease_ms)
        if command.kind == HELLO:
            return Packet(ACK, command.session, command.seq, led, left)
        return Packet(STATUS, command.session, command.seq, led, left, self.accepted)


class Client:
    def __init__(self, board: str, bind: str, port: int, timeout: float) -> None:
        socket.inet_aton(board)
        socket.inet_aton(bind)
        self.peer = (board, port)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.sock.bind((bind, port))
            self.sock.settimeout(timeout)
        except BaseException:
            self.sock.close()
            raise
        self.timeout = timeout
        self.session = secrets.randbelow(0xFFFFFFFF) + 1
        self.seq = 0
        self.sent = self.received = self.timeouts = self.invalid = self.unmatched = 0

    def close(self) -> None:
        self.sock.close()

    def exchange(self, kind: int, value: int = 0, lease: int = 0) -> Packet | None:
        if self.seq == 0xFFFFFFFF:
            raise RuntimeError("Sequence exhausted; start a fresh session")
        self.seq += 1
        request = Packet(kind, self.session, self.seq, value, lease)
        self.sock.sendto(request.encode(), self.peer)
        self.sent += 1
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            self.sock.settimeout(max(0.001, deadline - time.monotonic()))
            try:
                data, address = self.sock.recvfrom(2048)
            except socket.timeout:
                break
            if address != self.peer:
                self.unmatched += 1
                continue
            try:
                packet = Packet.decode(data)
            except ValueError:
                self.invalid += 1
                continue
            if (packet.session, packet.seq) != (self.session, self.seq):
                self.unmatched += 1
                continue
            expected = STATUS if kind == PING else ACK
            # PING may receive an ACK rejection (expired or unknown session).
            if packet.kind != expected and not (
                kind == PING and packet.kind == ACK and packet.detail in (BAD_SESSION, STALE)
            ):
                self.invalid += 1
                continue
            self.received += 1
            return packet
        self.timeouts += 1
        return None

    def stats(self) -> dict:
        return {key: getattr(self, key) for key in
                ("sent", "received", "timeouts", "invalid", "unmatched")}


def emulator(args: argparse.Namespace) -> int:
    model = DiagnosticModel()
    print("SOFTWARE EMULATOR: not FPGA, PHY, RTL or video evidence.", flush=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((args.bind, args.port))
        sock.settimeout(0.2)
        end = time.monotonic() + args.duration if args.duration else float("inf")
        while time.monotonic() < end:
            try:
                data, address = sock.recvfrom(2048)
            except socket.timeout:
                continue
            try:
                packet = Packet.decode(data)
            except ValueError:
                continue
            response = model.handle(packet, time.monotonic())
            if response:
                sock.sendto(response.encode(), address)
    return 0


def client(args: argparse.Namespace) -> int:
    link = Client(args.board, args.bind, args.port, args.timeout)
    records = []
    print("MES50HP S5 diagnostics only. This version does NOT receive video.", flush=True)
    try:
        hello = link.exchange(HELLO)
        if hello is None or hello.kind != ACK or hello.detail != OK:
            print("HELLO failed. Check bitstream, link, IP, firewall and peer session.")
            return 2
        print(f"Session {link.session:08x} established.", flush=True)
        if args.led is not None:
            response = link.exchange(LED, args.led, args.lease_ms)
            if response is None or response.detail != OK:
                print("LED command not confirmed.")
                return 2
            print(f"LED request={args.led}, lease={args.lease_ms} ms confirmed.", flush=True)
        for _ in range(args.count):
            started = time.monotonic()
            response = link.exchange(PING)
            if response and response.kind == STATUS:
                row = {**asdict(response), "rtt_ms": round((time.monotonic()-started)*1000, 3)}
                records.append(row)
                print(f"seq={response.seq} led={response.value} lease={response.lease_ms}ms "
                      f"accepted={response.detail} rtt={row['rtt_ms']}ms", flush=True)
            elif response:
                print(f"Session rejected, ACK code={response.detail}; restart after expiry.")
                return 2
            else:
                print(f"seq={link.seq} TIMEOUT (not a video freeze indicator)", flush=True)
            time.sleep(max(0, args.interval - (time.monotonic()-started)))
        return 0 if link.timeouts == link.invalid == 0 else 2
    finally:
        summary = {"mode": "udp_diagnostics_no_video", "peer": list(link.peer),
                   "session": link.session, **link.stats(), "records": records}
        print(json.dumps({k: v for k, v in summary.items() if k != "records"}), flush=True)
        if args.log:
            # Exclusive creation preserves previous acceptance records.
            with Path(args.log).open("x", encoding="utf-8") as output:
                json.dump(summary, output, indent=2)
        link.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    receive = sub.add_parser("client", help="Send commands and receive diagnostic replies, not video")
    receive.add_argument("--board", default="192.168.50.11")
    receive.add_argument("--bind", default="192.168.50.105")
    receive.add_argument("--port", type=int, default=PORT)
    receive.add_argument("--timeout", type=float, default=1.0)
    receive.add_argument("--count", type=int, default=20)
    receive.add_argument("--interval", type=float, default=0.5)
    receive.add_argument("--led", type=int, choices=(0, 1))
    receive.add_argument("--lease-ms", type=int, default=2000)
    receive.add_argument("--log")
    simulate = sub.add_parser("emulator", help="Software peer; never claim FPGA connectivity")
    simulate.add_argument("--bind", default="127.0.0.1")
    simulate.add_argument("--port", type=int, default=PORT)
    simulate.add_argument("--duration", type=float, default=0)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be 1..65535")
    if args.mode == "client" and (
        args.timeout <= 0 or args.interval < 0 or not 1 <= args.count <= 100000
        or not 1 <= args.lease_ms <= 5000
    ):
        parser.error("Invalid count, timeout, interval or LED lease")
    try:
        return emulator(args) if args.mode == "emulator" else client(args)
    except (OSError, ValueError, RuntimeError) as exc:
        parser.exit(2, f"Error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
