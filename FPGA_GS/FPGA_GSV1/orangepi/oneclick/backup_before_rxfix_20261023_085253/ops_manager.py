"""Additive v0.1.2 operator tools. Standard library only; never modifies protocol."""
import argparse
import base64
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.request

VERSION='M4-01-operator-v1'

def run(args):
    try:
        p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=5)
        return dict(ok=p.returncode==0,code=p.returncode,stdout=p.stdout.strip(),stderr=p.stderr.strip())
    except (OSError,subprocess.TimeoutExpired) as e: return dict(ok=False,error=str(e))

def ip_json(*args):
    r=run(['ip','-j',*args])
    try: r['data']=json.loads(r.get('stdout',''))
    except ValueError: r['data']=[]
    return r

def proc(pid):
    try:
        p=Path('/proc')/str(pid)
        fields=(p/'stat').read_text().split(') ',1)[1].split()
        if fields[0]=='Z': return None
        return dict(pid=int(pid),start_ticks=fields[19],cwd=str((p/'cwd').resolve(strict=True)),
                    argv=(p/'cmdline').read_bytes().decode().rstrip('\0').split('\0'),
                    uid=p.stat().st_uid)
    except (OSError,ValueError): return None

def identity(a,b):
    return bool(a and b and all(a.get(k)==b.get(k) for k in ('pid','start_ticks','cwd','argv','uid')))

def command(c):
    return ['.venv/bin/python','main.py','--mode','LIVE_FRONT','--bind',c['business_cidr'].split('/')[0],
            '--peer',c['fpga_ip'],'--port',str(c['udp_port']),'--peer-port',str(c['peer_port']),
            '--scene',c['scene'],'--preview-fps',str(c['preview_fps']),'--preview-width',str(c['preview_width']),
            '--preview-quality',str(c['preview_quality']),'--output',c['output'],'--web-port',str(c['web_port'])]

def matches(p,c):
    if not p or p['cwd']!=c['remote_dir'] or p['uid']!=os.getuid(): return False
    args=p['argv']
    if len(args)<2 or Path(args[1]).name!='main.py': return False
    try:
        if Path(args[0]).name not in ('python','python3','python3.10'): return False
        expected=command(c)[2:]
        # Order is immaterial; extra options are refused, not silently adopted.
        return len(args[2:])==len(expected) and dict(zip(args[2::2],args[3::2]))==dict(zip(expected[::2],expected[1::2]))
    except (ValueError,IndexError): return False

def processes(c):
    return [p for d in Path('/proc').iterdir() if d.name.isdigit() and (p:=proc(int(d.name))) and matches(p,c)]

def owners(c):
    ports={f'{c["web_port"]:04X}':'tcp',f'{c["udp_port"]:04X}':'udp'}
    inodes={}; rows=[]
    for proto in ('tcp','tcp6','udp','udp6'):
        try: lines=Path('/proc/net',proto).read_text().splitlines()[1:]
        except OSError: continue
        for line in lines:
            fields=line.split(); port=fields[1].split(':')[1]
            if (proto.startswith('tcp') and port==f'{c["web_port"]:04X}' and fields[3]=='0A') or (proto.startswith('udp') and port==f'{c["udp_port"]:04X}'):
                row=dict(protocol=proto,local_hex=fields[1],local_port=int(port,16),inode=fields[9],pids=[])
                rows.append(row);inodes.setdefault(fields[9],[]).append(row)
    for d in Path('/proc').iterdir():
        if not d.name.isdigit(): continue
        try:
            for fd in (d/'fd').iterdir():
                target=os.readlink(fd)
                if target.startswith('socket:['):
                    for row in inodes.get(target[8:-1],[]):
                        if int(d.name) not in row['pids']: row['pids'].append(int(d.name))
        except OSError: continue
    for row in rows: row['processes']=[proc(pid) for pid in row['pids']]
    return rows

def status(c):
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{c["web_port"]}/status.json',timeout=2) as r:
            return dict(ok=True,data=json.load(r))
    except Exception as e: return dict(ok=False,error=str(e))

def read_number(p):
    try: return int(p.read_text().strip())
    except (OSError,ValueError): return None

def jpeg_status(c):
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{c["web_port"]}/latest.jpg?t=diagnostic',timeout=1) as r:
            return dict(ok=True,sequence=r.headers.get('X-Frame-Sequence'),frame_id=r.headers.get('X-Frame-ID'),age_ms=r.headers.get('X-Frame-Age-Ms'))
    except Exception as e:return dict(ok=False,error=str(e))

def sample(c):
    nic=Path('/sys/class/net')/c['interface']
    return dict(monotonic=time.monotonic(),status=status(c),jpeg=jpeg_status(c),carrier=read_number(nic/'carrier'),
        counters={k:read_number(nic/'statistics'/k) for k in ('rx_packets','tx_packets','rx_bytes','tx_bytes','rx_errors','rx_dropped')})

def delta(a,b):
    if a is None or b is None or b<a:return None
    return b-a

def validate(c):
    root=Path(c['remote_dir'])
    if not root.is_absolute() or root.resolve()!=root: raise ValueError('远端目录必须是实际绝对路径，不使用软链接')
    ipaddress.ip_interface(c['business_cidr']);ipaddress.ip_address(c['fpga_ip'])
    if c['interface']!='eth0': raise ValueError('业务接口不是eth0；请核对集中配置，拒绝猜测SSH网卡')
    for key in ('scene','output','remote_tool'):
        if Path(c[key]).is_absolute() or '..' in Path(c[key]).parts: raise ValueError('项目相对路径无效: '+key)
    for key in ('udp_port','peer_port','web_port'):
        if not 1<=int(c[key])<=65535: raise ValueError('端口无效: '+key)
    return root

def preflight(c):
    root=validate(c)
    missing=[p for p in ('.venv/bin/python','main.py',c['scene']) if not (root/p).is_file()]
    addresses=ip_json('address','show','dev',c['interface'])
    addr=c['business_cidr'].split('/')[0];prefix=int(c['business_cidr'].split('/')[1])
    exact=any(a.get('local')==addr and a.get('prefixlen')==prefix for row in addresses['data'] for a in row.get('addr_info',[]))
    carrier=read_number(Path('/sys/class/net')/c['interface']/'carrier')
    errors=[]
    if missing: errors.append('缺少项目文件: '+', '.join(missing))
    if not addresses.get('ok'): errors.append('业务接口不存在或无法读取，请修改集中配置')
    if not exact: errors.append('eth0缺少业务地址 '+c['business_cidr'])
    if carrier!=1: errors.append('物理链路未建立或状态未知')
    return dict(directory=str(root),missing=missing,addresses=addresses,business_address_present=exact,
                carrier=carrier,errors=errors,processes=processes(c),ports=owners(c))

def start(c,state):
    check=preflight(c)
    fatal=check['missing'] or not check['business_address_present'] or not check['addresses'].get('ok')
    if fatal: return dict(ok=False,message='；'.join(check['errors']),preflight=check,can_setup_address=not check['business_address_present'])
    candidates=check['processes']; ports=check['ports']
    if len(candidates)>1: return dict(ok=False,message='发现多份匹配服务，拒绝创建或任意停止',preflight=check)
    candidate=candidates[0] if candidates else None
    foreign=[row for row in ports if not candidate or row['pids']!=[candidate['pid']]]
    if foreign: return dict(ok=False,message='8080或50000（配置端口）被不相关/身份不可确认进程占用',conflicts=foreign,preflight=check)
    adopted=bool(candidate)
    if not candidate:
        log=(state/'service.console.log').open('ab')
        child=subprocess.Popen(command(c),cwd=c['remote_dir'],stdin=subprocess.DEVNULL,stdout=log,stderr=log,
                               start_new_session=True,close_fds=True)
        log.close()
        deadline=time.monotonic()+float(c.get('startup_timeout_seconds',35))
        while time.monotonic()<deadline:
            if child.poll() is not None:return dict(ok=False,message='服务启动后退出，请查看operator_v1/state/service.console.log')
            candidate=proc(child.pid)
            current_ports=owners(c)
            if matches(candidate,c) and len(current_ports)>=2 and all(row['pids']==[child.pid] for row in current_ports):break
            time.sleep(.15)
        else:
            if matches(proc(child.pid),c): child.send_signal(signal.SIGINT)
            return dict(ok=False,message='等待服务端口超时，已请求本次进程正常停止')
    (state/'service.json').write_text(json.dumps(dict(identity=candidate,command=command(c),adopted=adopted),indent=2))
    deadline=time.monotonic()+5
    while time.monotonic()<deadline:
        s=status(c)
        if s.get('ok') and s['data'].get('mode')=='LIVE_FRONT' and isinstance(s['data'].get('link'),dict):
            return dict(ok=True,message='已复用本项目服务' if adopted else '已启动本项目服务',process=candidate,status=s,
                        lifetime='关闭电脑入口窗口后远端继续运行；请使用停止前摄服务')
        time.sleep(.15)
    return dict(ok=False,message='进程存在但LIVE_FRONT状态接口未就绪，请诊断；PID已记录',process=candidate,status=s)

def stop(c,state):
    record=state/'service.json'
    if not record.exists():
        found=processes(c)
        return dict(ok=not found,message='已有本项目服务但没有本工具PID记录；先启动入口核对并接管后再停止' if found else '已经停止',processes=found)
    saved=json.loads(record.read_text())['identity']; current=proc(saved['pid'])
    if not current:return dict(ok=True,message='已经停止')
    if not identity(saved,current) or not matches(current,c):return dict(ok=False,message='PID身份或参数已变化，拒绝停止',saved=saved,current=current)
    os.kill(current['pid'],signal.SIGINT)
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        if not identity(saved,proc(current['pid'])):
            return dict(ok=True,message='前摄服务已正常停止',ports=owners(c))
        time.sleep(.1)
    return dict(ok=False,message='正常退出超时，未强制杀进程，请查看日志',process=proc(current['pid']))

def diagnose(c):
    check=preflight(c)
    a=sample(c);time.sleep(min(10,max(2,float(c.get('diagnostic_seconds',4)))));b=sample(c)
    routes=ip_json('route','get',c['fpga_ip']);neigh=ip_json('neigh','show','to',c['fpga_ip'],'dev',c['interface'])
    da=a['status'].get('data',{});db=b['status'].get('data',{})
    la=da.get('link') or {};lb=db.get('link') or {}
    confirmed=len(check['processes'])==1 and len(check.get('ports',[]))>=2 and all(
        row['pids']==[check['processes'][0]['pid']] for row in check['ports'])
    same=bool(confirmed and la.get('session') and la.get('session')==lb.get('session'))
    # collections.Counter omits counters that have never incremented: missing means zero
    # only when both samples are readable, same LIVE session, and this implementation is used.
    counters=('heartbeat_tx','rx_packets','heartbeat_or_welcome','front_fragments','complete_frames','bad_packets','wrong_peer','wrong_session','send_errors','receive_errors')
    ld={k:delta(la.get(k,0),lb.get(k,0)) if same else None for k in counters}
    nd={k:delta(a['counters'][k],b['counters'][k]) for k in a['counters']}
    conclusions=[]
    if not check['processes']:conclusions.append('服务未运行或参数与集中配置不匹配')
    elif not confirmed:conclusions.append('服务与端口占用身份不能同时确认；HTTP统计不作为本项目通信通过证据')
    if not check['business_address_present']:conclusions.append('eth0缺少业务地址')
    if check['carrier']==0:conclusions.append('物理链路未建立')
    elif check['carrier'] is None:conclusions.append('物理链路未知')
    if not routes['data'] or routes['data'][0].get('dev')!=c['interface']:conclusions.append('到FPGA的路由异常或未知')
    states=[s for n in neigh['data'] for s in n.get('state',[])]
    if 'PERMANENT' in states:conclusions.append('ARP为PERMANENT静态条目，不证明FPGA已回应ARP')
    elif not states or any(s in states for s in ('INCOMPLETE','FAILED')):conclusions.append('ARP未解析或没有邻居记录')
    else:conclusions.append('ARP为动态邻居：'+','.join(states)+'；缓存记录不单独证明当前通信')
    for neighbor in neigh['data']:
        mac=neighbor.get('lladdr')
        if mac and mac.lower()!=c['fpga_mac'].lower():conclusions.append('邻居MAC与集中配置不一致：实际'+mac+'，配置'+c['fpga_mac'])
    if nd['tx_packets'] is not None and nd['tx_packets']>0 and nd['rx_packets']==0:
        conclusions.append('采样窗主机发送增加，但无接收；不能据此定位FPGA具体模块')
    if same and ld['heartbeat_tx'] and nd['tx_packets']==0:
        conclusions.append('程序心跳发送轮次增加，但网卡TX未增加；请结合链路状态，不能据此确认已发到网线上')
    if same and ld['send_errors']:
        conclusions.append('程序记录到发送系统错误，增量='+str(ld['send_errors']))
    if not b['status'].get('ok'):conclusions.append('状态接口不可读取')
    elif not same:conclusions.append('采样期间无有效同会话link统计，增量未知')
    else:
        if (nd['rx_packets'] or 0)>0 and ld['rx_packets']==0:conclusions.append('网卡已有接收，但没有有效同会话协议回包')
        if not lb.get('online'):conclusions.append('服务正常，FPGA尚未连接（online=false）')
        if lb.get('online') and ld['front_fragments']==0:conclusions.append('会话在线但采样窗没有视频分片')
        if ld['front_fragments'] and not ld['complete_frames']:conclusions.append('有分片但采样窗无完整帧')
        if ld['complete_frames']:
            pd=delta(da.get('processed'),db.get('processed'))
            if not pd:conclusions.append('完整帧持续到达，但处理没有更新')
            elif not b['jpeg'].get('ok') or a['jpeg'].get('sequence')==b['jpeg'].get('sequence'):
                conclusions.append('完整帧持续到达、处理更新，但预览JPEG未更新或不可读取')
            else:conclusions.append('已有完整前摄帧持续到达、处理及预览JPEG更新，通信正常；浏览器实际解码仍需现场观察')
        elif lb.get('complete_frames',0)>0:conclusions.append('历史收到完整帧，但当前采样窗没有新完整帧')
    root=Path(c['remote_dir'])
    try: version=json.loads((root/'manifest.json').read_text())['version']
    except (OSError,ValueError,KeyError):version='未知'
    if a['carrier']!=b['carrier']:conclusions.append('采样期间物理链路状态变化，请结合两个样本核对')
    speed=read_number(Path('/sys/class/net')/c['interface']/'speed')
    if speed is not None and speed<=0:speed=None
    return dict(ok=True,tool_version=VERSION,directory=str(root),version=version,config=c,preflight=check,
        route=routes,neighbors=neigh,speed_mbps=speed,
        samples=[a,b],window_seconds=b['monotonic']-a['monotonic'],nic_delta=nd,link_delta=ld,
        counter_notes='缺失Counter字段在同一可读session内按0解释；跨session/不可读/计数回退的增量为null；heartbeat_tx为每轮HELLO+HEARTBEAT计数，不是精确发包数',
        conclusions=conclusions,preview_observation='浏览器是否收到新图不能由服务启动或累计帧数单独证明',
        sockets=run(['ss','-ltnup']),optional_tools={k:run(['which',k]) for k in ('ethtool','tcpdump')},
        optional_note='基础诊断只读，不运行ping或第二份UDP客户端，不添加静态ARP；未执行sudo抓包，未安装工具')

def setup_address(c):
    validate(c)
    ssh=ip_json('route','get',os.environ.get('SSH_CONNECTION','').split(' ')[0])
    if not ssh.get('data') or ssh['data'][0].get('dev')==c['interface']:
        raise ValueError('无法确认SSH管理路由与业务接口分离，拒绝修改')
    if not ip_json('address','show','dev',c['interface']).get('ok'):raise ValueError('接口不存在，请修改配置')
    subprocess.run(['sudo','ip','link','set','dev',c['interface'],'up'],check=True)
    if not preflight(c)['business_address_present']:
        subprocess.run(['sudo','ip','address','add',c['business_cidr'],'dev',c['interface']],check=True)
    return dict(ok=True,message='仅临时启用eth0并补充业务地址；未删除其他地址或修改默认路由/DNS/持久配置')

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['preflight','start','stop','diagnose','setup-address'])
    p.add_argument('--config',required=True);a=p.parse_args()
    try:
        c=json.loads(base64.b64decode(a.config));root=validate(c)
        if a.action=='diagnose':result=diagnose(c)
        elif a.action=='preflight':result=dict(ok=True,**preflight(c))
        else:
            state=root/'operator_v1/state';state.mkdir(parents=True,exist_ok=True)
            with (state/'operation.lock').open('a') as lock:
                fcntl.flock(lock,fcntl.LOCK_EX)
                result=setup_address(c) if a.action=='setup-address' else globals()[a.action](c,state)
        print(json.dumps(result,ensure_ascii=False))
    except Exception as e: print(json.dumps(dict(ok=False,message=str(e)),ensure_ascii=False))

if __name__=='__main__':main()
