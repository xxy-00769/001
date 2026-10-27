import json,hashlib
from pathlib import Path
r=Path('.');b=Path('E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/release/FPGA_GSV1_M3_06_3_5_1')
m=json.loads((b/'source_sha256.json').read_text());mismatches=[n for n,h in m.items() if hashlib.sha256((b/'source'/n).read_bytes()).hexdigest()!=h]
changed=[]
for n in m:
 if (r/n).exists() and (r/n).read_bytes()!=(b/'source'/n).read_bytes():changed.append(n)
(r/'reports/baseline_scope.json').write_text(json.dumps(dict(baseline=str(b),manifest_files=len(m),baseline_mismatches=mismatches,changed_existing=changed,root_3_4_used=False),indent=2))
print('Baseline mismatches:',mismatches);print('Changed:',changed)
(r/'reports/orangepi_stats_delta.json').write_text(json.dumps(dict(source='User SSH transcript, 2026-10-22 14:31:36..14:31:46 CST',first=dict(mmc_rx_framecount_gb=2014495,mmc_rx_crc_error=2014495,mmc_rx_octetcount_gb=2763421047,mmc_rx_octetcount_g=0),last=dict(mmc_rx_framecount_gb=2014505,mmc_rx_crc_error=2014505,mmc_rx_octetcount_gb=2763421687,mmc_rx_octetcount_g=0),software_RX_packets=0,hardware_delta_bad_frames=10,hardware_delta_bytes=640),indent=2))
