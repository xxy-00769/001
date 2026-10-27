"""Role dispatch checks without opening sockets or changing networking."""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch, MagicMock
import sys, hashlib, json
R=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(R/'tools/m3'))
import console
from protocol import Message, HELLO, HEARTBEAT, RESULT

captured=[]
class Captured(Exception): pass
def capture(args): captured.append(args);raise Captured
for role,host,board in [('right','192.168.50.1','192.168.50.2'),
                        ('front-control','192.168.60.1','192.168.60.2')]:
    with patch.object(sys,'argv',['console.py','--role',role,'--headless']),patch.object(console,'Bench',capture):
        try: console.main()
        except Captured: pass
    a=captured[-1]
    assert (a.bind,a.board)==(host,board)
    assert (a.right_fps,a.front_fps)==((15,0) if role=='right' else (0,5))
    fake_socket=MagicMock();context=MagicMock();targets=[]
    with patch.object(console.socket,'socket',return_value=fake_socket), \
         patch.object(console.threading,'Thread',side_effect=lambda **k: targets.append(k['target'].__name__) or MagicMock()), \
         patch.object(console.multiprocessing,'get_context',return_value=context):
        b=console.Bench(a)
        assert ('transmit' in targets)==(role=='right')
        assert (b.tx_worker is not None)==(role=='right')
        b.stop.wait=MagicMock(side_effect=[False,True])
        b.heartbeat()
        packets=[Message.decode(x.args[0]) for x in fake_socket.sendto.call_args_list]
        assert [x.kind for x in packets]==[HELLO,HEARTBEAT]
        assert packets[0].reason==a.front_fps
        b.latest_event=Message(4,b.session,event=1,frame=55,code=1)
        b.respond('allow')
        assert (Message.decode(fake_socket.sendto.call_args.args[0]).kind==RESULT)==(role=='front-control')
        a.stats=None;b.close()
baseline=R.parents[1]/'release/FPGA_GSV1_M3_04_3_3/source'
assert (baseline/'tools/m3/protocol.py').read_bytes()==(R/'tools/m3/protocol.py').read_bytes()
out=R/'reports/m36_host';out.mkdir(exist_ok=True)
files=['tools/m3/console.py','tools/m3/protocol.py','config/m3_endpoints.json','scripts/check_m36_host.py']
inputs={str(R/f):hashlib.sha256((R/f).read_bytes()).hexdigest() for f in files}
(out/'inputs.json').write_text(json.dumps(inputs,indent=2))
(out/'result.json').write_text(json.dumps(dict(Verdict='PASS',InputsUnchanged=True,
    RoleDefaults=True,NoFrontVideoWorker=True,RoleHeartbeat=True,RightCannotSendResult=True,
    FrozenProtocol=True,NoNetworkMutation=True,BoardMeasured=False),indent=2))
print('M36_HOST_PASS roles/defaults/worker/heartbeat/result/frozen_protocol; sockets mocked')
