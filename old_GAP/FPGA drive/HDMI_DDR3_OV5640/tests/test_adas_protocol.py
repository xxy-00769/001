import binascii
import dataclasses
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "host"))
from adas_protocol import Decoder, Freshness, HEADER, Observation, encode
from adas_demo import simulated_policy


def example(frame_id=1):
    return Observation(0x47, 5, frame_id, 0, 560, 400, 496, 360, 688,
                       880, 496, 920, 688, 280, 280, 0, 0)


class ProtocolTests(unittest.TestCase):
    def test_crc_standard_check(self):
        self.assertEqual(binascii.crc_hqx(b"123456789", 0xFFFF), 0x29B1)

    def test_all_split_boundaries(self):
        packet = encode(example())
        for split in range(len(packet) + 1):
            decoder = Decoder()
            self.assertEqual(decoder.feed(packet[:split]) + decoder.feed(packet[split:]), [example()])

    def test_noise_corruption_and_back_to_back(self):
        corrupt = bytearray(encode(example(9)))
        corrupt[20] ^= 0x80
        decoder = Decoder()
        wire = b"noise\xa5\xa5\x5a\x09\x20" + corrupt + encode(example(10)) + encode(example(11))
        result = []
        for byte in wire:
            result.extend(decoder.feed(bytes([byte])))
        self.assertEqual(result, [example(10), example(11)])
        self.assertGreaterEqual(decoder.crc_errors, 1)

    def test_removed_byte_resynchronizes(self):
        packet = encode(example())
        decoder = Decoder()
        self.assertEqual(decoder.feed(packet[:17] + packet[18:] + encode(example(2))), [example(2)])

    def test_signed_offsets(self):
        obs = dataclasses.replace(example(), offset_px=-100)
        self.assertEqual(Decoder().feed(encode(obs)), [obs])

    def test_bad_semantics_with_valid_crc(self):
        payload = bytearray(example().payload())
        payload[0] = 0x44
        body = HEADER[2:] + payload
        packet = HEADER[:2] + body + struct.pack("<H", binascii.crc_hqx(body, 0xFFFF))
        decoder = Decoder()
        self.assertEqual(decoder.feed(packet), [])
        self.assertEqual(decoder.invalid_packets, 1)

    def test_duplicate_reorder_wrap_and_timeout(self):
        tracker = Freshness()
        self.assertTrue(tracker.accept(example(65535), 0.0))
        self.assertTrue(tracker.accept(example(0), 0.1))
        self.assertFalse(tracker.accept(example(0), 0.2))
        self.assertFalse(tracker.accept(example(65535), 0.3))
        self.assertIsNone(tracker.current(0.7))
        self.assertTrue(tracker.accept(example(1), 0.8))

    def test_missing_frames(self):
        tracker = Freshness()
        tracker.accept(example(2), 0.0)
        tracker.accept(example(5), 0.1)
        self.assertEqual(tracker.missed_frames, 2)

    def test_invalid_time_configuration(self):
        for value in (0, -1, float("nan"), float("inf")):
            with self.assertRaises(ValueError):
                Freshness(value)
        with self.assertRaises(ValueError):
            Freshness().accept(example(), float("nan"))

    def test_simulation_never_reports_safe_to_change(self):
        result = simulated_policy(example(), speed_kmh=60, limit_kmh=50, distance_m=10, turn="left")
        self.assertTrue(result["simulated_overspeed"])
        self.assertTrue(result["simulated_proximity_alert"])
        self.assertFalse(result["actuator_output"])
        self.assertEqual(result["lane_change_safety"], "NOT_ASSESSED")
        self.assertEqual(result["source"], "SOFTWARE_SIMULATION_ONLY")

    def test_simulation_missing_measurement_and_invalid_input(self):
        self.assertFalse(simulated_policy(None, speed_kmh=0, limit_kmh=50)["simulated_proximity_alert"])
        for value in (float("nan"), -1, 251):
            with self.assertRaises(ValueError):
                simulated_policy(None, speed_kmh=value, limit_kmh=50)


if __name__ == "__main__":
    if "--vectors" in sys.argv:
        output = Path(__file__).parent / "output" / "adas"
        output.mkdir(parents=True, exist_ok=True)
        observations = [example(65535), dataclasses.replace(example(0), offset_px=-100),
                        Observation(0x40, 0, 1, *([0] * 14))]
        wire = b"".join(encode(obs) for obs in observations)
        (output / "packets.hex").write_text("\n".join(f"{byte:02X}" for byte in wire) + "\n", encoding="ascii")
        (output / "packets_expected.bin").write_bytes(wire)
        print("Wrote 114 independently CRC-encoded packet bytes")
        sys.argv.remove("--vectors")
    unittest.main()
