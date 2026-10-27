import urllib.request
from pathlib import Path
r=Path(__file__).resolve().parents[1];rev='2c723177a94fac65cbc036d722907ddbc91980cf';u=f'https://raw.githubusercontent.com/airockchip/rknn-toolkit2/{rev}/doc/EN/06_RKNN2_Supported_Operators_and_Constraints_Reference_V2.5.0.pdf'
p=r/'sources/RKNN_operators_V2.5.0.pdf';p.write_bytes(urllib.request.urlopen(u,timeout=40).read());print(p.stat().st_size,flush=True)
