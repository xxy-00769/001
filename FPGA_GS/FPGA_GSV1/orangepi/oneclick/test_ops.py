"""Operator-only checks; no inference, FPGA traffic, or network configuration."""
import copy
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch
import ops_manager as ops

class OperatorChecks(unittest.TestCase):
    def setUp(self):
        self.c=json.loads(Path(__file__).with_name('config.json').read_text(encoding='utf-8-sig'))

    def test_exact_existing_command_only(self):
        p=dict(pid=42,uid=ops.os.getuid(),start_ticks='123',cwd=self.c['remote_dir'],argv=ops.command(self.c))
        self.assertTrue(ops.matches(p,self.c))
        p['argv']=p['argv']+['--duration','1'];self.assertFalse(ops.matches(p,self.c))
        p['argv']=ops.command(self.c);p['cwd']='/tmp/other';self.assertFalse(ops.matches(p,self.c))

    def test_actual_foreign_tcp_and_udp_ports_refused(self):
        # Only temporary unused high ports, never 8080/50000 or another service.
        for kind,key in ((socket.SOCK_STREAM,'web_port'),(socket.SOCK_DGRAM,'udp_port')):
            with self.subTest(kind=kind),socket.socket(socket.AF_INET,kind) as s,tempfile.TemporaryDirectory() as state:
                s.bind(('127.0.0.1',0))
                if kind==socket.SOCK_STREAM:s.listen()
                c=copy.deepcopy(self.c);c[key]=s.getsockname()[1]
                result=ops.start(c,Path(state))
                self.assertFalse(result['ok']);self.assertIn('占用',result['message'])
                self.assertTrue(result['conflicts'])
                own=[row for row in result['conflicts'] if row['local_port']==s.getsockname()[1]]
                self.assertTrue(own)
                self.assertIn(ops.os.getpid(),own[0]['pids'])

    def test_changed_pid_identity_not_signalled(self):
        saved=dict(pid=123,start_ticks='1',cwd=self.c['remote_dir'],uid=ops.os.getuid(),argv=ops.command(self.c))
        changed=dict(saved,start_ticks='2')
        with tempfile.TemporaryDirectory() as state:
            Path(state,'service.json').write_text(json.dumps(dict(identity=saved)))
            with patch.object(ops,'proc',return_value=changed),patch.object(ops.os,'kill') as kill:
                result=ops.stop(self.c,Path(state))
            self.assertFalse(result['ok']);kill.assert_not_called()

    def test_readonly_diagnostic_counter_semantics(self):
        check=dict(processes=[dict(pid=42)],ports=[dict(pids=[42]),dict(pids=[42])],business_address_present=True,carrier=1)
        a=dict(monotonic=10,status=dict(ok=True,data=dict(processed=0,link=dict(session=7,online=False,heartbeat_tx=5))),
               counters=dict(rx_packets=0,tx_packets=10),jpeg=dict(ok=False),carrier=1,
               processes=[dict(pid=42,start_ticks='1',cwd=self.c['remote_dir'],argv=ops.command(self.c),uid=ops.os.getuid())],
               service_sockets=[dict(inode='7',service_owned=True,drops=3)],udp_global=dict(RcvbufErrors=30),
               receive_buffer=dict(kernel_max=8388608,socket_requested=4194304,socket_actual=8388608,kernel_ready=True,socket_ready=True))
        b=copy.deepcopy(a);b['monotonic']=14;b['counters']['tx_packets']=42;b['status']['data']['link']['heartbeat_tx']=21
        b['service_sockets'][0]['drops']=5;b['udp_global']['RcvbufErrors']=99
        with patch.object(ops,'preflight',return_value=check),patch.object(ops,'sample',side_effect=[a,b]),patch.object(ops.time,'sleep'),\
             patch.object(ops,'ip_json',side_effect=[dict(data=[dict(dev='eth0')]),dict(data=[dict(state=['PERMANENT'])])]),\
             patch.object(ops,'run',return_value=dict(ok=False)),patch.object(ops,'read_number',return_value=1000):
            report=ops.diagnose(self.c)
        self.assertEqual(report['link_delta']['complete_frames'],0)
        self.assertEqual(report['nic_delta']['tx_packets'],32)
        self.assertIn('主机发送增加，但无接收','；'.join(report['conclusions']))
        self.assertIn('静态条目','；'.join(report['conclusions']))
        self.assertEqual(report['service_socket_drop_delta_by_inode'],{'7':2})
        self.assertEqual(report['udp_global_delta']['RcvbufErrors'],69)

    def test_kernel_change_does_not_resize_existing_socket(self):
        s=dict(data=dict(link=dict(socket_receive_buffer_bytes=425984)))
        with patch.object(ops,'read_number',return_value=8388608):r=ops.buffer_check(self.c,s)
        self.assertTrue(r['kernel_ready']);self.assertFalse(r['socket_ready'])

    def test_insufficient_kernel_limit_never_starts_child(self):
        check=dict(missing=[],business_address_present=True,addresses=dict(ok=True),route_ok=True,
                   receive_buffer=dict(kernel_ready=False),errors=['接收缓冲不足'])
        with tempfile.TemporaryDirectory() as state,patch.object(ops,'preflight',return_value=check),patch.object(ops.subprocess,'Popen') as launch:
            self.assertFalse(ops.start(self.c,Path(state))['ok']);launch.assert_not_called()

if __name__=='__main__':unittest.main(verbosity=2)
