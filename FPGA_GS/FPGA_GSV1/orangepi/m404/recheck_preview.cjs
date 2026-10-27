const fs=require('fs'),path=require('path'),assert=require('assert');
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const out=path.join(__dirname,'evidence/recheck');fs.mkdirSync(out,{recursive:true});
(async()=>{const b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
try{const p=await b.newPage({viewport:{width:1280,height:1100}});await p.goto('http://127.0.0.1:18080/');await p.waitForFunction(()=>window.m403Metrics?.().newFrames>5);
async function status(){return (await p.request.get('http://127.0.0.1:18080/status.json')).json();}
async function control(data){const s=await status();let r=await(await p.request.post('http://127.0.0.1:18080/demo/control',{headers:{'X-M4-Control-Token':s.control_token},data})).json();assert(r.ok,JSON.stringify(r));return r;}
const results=[];
for(const [video,seek,width]of [['SC_YJ2.mp4',16,640],['SC_BT.mp4',50,1280]]){
 await control({video,seek,width,playing:true});await p.waitForTimeout(1700);
 const a=await status(),ma=await p.evaluate(()=>window.m403Metrics());assert.equal(a.release,'M4-04-r1');
 await p.evaluate(()=>{window.__frames=[];window.__handler=e=>window.__frames.push({...e.detail,ageMs:window.m403Metrics().ageUpperMs});window.addEventListener('m403-frame',window.__handler);window.__chunks=[];window.__rec=new MediaRecorder(document.querySelector('#video').captureStream(15),{mimeType:'video/webm;codecs=vp8'});window.__rec.ondataavailable=e=>{if(e.data.size)window.__chunks.push(e.data)};window.__rec.start(1000);});
 const samples=[];const end=Date.now()+6500;let shot;
 while(Date.now()<end){const s=await status();assert(!s.error);assert.equal(s.detection.epoch,s.epoch);delete s.control_token;samples.push(s);await p.waitForTimeout(450);}
 const z=await status(),mz=await p.evaluate(()=>window.m403Metrics()),frames=await p.evaluate(()=>{window.removeEventListener('m403-frame',window.__handler);return window.__frames;});
 const data=await p.evaluate(async()=>{await new Promise(r=>{window.__rec.onstop=r;window.__rec.stop()});let bytes=new Uint8Array(await new Blob(window.__chunks,{type:'video/webm'}).arrayBuffer()),s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);});
 fs.writeFileSync(path.join(out,video+'_'+width+'.webm'),Buffer.from(data,'base64'));shot=await control({snapshot:true});fs.writeFileSync(path.join(out,video+'_'+width+'_snapshot.json'),JSON.stringify(shot,null,2));
 await p.screenshot({path:path.join(out,video+'_'+width+'_page.png'),fullPage:true});
 const dt=(z.host_monotonic_ms-a.host_monotonic_ms)/1000,row={video,width,seconds:dt,processFps:(z.processed-a.processed)/dt,previewNewFps:(mz.newFrames-ma.newFrames)/dt,detectionFps:(z.detection.detection_runs-a.detection.detection_runs)/dt,
 stage:z.stage_mean_ms,maxAgeMs:Math.max(...frames.map(x=>x.ageMs)),maxInflight:mz.maxInflight,positionDelta:z.position-a.position,samples};
 results.push(row);fs.writeFileSync(path.join(out,'performance.json'),JSON.stringify(results,null,2));console.log(JSON.stringify({...row,samples:samples.length}));
}
await control({playing:false});await p.waitForTimeout(5600);const paused=await status();assert.equal(paused.detection.detection_fps,0);const oldEpoch=paused.epoch;
await control({video:'SC_BT.mp4',seek:54,width:640,playing:true});await p.waitForTimeout(1400);let fresh=await status();assert(fresh.epoch>oldEpoch);assert.equal(fresh.detection.epoch,fresh.epoch);
// Existing red warning compatibility only; no new vehicle-driven braking rule.
await control({video:'SC_YJ.mp4',seek:70,width:640,mode:'intersection',lane:'straight',playing:true});
await p.waitForFunction(async()=>{let s=await(await fetch('/status.json')).json();return s.perception?.signal.state==='RED';});
await control({intent:'straight',force:true});await p.waitForTimeout(500);const alarm=await status();assert(alarm.driving.alarm);await p.screenshot({path:path.join(out,'old_red_warning_compatible.png'),fullPage:true});
await control({intent:'stop'});await control({video:'SC_BT.mp4',seek:54,width:640,playing:true});
fs.writeFileSync(path.join(out,'compatibility.json'),JSON.stringify({pausedDetectionFps:paused.detection.detection_fps,switchClearedEpoch:true,redWarning:alarm.driving.alarm,finalRelease:fresh.release},null,2));
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
