const fs=require('fs'),path=require('path');const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const out=path.join(__dirname,'evidence','playback');fs.mkdirSync(out,{recursive:true});
(async()=>{const b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});try{let p=await b.newPage({viewport:{width:1120,height:1000}});await p.goto('http://127.0.0.1:18080/');
const status=()=>p.evaluate(async()=>await(await fetch('/status.json')).json());
const ctrl=x=>p.evaluate(async x=>{const s=await(await fetch('/status.json')).json();return await(await fetch('/demo/control',{method:'POST',headers:{'Content-Type':'application/json','X-M4-Control-Token':s.control_token},body:JSON.stringify(x)})).json()},x);
const cases=process.argv[2]==='transition'?[['SC_YJ.mp4',100,12]]:process.argv[2]==='YJ2'?[['SC_YJ2.mp4',42,6]]:process.argv[2]==='holdout'?[['SC_YJ.mp4',72,7],['SC_YJ.mp4',110,6],['SC_BT.mp4',20,6],['SC_YJ2.mp4',35,6]]:[['SC_YJ.mp4',80,8],['SC_YJ.mp4',100,12],['SC_BT.mp4',7,8],['SC_BT2.mp4',9,6],['SC_YJ2.mp4',42,6]];
let rows=[];
for(const[video,seek,seconds]of cases){await ctrl({video,seek,playing:true,width:640,mode:'intersection',intent:'auto'});let end=Date.now()+20000;while(Date.now()<end){const s=await status();if(s.video===video&&s.position>seek+.7&&s.perception?.traffic?.epoch===s.epoch)break;await p.waitForTimeout(120)}await p.waitForTimeout(500);
await p.evaluate(()=>{window.chunks=[];window.rec=new MediaRecorder(document.getElementById('video').captureStream(15),{mimeType:'video/webm;codecs=vp8',videoBitsPerSecond:1700000});window.rec.ondataavailable=e=>{if(e.data.size)window.chunks.push(e.data)};window.rec.start(200)});
let a=await status(),ma=await p.evaluate(()=>m403Metrics()),samples=[];
for(let k=0;k<seconds*2;k++){await p.waitForTimeout(500);samples.push(await status())}
let z=await status(),mz=await p.evaluate(()=>m403Metrics()),dt=(z.host_monotonic_ms-a.host_monotonic_ms)/1000;
if(a.video!==video||samples.some(s=>s.video!==video||s.epoch!==a.epoch)||z.epoch!==a.epoch)throw Error('Playback changed during measurement; discard this window');
const data=await p.evaluate(async()=>{await new Promise(r=>{window.rec.onstop=r;window.rec.stop()});let bytes=new Uint8Array(await new Blob(window.chunks).arrayBuffer()),s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s)});
const name=video.slice(0,-4)+'_'+seek;fs.writeFileSync(path.join(out,name+'.webm'),Buffer.from(data,'base64'));await p.screenshot({path:path.join(out,name+'_page.png'),fullPage:true});
const snap=await ctrl({snapshot:true});fs.writeFileSync(path.join(out,name+'_snapshot.json'),JSON.stringify(snap,null,2));
let row={video,seek,seconds:dt,release:z.release,processingFps:(z.processed-a.processed)/dt,previewNewFps:(mz.newFrames-ma.newFrames)/dt,detectionFps:(z.detection.detection_runs-a.detection.detection_runs)/dt,roadFps:(z.road.completed-a.road.completed)/dt,trafficFps:(z.traffic.completed-a.traffic.completed)/dt,trafficSkipped:z.traffic.skipped_source_observations-a.traffic.skipped_source_observations,sourceSkipped:z.skipped_source_frames-a.skipped_source_frames,maxInflight:mz.maxInflight,stage:z.stage_mean_ms,samples};rows.push(row);fs.writeFileSync(path.join(out,(process.argv[2]||'dev')+'.json'),JSON.stringify(rows,null,2));console.log(name,JSON.stringify({...row,samples:undefined}));
}
}finally{await b.close()}})().catch(e=>{console.error(e);process.exitCode=1});
