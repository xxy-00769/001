"""Documentation only: expand recorded release identities and check document links.
No FPGA build/test, hardware, serial, network, service or production-source operations.
"""
from pathlib import Path
import csv
import hashlib
import json
import re
from datetime import datetime, timezone

base = Path(__file__).resolve().parent
doc = base / 'FPGA完整开发交接.md'
rows = list(csv.DictReader((base / 'FPGA发布版本索引.tsv').open(encoding='utf-8-sig'), delimiter='\t'))
table = ['| 发布目录与位流文件名（均在release/下） | 原生成时间 | SHA256及原依据 |',
         '|---|---|---|']
for r in rows:
    directory = r['Release'].removeprefix('release/')
    bit = Path(r['Bitstream']).name
    table.append(f"| `{directory}/`<br>`{bit}` | {r['Generated_recorded']} | `{r['SHA256_existing'].lower()}`<br>原依据：`{r['HashEvidence']}` |")
content = doc.read_text(encoding='utf-8')
content = content.split('<!-- VERSION_TABLE -->', 1)[0] + '<!-- VERSION_TABLE -->\n\n' + '\n'.join(table) + '\n'
doc.write_text(content, encoding='utf-8')
links = re.findall(r'(?<!!)\[[^\]]+\]\(([^)]+)\)', content)
missing = []
for link in links:
    if '://' in link or link.startswith('#'):
        continue
    path = link.split('#', 1)[0].strip('<>')
    if path and not (base / path).exists():
        missing.append(link)
result = dict(
    documentation_only=True,
    observed_utc=datetime.now(timezone.utc).isoformat(),
    release_rows=len(rows),
    markdown_links=len(links),
    missing_local_links=missing,
    note='Document assembly/link existence check only. No implementation tests or hardware access.'
)
(base / 'FPGA交接文档核对.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
names = [
    'FPGA完整开发交接.md', 'FPGA发布版本索引.tsv', 'FPGA早期源码补复制.tsv',
    'FPGA冻结发布输入清单.tsv', 'FPGA当前work输入快照.tsv', 'FPGA_R0构建依赖闭包.tsv',
    'FPGA交接只读核对.json', '生成FPGA交接清单.py', '完成FPGA交接附录.py',
    'FPGA交接文档核对.json'
]
lines = [f"{hashlib.sha256((base / name).read_bytes()).hexdigest()}  {name}" for name in names]
(base / 'FPGA交接文件SHA256.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
print(f'Document bytes: {doc.stat().st_size}; manifest entries: {len(names)}')
