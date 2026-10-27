const fs=require('fs'),path=require('path');
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{const b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});const p=await b.newPage({viewport:{width:1280,height:1100}}),rows=[],out=path.join(__dirname,'evidence/browser');
try{await p.goto('http://127.0.0.1:18080/');await p.waitForFunction(()=>window.m403Metrics?.().newFrames>10);
for(let file of (process.argv[2]?[process.argv[2]]:['SC_BT.mp4','SC_BT2.mp4','SC_YJ.mp4','SC_YJ2.mp4']))for(let width of (process.argv[3]?[Number(process.argv[3])]:[640,1280])){
 await p.locator('#file').selectOption(file);await p.locator('#width').selectOption(String(width));
 let current,metrics,end=Date.now()+30000;
 do{current=await(await p.request.get('http://127.0.0.1:18080/status.json')).json();metrics=await p.evaluate(()=>window.m403Metrics());if(current.video===file&&metrics.identity?.startsWith(current.epoch+':')&&current.processed_fps>5&&await p.locator('#video').evaluate((c,w)=>c.width===w,width))break;await p.waitForTimeout(100);}while(Date.now()<end);
 const samples=[],t=Date.now(),s0=current,m0=metrics;await p.evaluate(()=>{window.__bench=[];window.__benchHandler=e=>window.__bench.push({...e.detail,ageUpperMs:window.m403Metrics().ageUpperMs});window.addEventListener('m403-frame',window.__benchHandler);});
 while(Date.now()-t<10000){let s=await(await p.request.get('http://127.0.0.1:18080/status.json')).json();delete s.control_token;samples.push({server:s,browser:await p.evaluate(()=>window.m403Metrics())});await p.waitForTimeout(1000);}
 const s1=await(await p.request.get('http://127.0.0.1:18080/status.json')).json(),m1=await p.evaluate(()=>window.m403Metrics()),frames=await p.evaluate(()=>{window.removeEventListener('m403-frame',window.__benchHandler);return window.__bench;});
 const seconds=(s1.host_monotonic_ms-s0.host_monotonic_ms)/1000,row={file,width,seconds,processedFps:(s1.processed-s0.processed)/seconds,previewNewFps:(m1.newFrames-m0.newFrames)/seconds,positionDelta:s1.position-s0.position,maxFrameAgeUpperMs:Math.max(...frames.map(x=>x.ageUpperMs)),maxInflight:m1.maxInflight,samples,frames};rows.push(row);fs.writeFileSync(path.join(out,process.argv[2]?'performance_recheck_YJ2_1280.json':'performance_final.json'),JSON.stringify(rows,null,2));await p.screenshot({path:path.join(out,'final_'+file+'_'+width+'.png'),fullPage:true});console.log(JSON.stringify({...row,samples:samples.length,frames:frames.length}));
}
await p.getByRole('button',{name:'夜间路口 70秒',exact:true}).click();
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
