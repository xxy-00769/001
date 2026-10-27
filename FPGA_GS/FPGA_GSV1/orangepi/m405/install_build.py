from pathlib import Path
import zipfile,site
base=Path('.venv405build/lib/python3.10/site-packages')
for p in Path('m405/wheels').glob('*.whl'):
 print('extract',p.name,flush=True);zipfile.ZipFile(p).extractall(base)
(base/'m404_runtime.pth').write_text(str(Path('.venv404/lib/python3.10/site-packages').resolve())+'\n')
