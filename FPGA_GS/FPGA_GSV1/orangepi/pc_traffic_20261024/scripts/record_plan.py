from pathlib import Path
import json,hashlib
r=Path(__file__).resolve().parents[1];b=r.parent
ps=[b/'m406/research/yolov8s.pt',b/'m406/yolov8s640_fp16.rknn',b/'m404/models/yolov8n.onnx',b/'m406/research/tlony/tlony-yolov8n/weights/best.pt']
(r/'reports/weights_inventory.json').write_text(json.dumps([{'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in ps if p.exists()],indent=2),encoding='utf-8')
plan={'status':'not_frozen','original_four_videos':'regression_only_entire_recordings','ratio_target':{'train':0.7,'val':0.2,'holdout':0.1},'group_rule':'Connected components of same intersection, recording, continuous scene and near duplicates stay together','filename_prefix_is_only_candidate_group':True,'final_external_test':{'status':'not_collected','used_for_tuning':False,'used_for_int8_calibration':False},'training_allowed':False}
(r/'data/split_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
print('weights hashes and split plan written')
