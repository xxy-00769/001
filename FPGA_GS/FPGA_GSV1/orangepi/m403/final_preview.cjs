const fs=require('fs'),path=require('path'),assert=require('assert');
const {execFileSync}=require('child_process');
const cfg=JSON.parse(fs.readFileSync(path.join(__dirname,'../oneclick/config.json'),'utf8'));
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
 const b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 try{
 const p=await b.newPage({viewport:{width:1280,height:1100}});await p.goto('http://127.0.0.1:18080/');
 await p.evaluate(()=>{window.__statusRetries=0;window.readStatus=async()=>{for(let n=0;n<4;n++){try{let r=await fetch('/status.json');if(!r.ok)throw Error('HTTP '+r.status);return await r.json();}catch(e){window.__statusRetries++;if(n===3)throw e;await new Promise(r=>setTimeout(r,200));}}};});
 await p.waitForFunction(()=>window.m403Metrics?.().newFrames>10);
 await p.evaluate(()=>{window.__chunks=[];window.__rec=new MediaRecorder(document.querySelector('#video').captureStream(15),{mimeType:'video/webm;codecs=vp8'});window.__rec.ondataavailable=e=>{if(e.data.size)window.__chunks.push(e.data)};window.__rec.start(1000);});
 await p.getByRole('button',{name:'日间虚线 32秒',exact:true}).click();await p.getByRole('button',{name:'请求右',exact:true}).click();
 let hit=null,shot=null,end=Date.now()+20000;
 const token=(await(await p.request.get('http://127.0.0.1:18080/status.json')).json()).control_token;
 while(Date.now()<end){try{let r=await p.request.post('http://127.0.0.1:18080/demo/control',{headers:{'X-M4-Control-Token':token},data:{snapshot:true,snapshot_expected:{right:'DASHED',motion:'CHANGE_RIGHT'}},timeout:3000});shot=await r.json();if(shot.ok){hit={video:shot.status.video,time:shot.status.position,frame:shot.status.frame_id};break;}}catch(e){shot={ok:false,error:String(e)};}await p.waitForTimeout(70);} assert(shot.ok,JSON.stringify(shot));const out=path.join(__dirname,'evidence/browser');fs.writeFileSync(path.join(out,'day_dashed_allow.json'),JSON.stringify(shot.status,null,2));
 for(let suffix of ['_raw.jpg','_overlay.jpg'])execFileSync('scp.exe',['-P',String(cfg.ssh_port),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',`${cfg.ssh_user}@${cfg.ssh_host}:${cfg.remote_dir}/m403/evidence/runtime/${shot.snapshot}${suffix}`,path.join(out,'day_dashed_allow'+suffix)]);
 await p.getByRole('button',{name:'请求左',exact:true}).click();await p.waitForTimeout(600);await p.getByRole('button',{name:'强制跨左线',exact:true}).click();await p.waitForTimeout(1700);await p.getByRole('button',{name:'停车（优先）',exact:true}).click();await p.waitForTimeout(800);
 const recording=await p.evaluate(async()=>{await new Promise(r=>{window.__rec.onstop=r;window.__rec.stop()});let bytes=new Uint8Array(await new Blob(window.__chunks,{type:'video/webm'}).arrayBuffer()),s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);});fs.writeFileSync(path.join(out,'final_day_actual_operations.webm'),Buffer.from(recording,'base64'));
 await p.getByRole('button',{name:'夜间路口 70秒',exact:true}).click();await p.locator('#width').selectOption('640');
 for(let n=0;n<100;n++){let s=await p.evaluate(async()=>window.readStatus()),m=await p.evaluate(()=>window.m403Metrics());if(s.video==='SC_YJ.mp4'&&s.position>70&&s.position<76&&m.identity?.startsWith(s.epoch+':')&&m.newFrameFps>10)break;await p.waitForTimeout(100);}
 await p.evaluate(()=>{window.__frames=[];window.addEventListener('m403-frame',e=>window.__frames.push({...e.detail,ageUpperMs:window.m403Metrics().ageUpperMs}));});
 const start=await p.evaluate(async()=>({status:await window.readStatus(),metrics:window.m403Metrics(),time:performance.now()})),samples=[];
 const deadline=Date.now()+30000;
 while(Date.now()<deadline){samples.push(await p.evaluate(async()=>({status:await window.readStatus(),metrics:window.m403Metrics()})));await p.waitForTimeout(1000);}
 const finish=await p.evaluate(async()=>({status:await window.readStatus(),metrics:window.m403Metrics(),frames:window.__frames,time:performance.now(),statusRetries:window.__statusRetries}));
 const sec=(finish.time-start.time)/1000,result={seconds:sec,processedFps:(finish.status.processed-start.status.processed)/sec,previewNewFps:(finish.metrics.newFrames-start.metrics.newFrames)/sec,positionDelta:finish.status.position-start.status.position,maxFrameAgeUpperMs:Math.max(...finish.frames.map(x=>x.ageUpperMs)),maxInflight:finish.metrics.maxInflight,statusRetries:finish.statusRetries,laneSceneButton:hit,samples,frames:finish.frames};
 for(const x of result.samples)delete x.status.control_token;
 result.targetNear15=result.previewNewFps>=14;assert(result.maxInflight===1);
 fs.writeFileSync(path.join(out,'final_30s_preview.json'),JSON.stringify(result,null,2));
 await p.getByRole('button',{name:'夜间路口 70秒',exact:true}).click();await p.waitForTimeout(1000);await p.screenshot({path:path.join(out,'final_page.png'),fullPage:true});console.log(JSON.stringify({...result,samples:result.samples.length,frames:result.frames.length}));
 }finally{await b.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
