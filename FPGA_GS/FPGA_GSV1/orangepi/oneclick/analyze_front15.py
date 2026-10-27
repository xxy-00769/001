"""Summarize a captured LIVE window; does not contact FPGA or run inference."""
import json
from pathlib import Path
import statistics
import sys

p=Path(sys.argv[1])
def load(name):return json.loads((p/name).read_text(encoding='utf-8-sig'))
w=load('window.json');b=load('browser_acceptance.json')
records=[json.loads(x) for x in (p/'events_after.jsonl').read_text(encoding='utf-8-sig').splitlines() if x.strip()]
obs=[x for x in records if x.get('type')=='observation' and w['first']['monotonic']<=x.get('received_monotonic',0)<=w['last']['monotonic']]
def stats(v):
    s=sorted(v)
    return dict(mean=statistics.mean(s),p50=s[len(s)//2],p95=s[min(len(s)-1,int(len(s)*.95))],max=max(s)) if s else None
frames=load('browser_frames.json');d=[x['decodedAtMs']-x['receivedMonotonicMs'] for x in frames]
metric=dict(request_fps=w['first']['status']['data']['link']['requested_front_fps'],seconds=w['window_seconds'],
    receive_fps=w['complete_fps'],complete_frames=w['link_delta']['complete_frames'],
    processed_frames=w['processed_delta'],processed_fps=w['processed_delta']/w['window_seconds'],
    browser_new_fps=b['new_frame_fps'],browser_unique_frames=b['decoded_unique_frames'],
    app_skip_delta=w['skipped_complete_frames_delta'],socket_drop_delta=w['service_socket_drop_delta_by_inode'],
    assembly_drop_delta=w['link_delta']['assembly_dropped'],crc_delta=w['nic_delta']['rx_crc_errors'],
    hardware_crc_delta=w['hardware_delta'].get('mmc_rx_crc_error'),
    complete_gap_ms=stats([(y['received_monotonic']-x['received_monotonic'])*1000 for x,y in zip(obs,obs[1:])]),
    inference_ms=stats([x['inference_ms'] for x in obs]),processing_ms=stats([x['stage_ms']['process_total'] for x in obs]),
    raw_jpeg_ms=stats([x['stage_ms']['raw_jpeg'] for x in obs]),overlay_jpeg_ms=stats([x['stage_ms']['overlay_jpeg'] for x in obs]),
    complete_to_processing_wait_ms=stats([x['complete_to_process_wait_ms'] for x in obs]),
    complete_to_result_age_ms=stats([x['frame_age_at_result_ms'] for x in obs]),
    max_sampled_complete_to_current_preview_age_ms=w['max_sampled_preview_age_ms'],
    browser_decode_gap_max_ms=b['max_decode_gap_ms'],
    browser_delay_change_last_vs_first_5s_ms=statistics.median(d[-70:])-statistics.median(d[:70]),
    right_camera_parallel='not running, user confirmed; dual-port parallel not tested',
    boundary_note='Counter snapshots and per-frame records can differ by one in-flight frame.')
assert metric['receive_fps']>=14 and metric['browser_new_fps']>=14
assert metric['socket_drop_delta'] and all(v==0 for v in metric['socket_drop_delta'].values())
assert metric['assembly_drop_delta']==0 and metric['crc_delta']==0 and metric['hardware_crc_delta']==0
assert b['max_in_flight']==1 and b['duplicate_responses']==0 and not b['errors']
assert metric['request_fps']==15 and w['same_session'] and w['same_process']
(p/'acceptance_summary.json').write_text(json.dumps(metric,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(metric,ensure_ascii=False,indent=2))
