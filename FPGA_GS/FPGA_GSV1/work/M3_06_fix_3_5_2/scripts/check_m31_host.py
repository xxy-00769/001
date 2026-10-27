from pathlib import Path
import subprocess,datetime,hashlib,json,sys
R=Path(__file__).resolve().parents[1];O=R/'reports'/('host_m31_final_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));O.mkdir()
files=list((R/'tools/m3').glob('*.py'))+[R/'config/m3_endpoints.json']
inputs={str(n):hashlib.sha256(n.read_bytes()).hexdigest() for n in files}
c=subprocess.run([sys.executable,'-X','utf8',str(R/'tools/m3/test_protocol.py')],cwd=R,capture_output=True,text=True,encoding='utf-8')
(O/'run.log').write_text(c.stdout+c.stderr,encoding='utf-8')
result={'Verdict':'PASS' if c.returncode==0 and 'M3_HOST_PASS' in c.stdout else 'ERROR',
 'InputsUnchanged':all(hashlib.sha256(Path(n).read_bytes()).hexdigest()==h for n,h in inputs.items()),'BoardMeasured':False}
(O/'inputs.json').write_text(json.dumps(inputs,indent=2));(O/'result.json').write_text(json.dumps(result,indent=2));print(O);print(json.dumps(result));print(c.stdout+c.stderr)
sys.exit(0 if result['Verdict']=='PASS' and result['InputsUnchanged'] else 1)
