from pathlib import Path
from pypdf import PdfReader
r=Path(__file__).resolve().parents[1];p=r/'sources/RKNN_operators_V2.5.0.pdf'
a=PdfReader(p);print('pages',len(a.pages));texts=[]
for i,page in enumerate(a.pages):
 t=page.extract_text() or '';texts.append(f'\n=== PDF PAGE {i+1} ===\n'+t)
 if any(k in t for k in ['ONNX Operators','Conv','Softmax','Resize']):print('PAGE',i+1,t[:14000])
(r/'sources/rknn_operators_extracted.txt').write_text('\n'.join(texts),encoding='utf-8')
