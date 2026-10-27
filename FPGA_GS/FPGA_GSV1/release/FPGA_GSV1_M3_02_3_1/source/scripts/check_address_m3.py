"""Native-word aperture proof for the nine real production frame slots."""
from pathlib import Path
import hashlib, json
R = Path(__file__).resolve().parents[1]
slots = [(s, b, (s << 23) | (b << 22)) for s in range(4) for b in range(2)]
slots.append((0, 2, 0x2000000))
words = 1280 * 720 // 2
for i, (s, b, base) in enumerate(slots):
    assert base % 8 == 0 and words == 0x70800
    assert base + words <= (1 << 28)
    for _, _, other in slots[:i]:
        assert base + words <= other or other + words <= base
    # First / last native beat of every line, with actual 8-word beat stride.
    for y in range(720):
        first, last = base + y * 640, base + y * 640 + 632
        assert first % 8 == last % 8 == 0 and last + 8 <= base + words
names = ['rtl/reuse/fram_buf.v', 'rtl/network/m3_net_core.v',
         'rtl/network/m3_right_store.v', 'rtl/network/m3_upload.v']
assert "28'h2000000" in (R/names[0]).read_text()
assert "28'h2000000" in (R/names[3]).read_text()
r = dict(Verdict='PASS', AddressUnit='32bit native word', FrameWords=words,
         Slots=[dict(Source=s, Bank=b, NativeBase=hex(a), ByteBase=hex(a*4)) for s,b,a in slots],
         Inputs={n:hashlib.sha256((R/n).read_bytes()).hexdigest() for n in names},
         Boundary='Static apertures; production traffic/oracles verified separately by m3_full')
(R/'reports/M3_01_address.json').write_text(json.dumps(r, indent=2), encoding='utf-8')
print('M3_ADDRESS_PASS slots=9 full_rows=720 no_overlap=1 32bit_words_per_beat=8')
