const fs=require('fs'),path=require('path');const{chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const tag=process.argv[2]||'r2',out=path.join(__dirname,'evidence',tag);fs.mkdirSync(out,{recursive:true});
(async()=>{let b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});try{let p=await b.newPage({viewport:{width:1150,height:1050}});await p.goto('http://127.0.0.1:18080/');
const st=()=>p.evaluate(async()=>await(await fetch('/status.json')).json());
const ctrl=x=>p.evaluate(async x=>{let s=await(await fetch('/status.json')).json();return await(await fetch('/demo/control',{method:'POST',headers:{'Content-Type':'application/json','X-M4-Control-Token':s.control_token},body:JSON.stringify(x)})).json()},x);
const cases=tag==='r1'?[['SC_BT.mp4',30,7],['SC_YJ2.mp4',48,7]]:[['SC_BT.mp4',30,10],['SC_BT2.mp4',11,7],['SC_YJ.mp4',128,7],['SC_YJ2.mp4',48,8],['SC_BT.mp4',55,6]];
let rows=[];
for(let [video,seek,seconds]of cases){await ctrl({video,seek,playing:true,width:640,mode:'lane',intent:'right'});let end=Date.now()+16000;while(Date.now()<end){let s=await st();if(s.video===video&&s.position>seek+.7&&s.perception?.road?.epoch===s.epoch)break;await p.waitForTimeout(100)}await p.waitForTimeout(800);
await p.evaluate(()=>{window.chunks=[];window.rec=new MediaRecorder(document.getElementById('video').captureStream(15),{mimeType:'video/webm;codecs=vp8',videoBitsPerSecond:1700000});window.rec.ondataavailable=e=>{if(e.data.size)window.chunks.push(e.data)};window.rec.start(200)});
let a=await st(),ma=await p.evaluate(()=>window.m403Metrics()),samples=[];
for(let i=0;i<seconds*2;i++){await p.waitForTimeout(500);let s=await st();samples.push(s)}
let z=await st(),mz=await p.evaluate(()=>window.m403Metrics()),dt=(z.host_monotonic_ms-a.host_monotonic_ms)/1000;
let data=await p.evaluate(async()=>{await new Promise(r=>{window.rec.onstop=r;window.rec.stop()});let bytes=new Uint8Array(await new Blob(window.chunks).arrayBuffer()),s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s)});
let name=video.slice(0,-4)+'_'+seek;fs.writeFileSync(path.join(out,name+'.webm'),Buffer.from(data,'base64'));await p.screenshot({path:path.join(out,name+'_page.png'),fullPage:true});
let snap=await ctrl({snapshot:true});fs.writeFileSync(path.join(out,name+'_snapshot.json'),JSON.stringify(snap,null,2));
rows.push({video,seek,release:z.release,seconds:dt,processingFps:(z.processed-a.processed)/dt,previewNewFps:(mz.newFrames-ma.newFrames)/dt,roadFps:(z.road.completed-a.road.completed)/dt,laneSemanticFps:z.road.semantic_update_fps,detectionFps:(z.detection.detection_runs-a.detection.detection_runs)/dt,maxInflight:mz.maxInflight,stage:z.stage_mean_ms,samples});fs.writeFileSync(path.join(out,'playback.json'),JSON.stringify(rows,null,2));console.log(name,rows.at(-1).previewNewFps,rows.at(-1).roadFps)}
}finally{await b.close()}})().catch(e=>{console.error(e);process.exitCode=1});
