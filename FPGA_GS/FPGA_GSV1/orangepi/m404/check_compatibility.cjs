const fs=require('fs'),path=require('path'),assert=require('assert');
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{const b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});try{
 const p=await b.newPage({viewport:{width:1280,height:1100}});await p.goto('http://127.0.0.1:18080/');
 const status=async()=>{const r=await p.request.get('http://127.0.0.1:18080/status.json');return JSON.parse(await r.text());};
 const control=async data=>{const s=await status();const r=await p.request.post('http://127.0.0.1:18080/demo/control',{headers:{'X-M4-Control-Token':s.control_token},data});assert((await r.json()).ok);};
 async function until(predicate){const end=Date.now()+20000;let s;do{s=await status();if(predicate(s))return s;await p.waitForTimeout(100);}while(Date.now()<end);throw Error('wait failed '+JSON.stringify(s));}
 const rows=[];
 for(const video of ['SC_BT.mp4','SC_BT2.mp4','SC_YJ.mp4','SC_YJ2.mp4']){await control({video,seek:0,width:640,playing:true});const immediate=await status();assert(!immediate.perception||immediate.detection?.epoch===immediate.epoch);rows.push({video,immediateJsonValid:true});await until(s=>s.detection?.epoch===s.epoch&&s.detection.count>0);}
 await control({playing:false});await p.waitForTimeout(5600);assert.equal((await status()).detection.detection_fps,0);
 await control({video:'SC_YJ.mp4',seek:70,width:640,mode:'intersection',lane:'straight',playing:true});
 const red=await until(s=>s.video==='SC_YJ.mp4'&&s.perception?.signal.state==='RED'&&s.age_ms<500&&s.position>=70);
 await control({intent:'straight',force:true});const alarm=await until(s=>!!s.driving.alarm);await p.waitForTimeout(180);
 await p.screenshot({path:path.join(__dirname,'evidence/final/old_red_warning_compatible.png'),fullPage:true});
 await control({intent:'stop'});const stopped=await status();assert.equal(stopped.driving.alarm,null);
 await control({video:'SC_BT.mp4',seek:54,width:640,playing:true});await until(s=>s.video==='SC_BT.mp4'&&s.frame_id>0&&s.detection?.epoch===s.epoch);
 const result={passed:true,transitions:rows,pausedDetectionFps:0,redWarning:alarm.driving.alarm,stopClearsWarning:true,newEpochIsolation:true};
 fs.writeFileSync(path.join(__dirname,'evidence/final/compatibility.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
