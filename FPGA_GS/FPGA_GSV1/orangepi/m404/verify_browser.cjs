const fs=require('fs'),path=require('path'),assert=require('assert');
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const out=path.join(__dirname,'evidence/browser');fs.mkdirSync(out,{recursive:true});
(async()=>{const b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
try{const p=await b.newPage({viewport:{width:1280,height:1100}});await p.goto('http://127.0.0.1:18080/');await p.waitForFunction(()=>window.m403Metrics?.().newFrames>5);
const results=[];
async function status(){return await(await p.request.get('http://127.0.0.1:18080/status.json',{timeout:8000})).json();}
async function control(data){const s=await status();return (await p.request.post('http://127.0.0.1:18080/demo/control',{headers:{'X-M4-Control-Token':s.control_token},data})).json();}
async function startRecording(){await p.evaluate(()=>{window.__chunks=[];window.__rec=new MediaRecorder(document.querySelector('#video').captureStream(15),{mimeType:'video/webm;codecs=vp8'});window.__rec.ondataavailable=e=>{if(e.data.size)window.__chunks.push(e.data)};window.__rec.start(1000);});}
async function stopRecording(file){const data=await p.evaluate(async()=>{await new Promise(r=>{window.__rec.onstop=r;window.__rec.stop()});let bytes=new Uint8Array(await new Blob(window.__chunks,{type:'video/webm'}).arrayBuffer()),s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);});fs.writeFileSync(path.join(out,file),Buffer.from(data,'base64'));}
for(const [video,clipStart,shots]of [['SC_BT.mp4',51,[1,30,57]],['SC_BT2.mp4',8,[2,12,25]],['SC_YJ.mp4',93,[2,20,72,98,130,170]],['SC_YJ2.mp4',16,[2,20,50,74]]]){
 assert((await control({video,seek:0,playing:true,loop:true,width:640})).ok);
 await p.waitForFunction(v=>window.m403Metrics().identity?.startsWith(v+':'),(await status()).epoch);
 await p.evaluate(()=>{window.__frames=[];window.__handler=e=>window.__frames.push({...e.detail,ageMs:window.m403Metrics().ageUpperMs});window.addEventListener('m403-frame',window.__handler);});
 const initial=await status(),m0=await p.evaluate(()=>window.m403Metrics()),samples=[],captured=[],t0=Date.now();let recording=false,recorded=false,looped=false;
 while(Date.now()-t0<(initial.duration+15)*1000){
  const s=await status();delete s.control_token;const m=await p.evaluate(()=>window.m403Metrics());samples.push({server:s,browser:m});
  if(s.epoch!==initial.epoch){looped=true;break;}
  if(s.position>=clipStart&&!recording&&!recorded){await startRecording();recording=true;}
  if(recording&&s.position>=clipStart+6){await stopRecording(video+'_actual_preview.webm');recording=false;recorded=true;}
  for(const at of shots)if(s.position>=at&&!captured.includes(at)){
   const snapshot=await control({snapshot:true});assert(snapshot.ok);captured.push(at);fs.writeFileSync(path.join(out,video+'_'+at+'_snapshot.json'),JSON.stringify(snapshot,null,2));
   await p.screenshot({path:path.join(out,video+'_'+at+'_page.png'),fullPage:true});
  }
  await p.waitForTimeout(900);
 }
 if(recording)await stopRecording(video+'_actual_preview.webm');
 const frames=await p.evaluate(()=>{window.removeEventListener('m403-frame',window.__handler);return window.__frames;});
 const last=samples.filter(x=>x.server.epoch===initial.epoch).at(-1);const elapsed=(last.server.host_monotonic_ms-initial.host_monotonic_ms)/1000;
 const row={video,completePlayback:looped,seconds:elapsed,positionStart:initial.position,positionEnd:last.server.position,
  processingFps:(last.server.processed-initial.processed)/elapsed,previewNewFps:(last.browser.newFrames-m0.newFrames)/elapsed,
  detectionFpsMean:samples.reduce((a,x)=>a+(x.server.detection?.detection_fps||0),0)/samples.length,
  maxAgeMs:Math.max(...frames.map(x=>x.ageMs||0)),maxInflight:last.browser.maxInflight,stage:last.server.stage_mean_ms,samples,frames};
 assert(looped,'whole playback did not finish '+video);results.push(row);fs.writeFileSync(path.join(out,'full_playback.json'),JSON.stringify(results,null,2));console.log(JSON.stringify({...row,samples:row.samples.length,frames:row.frames.length}),null,2);
}
// 1280 performance only, same original timeline and same detector.
await control({video:'SC_BT.mp4',seek:53,width:1280,playing:true});await p.waitForTimeout(1800);
const a=await status(),ma=await p.evaluate(()=>window.m403Metrics());await p.waitForTimeout(7000);const z=await status(),mz=await p.evaluate(()=>window.m403Metrics());
const dt=(z.host_monotonic_ms-a.host_monotonic_ms)/1000;fs.writeFileSync(path.join(out,'performance_1280.json'),JSON.stringify({seconds:dt,processFps:(z.processed-a.processed)/dt,previewNewFps:(mz.newFrames-ma.newFrames)/dt,stage:z.stage_mean_ms},null,2));
await control({video:'SC_BT.mp4',seek:54,width:640,playing:true});
console.log('four full playbacks, preview clips and snapshots saved');
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
