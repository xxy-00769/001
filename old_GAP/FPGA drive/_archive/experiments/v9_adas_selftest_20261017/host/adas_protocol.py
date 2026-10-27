"""Transport-neutral v1 FPGA result decoder. Python 3.10+, standard library only."""
from __future__ import annotations

import argparse
import binascii
import dataclasses
import json
import math
import struct
import sys
from pathlib import Path

MAGIC = b"\xa5\x5a"
HEADER = MAGIC + b"\x01\x20"
PACKET_SIZE = 38
PAYLOAD = struct.Struct("<BBHh13H")
KINDS = ("unknown", "solid_candidate", "dashed_candidate")


@dataclasses.dataclass(frozen=True)
class Observation:
    flags: int
    types: int
    frame_id: int
    offset_px: int
    lane_width: int
    left_x0: int
    left_y0: int
    left_x1: int
    left_y1: int
    right_x0: int
    right_y0: int
    right_x1: int
    right_y1: int
    left_support: int
    right_support: int
    zebra_y0: int
    zebra_y1: int

    @property
    def pair_valid(self):
        return bool(self.flags & 4)

    @property
    def left_kind(self):
        return self.types & 3

    @property
    def right_kind(self):
        return (self.types >> 2) & 3

    def validate(self):
        if self.flags & 0x80 or not self.flags & 0x40 or self.types & 0xC0:
            raise ValueError("Reserved flags or non-experimental frame")
        if any(value > 2 for value in (self.left_kind, self.right_kind, (self.types >> 4) & 3)):
            raise ValueError("Invalid type code")
        if self.flags & 0x10 and not self.flags & 8:
            raise ValueError("Crosswalk confirmation without candidate")
        if self.pair_valid and (self.flags & 3 != 3 or not self.lane_width):
            raise ValueError("Pair requires both sides and a nonzero width")
        if not self.pair_valid and (self.offset_px or self.lane_width or self.types & 0x30):
            raise ValueError("Invalid pair carries offset/width/warning")
        if self.flags & 0x20 and (self.flags & 0x1F or self.types):
            raise ValueError("Malformed frame carries a valid observation")
        for flag, kind, points in (
            (1, self.left_kind, (self.left_x0, self.left_y0, self.left_x1, self.left_y1)),
            (2, self.right_kind, (self.right_x0, self.right_y0, self.right_x1, self.right_y1)),
        ):
            if not self.flags & flag and (kind or any(points)):
                raise ValueError("Missing side carries stale geometry")
            if self.flags & flag and points[3] <= points[1]:
                raise ValueError("Lane segment has non-increasing rows")
        values = dataclasses.astuple(self)
        if not -2048 <= self.offset_px <= 2047 or any(value > 2047 for value in values[4:]):
            raise ValueError("Geometry outside the RTL field width")
        if not self.flags & 8 and (self.zebra_y0 or self.zebra_y1):
            raise ValueError("Missing crosswalk carries stale geometry")
        if self.flags & 8 and self.zebra_y0 > self.zebra_y1:
            raise ValueError("Invalid crosswalk bounds")
        if self.pair_valid and (self.right_x1 <= self.left_x1
                                or self.lane_width != self.right_x1 - self.left_x1):
            raise ValueError("Inconsistent near lane width")
        return self

    def payload(self):
        self.validate()
        return PAYLOAD.pack(*dataclasses.astuple(self))

    def as_dict(self):
        return {
            "frame_id": self.frame_id,
            "experimental": True,
            "malformed_frame": bool(self.flags & 0x20),
            "left_valid": bool(self.flags & 1),
            "right_valid": bool(self.flags & 2),
            "pair_valid": self.pair_valid,
            "left_kind": KINDS[self.left_kind],
            "right_kind": KINDS[self.right_kind],
            "camera_offset_px": self.offset_px if self.pair_valid else None,
            "lane_width_px": self.lane_width if self.pair_valid else None,
            "offset_warning": ("none", "camera_left", "camera_right")[(self.types >> 4) & 3],
            "crosswalk_candidate": bool(self.flags & 8),
            "crosswalk_confirmed": bool(self.flags & 0x10),
        }


def encode(observation: Observation) -> bytes:
    body = HEADER[2:] + observation.payload()
    return MAGIC + body + struct.pack("<H", binascii.crc_hqx(body, 0xFFFF))


class Decoder:
    """Incremental framing, CRC verification and resynchronization after noise."""

    def __init__(self):
        self.buffer = bytearray()
        self.crc_errors = 0
        self.invalid_packets = 0

    def feed(self, chunk: bytes) -> list[Observation]:
        self.buffer.extend(chunk)
        records = []
        while True:
            start = self.buffer.find(MAGIC)
            if start < 0:
                self.buffer[:] = b"\xa5" if self.buffer.endswith(b"\xa5") else b""
                break
            del self.buffer[:start]
            if len(self.buffer) < 4:
                break
            if self.buffer[:4] != HEADER:
                self.invalid_packets += 1
                del self.buffer[0]
                continue
            if len(self.buffer) < PACKET_SIZE:
                break
            packet = bytes(self.buffer[:PACKET_SIZE])
            if binascii.crc_hqx(packet[2:36], 0xFFFF) != int.from_bytes(packet[36:], "little"):
                self.crc_errors += 1
                del self.buffer[0]
                continue
            try:
                observation = Observation(*PAYLOAD.unpack(packet[4:36])).validate()
            except ValueError:
                self.invalid_packets += 1
            else:
                records.append(observation)
            del self.buffer[:PACKET_SIZE]
        return records


class Freshness:
    """Do not present old, duplicate or out-of-order frames as current results."""

    def __init__(self, timeout=0.5):
        if not math.isfinite(timeout) or timeout <= 0:
            raise ValueError("Timeout must be positive")
        self.timeout = timeout
        self.last = None
        self.received_at = None
        self.missed_frames = 0

    def accept(self, observation: Observation, now: float) -> bool:
        observation.validate()
        if not math.isfinite(now):
            raise ValueError("Timestamp must be finite and monotonic")
        if self.last is not None and self.received_at is not None and now - self.received_at <= self.timeout:
            delta = (observation.frame_id - self.last.frame_id) & 0xFFFF
            if not 0 < delta < 0x8000:
                return False
            self.missed_frames += delta - 1
        self.last = observation
        self.received_at = now
        return True

    def current(self, now: float):
        if not math.isfinite(now):
            raise ValueError("Timestamp must be finite and monotonic")
        if self.received_at is None or now - self.received_at > self.timeout:
            return None
        return self.last


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", nargs="?", type=Path, help="Binary capture; omit to read stdin")
    args = parser.parse_args()
    stream = args.capture.open("rb") if args.capture else sys.stdin.buffer
    decoder = Decoder()
    count = 0
    try:
        while chunk := stream.read(4096):
            for observation in decoder.feed(chunk):
                print(json.dumps({"source": "CAPTURE_REPLAY", **observation.as_dict()}))
                count += 1
    finally:
        if args.capture:
            stream.close()
    print(f"Decoded {count}; CRC errors={decoder.crc_errors}; invalid={decoder.invalid_packets}; "
          f"trailing bytes={len(decoder.buffer)}", file=sys.stderr)


if __name__ == "__main__":
    main()
