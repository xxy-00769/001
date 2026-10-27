"""Generate independent Ethernet/IP/UDP/FCS fixtures, without a NIC."""
from pathlib import Path
import argparse
import ipaddress
import json
import struct
import zlib

LOCAL_MAC = bytes.fromhex("025048500001")
PEER_MAC = bytes.fromhex("02aabbccddee")
LOCAL_IP = ipaddress.ip_address("192.168.50.11").packed
PEER_IP = ipaddress.ip_address("192.168.50.105").packed
PAYLOAD = bytes.fromhex("4d35443101010000123456780000000100000000000000000000000080fe8ea1")


def checksum(data):
    if len(data) % 2:
        data += b"\0"
    total = sum(struct.unpack(f"!{len(data)//2}H", data))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def packet(payload=PAYLOAD, zero_udp=False):
    udp = bytearray(struct.pack("!HHHH", 8000, 8000, 8 + len(payload), 0) + payload)
    pseudo = PEER_IP + LOCAL_IP + struct.pack("!BBH", 0, 17, len(udp))
    if not zero_udp:
        udp[6:8] = struct.pack("!H", checksum(pseudo + udp) or 0xFFFF)
    ip = bytearray(struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp),
                               1, 0x4000, 64, 17, 0, PEER_IP, LOCAL_IP))
    ip[10:12] = struct.pack("!H", checksum(ip))
    return bytearray(LOCAL_MAC + PEER_MAC + b"\x08\x00" + ip + udp)


def update_checksums(body):
    body[24:26] = b"\0\0"
    body[24:26] = struct.pack("!H", checksum(body[14:34]))
    body[40:42] = b"\0\0"
    pseudo = body[26:34] + b"\0\x11" + body[38:40]
    body[40:42] = struct.pack("!H", checksum(pseudo + body[34:]) or 0xFFFF)
    return body


def wire(body):
    return b"\x55" * 7 + b"\xd5" + body + struct.pack("<I", zlib.crc32(body))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=False)
    cases = []

    def add(name, data, valid=False, error_at=-1):
        cases.append(dict(name=name, data=data.hex(), valid=valid, error_at=error_at))

    add("valid_nonzero_udp_checksum", wire(packet()), True)
    add("valid_absent_ipv4_udp_checksum", wire(packet(zero_udp=True)), True)
    b = packet()
    b[20:22] = b"\0\0"
    add("valid_no_df_flag", wire(update_checksums(b)), True)
    add("valid_arbitrary_payload_byte_order", wire(packet(bytes(range(32)))), True)
    b = bytearray(wire(packet()))
    b[-1] ^= 1
    add("bad_fcs", b)
    b = packet()
    b[24] ^= 1
    add("bad_ip_checksum_good_fcs", wire(b))
    b = packet()
    b[40] ^= 1
    add("bad_udp_checksum_good_fcs", wire(b))
    for name, offset, value in [
        ("wrong_destination_mac", 0, 4),
        ("multicast_source_mac", 6, 3),
        ("unsupported_ethertype", 12, 0x86),
        ("ipv4_options_unsupported", 14, 0x46),
        ("wrong_ip_total_length", 17, 59),
        ("reserved_fragment_bit", 20, 0x80),
        ("more_fragments", 20, 0x20),
        ("nonzero_fragment_offset", 21, 1),
        ("zero_ttl", 22, 0),
        ("wrong_ip_protocol", 23, 6),
        ("wrong_source_ip", 29, 106),
        ("wrong_destination_ip", 33, 12),
        ("wrong_source_port", 35, 0x41),
        ("wrong_destination_port", 37, 0x41),
        ("wrong_udp_length", 39, 39),
    ]:
        b = packet()
        b[offset] = value
        add(name, wire(update_checksums(b)))
    b = packet()
    b[6:12] = b"\0" * 6
    add("zero_source_mac", wire(b))
    add("short_payload_valid_checksums", wire(packet(PAYLOAD[:-1])))
    add("long_payload_valid_checksums", wire(packet(PAYLOAD + b"\0")))
    add("extra_ethernet_byte_valid_fcs", wire(packet() + b"\0"))
    add("truncated_fcs", wire(packet())[:-1])
    add("oversize_bounded_capture", wire(packet() + b"\0" * 200))
    b = bytearray(wire(packet()))
    b[7] = 0x55
    add("invalid_preamble_sfd", b)
    add("phy_error_in_preamble", wire(packet()), error_at=0)
    add("phy_error_in_payload", wire(packet()), error_at=60)
    add("phy_error_at_last_fcs", wire(packet()), error_at=85)

    calls = []
    for n, case in enumerate(cases):
        data = bytes.fromhex(case["data"])
        filename = f"case_{n:02}.hex"
        (args.directory / filename).write_text(
            "\n".join(f"{octet:02x}" for octet in data) + "\n", encoding="ascii")
        payload = data[50:82] if case["valid"] else bytes(32)
        calls.append(f'run_case("vectors/{filename}", {len(data)}, '
                     f'{int(case["valid"])}, {case["error_at"]}, 256\'h{payload.hex()});')
    (args.directory / "cases.svh").write_text("\n".join(calls) + "\n", encoding="ascii")
    (args.directory / "manifest.json").write_text(json.dumps(cases, indent=2), encoding="utf-8")

    def app_packet(kind, seq, value=0, lease=0):
        head = struct.pack("!4sBBBBIIIII", b"M5D1", 1, kind, 0, 0,
                           0x12345678, seq, value, lease, 0)
        return head + struct.pack("!I", zlib.crc32(head))

    def hex_bytes(name, data):
        (args.directory / name).write_text(
            "\n".join(f"{octet:02x}" for octet in data) + "\n", encoding="ascii")

    bad_led = bytearray(wire(packet(app_packet(3, 2, 1, 2000))))
    bad_led[-1] ^= 1
    hex_bytes("bad_fcs_led.hex", bad_led)
    hex_bytes("good_led.hex", wire(packet(app_packet(3, 2, 1, 2000))))
    bad_udp_led = packet(app_packet(3, 3, 0, 2000))
    bad_udp_led[40] ^= 1
    hex_bytes("bad_udp_led.hex", wire(bad_udp_led))
    (args.directory / "app_replies.hex").write_text(
        app_packet(0x81, 1).hex() + "\n" + app_packet(0x81, 2, 1, 2000).hex() + "\n",
        encoding="ascii")
    print(json.dumps({"cases": len(cases), "valid": sum(c["valid"] for c in cases)}))


if __name__ == "__main__":
    main()
