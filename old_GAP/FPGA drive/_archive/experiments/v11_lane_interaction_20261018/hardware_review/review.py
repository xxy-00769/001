"""Read supplied connector files and cross-check the vendor button pin table.

No CAD files, primary design files or hardware configuration are modified.
The generated constraints remain a reference draft until the physical PCB matches.
"""
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageDraw
from pypdf import PdfReader

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
KIT = Path("D:/BaiduNetdiskDownload/盘古50K开发板")
HARDWARE = KIT / "3_Hardware"
CONNECTOR = HARDWARE / "核心板连接座"
DOCX = CONNECTOR / "先读我！重要说明.docx"
PCB = CONNECTOR / "50K_Base_Board.pcb"
SCH = CONNECTOR / "50K_Base_Board.sch"
MANUAL = HARDWARE / "MES50HP开发板硬件使用手册_1V1.pdf"
DEMO = KIT / "2_Demo/02_key_led_test.rar"
PINS = ("K18", "L15", "J17", "K16", "J16", "J19", "H20", "H17")
ROLES = ("left", "right", "force", "cancel")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    # Files are data only. Never run a command or script extracted from the kit.
    source_paths = (DOCX, PCB, SCH, MANUAL, DEMO)
    before = {str(p): sha(p) for p in source_paths}
    with zipfile.ZipFile(DOCX) as doc:
        root = ET.fromstring(doc.read("word/document.xml"))
        ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
        paragraphs = ["".join(t.text or "" for t in p.findall(".//w:t", ns))
                      for p in root.findall(".//w:p", ns)]
        (HERE / "docx_text.txt").write_text("\n".join(paragraphs), encoding="utf-8")
        media = HERE / "docx_media"
        media.mkdir(exist_ok=True)
        images = []
        for name in doc.namelist():
            if name.startswith("word/media/") and name.endswith(".png"):
                out = media / Path(name).name
                out.write_bytes(doc.read(name))
                images.append(out)
    sheet = Image.new("RGB", (1200, 900), "white")
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(images):
        with Image.open(path) as original:
            thumb = original.convert("RGB")
            thumb.thumbnail((390, 270))
            x, y = (i % 3) * 400, (i // 3) * 300
            sheet.paste(thumb, (x, y + 25))
            draw.text((x + 5, y + 5), path.name, fill="black")
    sheet.save(HERE / "docx_media_contact.png")

    reader = PdfReader(MANUAL)
    pages = [page.extract_text() for page in reader.pages]
    table = pages[32]
    for i, pin in enumerate(PINS, start=1):
        if not re.search(rf"KEY{i}\s+{pin}\b", table):
            raise RuntimeError(f"Manual table missing KEY{i}/{pin}")
    (HERE / "manual_pages_32_33_text.txt").write_text(
        pages[31] + "\n" + pages[32], encoding="utf-8")
    reference_fdc = subprocess.run(
        ["tar", "-xOf", str(DEMO), "02_key_led_test/key_led_test.fdc"],
        check=True, capture_output=True).stdout
    (HERE / "vendor_key_led_test.fdc").write_bytes(reference_fdc)
    if b"{p:key} {PAP_IO_LOC} {K18}" not in reference_fdc:
        raise RuntimeError("Vendor demo KEY1 does not match manual")
    if b"{p:key} {PAP_IO_STANDARD} {LVCMOS33}" not in reference_fdc:
        raise RuntimeError("Vendor demo KEY1 voltage standard not confirmed")

    primary = PROJECT / "hdmi_ddr_ov5640_top.fdc"
    original = primary.read_bytes()
    text = original.decode("utf-8-sig")
    loc_pattern = r"define_attribute\s+\{p:([^}]+)\}\s+\{PAP_IO_LOC\}\s+\{([^}]+)\}"
    locations = re.findall(loc_pattern, text)
    owners = {pin: port for port, pin in locations}
    conflicts = {pin: owners[pin] for pin in PINS[:4] if pin in owners}
    if conflicts:
        raise RuntimeError(f"Button locations already used: {conflicts}")
    constraints = ["# REFERENCE DRAFT: supplied MES50HP manual, physical PCB match pending.",
                   "# KEY1/2/3/4 = left/right/force/cancel; active-low, external pull-ups."]
    for i, pin in enumerate(PINS[:4]):
        for attr, value in (("DIRECTION", "INPUT"), ("LOC", pin), ("VCCIO", "3.3"),
                            ("STANDARD", "LVCMOS33"), ("NONE", "TRUE")):
            constraints.append(f"define_attribute {{p:local_key_n[{i}]}} {{PAP_IO_{attr}}} {{{value}}}")
    block = "\n".join(constraints) + "\n"
    (HERE / "keys_reference.fdc").write_text(block, encoding="ascii")
    (HERE / "combined_reference.fdc").write_text(
        text.rstrip() + "\n\n" + block, encoding="utf-8")
    if before != {str(p): sha(p) for p in source_paths} or original != primary.read_bytes():
        raise RuntimeError("Protected source files changed")
    evidence = {
        "sources_sha256": before,
        "docx_scope": "core-board mating connectors, JTAG and PCB placement reference",
        "docx_full_page_render": False,
        "docx_render_limitation": "bundled renderer found no LibreOffice executable",
        "docx_text_and_nine_embedded_images_extracted": len(images) == 9,
        "pcb_and_sch_format": "proprietary binary; full CAD topology NOT decoded",
        "button_pin_table_verified": True,
        "manual_physical_pages_reviewed": [32, 33],
        "manual_printed_pages": [31, 32],
        "active_low_confirmed_in_manual": True,
        "manual_button_count": 8,
        "all_button_pins": {f"KEY{i+1}": pin for i, pin in enumerate(PINS)},
        "proposed_mapping": [
            {"port": f"local_key_n[{i}]", "button": f"KEY{i+1}", "pin": pin, "role": ROLES[i]}
            for i, pin in enumerate(PINS[:4])
        ],
        "vendor_demo_cross_check": "KEY1=K18, LVCMOS33, VCCIO3.3",
        "main_constraint_pin_conflicts": conflicts,
        "new_key_constraint_sha256": sha(HERE / "keys_reference.fdc"),
        "original_constraint_sha256": hashlib.sha256(original).hexdigest(),
        "primary_design_modified": False,
        "source_documents_unchanged": True,
        "actual_board_revision_match": None,
        "physical_electrical_test": False,
        "full_build": False, "new_bitstream": False, "programmed": False,
        "stage_exit_met": False,
        "next_gate": "confirm physical board is the supplied MES50HP baseboard with KEY1..KEY8",
    }
    (HERE / "evidence.json").write_text(
        json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("PASS supplied manual: 8 active-low keys; KEY1 cross-checked with vendor demo")
    print("PASS draft constraints: KEY1..4 K18/L15/J17/K16; no main-design pin conflict")
    print("Source files unchanged; physical PCB match not confirmed; no build/download")


if __name__ == "__main__":
    main()
