from pathlib import Path
from PIL import Image,ImageDraw
import json
r=Path(__file__).resolve().parents[1];b=r.parent/'m406/evidence';out=Image.new('RGB',(1300,680),'#eeeeee');d=ImageDraw.Draw(out)
for i,color in enumerate(['RED','GREEN']):
 im=Image.open(b/'exact_source'/f'{color}_raw.jpg');print(color,im.size)
 # crop both distant horizontal housings, independently inspect before manual example labels
 region=(1420,580,1800,735); crop=im.crop(region).resize((1140,465));out.paste(crop,(80,i*330+30));d.text((10,i*330+5),f'{color}: source {im.size}, crop {region}, nearest visual inspection only',fill='black')
out.save(r/'artifacts/lamp_inspection.png')
