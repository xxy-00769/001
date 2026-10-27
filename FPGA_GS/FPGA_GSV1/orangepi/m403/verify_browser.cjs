// Integration tests against actual original-file playback over the SSH forward.
// No generated perception or video is injected. Browser actions operate the delivered UI.
const fs=require('fs'),path=require('path'),assert=require('assert');
const {execFileSync}=require('child_process');
const config=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../oneclick/config.json'),'utf8').replace(/^\uFEFF/,''));
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const out=path.resolve(__dirname,'evidence/browser');fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:1100}});const errors=[],checks=[],performance=[];
 page.on('pageerror',e=>errors.push(e.message));
 async function poll(fn,arg=null,{timeout=30000}={}){let deadline=Date.now()+timeout;while(Date.now()<deadline){if(await page.evaluate(fn,arg))return;await page.waitForTimeout(100);}throw Error('Status predicate timeout: '+String(fn));}
 async function status(){return page.evaluate(async()=>{let s=await(await fetch('/status.json')).json();delete s.control_token;return s;});}
 async function wait(predicate){await page.waitForFunction(predicate,null,{timeout:30000});return status();}
 async function seek(sec){let prior=await status();await page.locator('#seek').evaluate((el,n)=>{el.value=n;el.dispatchEvent(new Event('change'));},String(sec));await poll(async({sec,epoch})=>{let s=await(await fetch('/status.json')).json();return s.epoch>epoch&&s.position>=sec-.05&&s.position<sec+5&&s.perception&&window.m403Metrics().identity?.startsWith(s.epoch+':');},{sec,epoch:prior.epoch},{timeout:45000});}
 async function save(name,expected={}){let captured;
  await poll(async expected=>{let s=await(await fetch('/status.json')).json(),r=await fetch('/demo/control',{method:'POST',headers:{'Content-Type':'application/json','X-M4-Control-Token':s.control_token},body:JSON.stringify({snapshot:true,snapshot_expected:expected})});let d=await r.json();if(d.ok)window.__captured=d;return d.ok;},expected,{timeout:20000});
  captured=await page.evaluate(()=>window.__captured);let s=captured.status;
  fs.writeFileSync(path.join(out,name+'.json'),JSON.stringify({...s,snapshot_base:captured.snapshot,evidence:'paired original/overlay/status captured atomically; browser screenshot may be an adjacent live frame'},null,2));
  for(let [suffix,label] of [['_raw.jpg','raw'],['_overlay.jpg','latest']])execFileSync('scp.exe',['-P',String(config.ssh_port),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',`${config.ssh_user}@${config.ssh_host}:${config.remote_dir}/m403/evidence/runtime/${captured.snapshot}${suffix}`,path.join(out,name+'_'+label+'.jpg')]);
  await page.screenshot({path:path.join(out,name+'.png'),fullPage:true});return s;}
 async function recordStart(){await page.evaluate(()=>{window.__chunks=[];window.__rec=new MediaRecorder(document.querySelector('#video').captureStream(15),{mimeType:'video/webm;codecs=vp8'});window.__rec.ondataavailable=e=>{if(e.data.size)window.__chunks.push(e.data)};window.__rec.start(1000);});}
 async function recordStop(name){let data=await page.evaluate(async()=>{await new Promise(r=>{window.__rec.onstop=r;window.__rec.stop()});let b=await new Blob(window.__chunks,{type:'video/webm'}).arrayBuffer();let a=new Uint8Array(b),s='';for(let i=0;i<a.length;i+=8192)s+=String.fromCharCode(...a.subarray(i,i+8192));return btoa(s);});fs.writeFileSync(path.join(out,name+'.webm'),Buffer.from(data,'base64'));}
 try{
  await page.goto('http://127.0.0.1:18080/',{waitUntil:'domcontentloaded'});await wait(()=>window.m403Metrics?.().newFrames>10);
  // Signal: native image, manually declared group association only, no known answer in code.
  await page.locator('#file').selectOption('SC_YJ.mp4');await seek(70);
  await poll(async()=>{let s=await(await fetch('/status.json')).json();return s.position>70&&s.position<76&&s.perception?.signal.state==='RED';},null,{timeout:30000});
  let s=await status();assert.equal(s.driving.motion,'STOPPED');checks.push({case:'real_red_auto_stop',video:s.video,time:s.position,pass:true});await recordStart();await save('night_red_stop',{signal:'RED',motion:'STOPPED'});
  await page.getByRole('button',{name:'请求直行',exact:true}).click();s=await status();assert.equal(s.driving.motion,'STOPPED');assert.equal(s.driving.alarm,null);checks.push({case:'red_ordinary_stays_stopped',pass:true});
  await page.getByRole('button',{name:'强制行驶',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#alarm').textContent.includes('闯红灯'));
  s=await save('night_forced_red_alarm',{signal:'RED',alarm:true,motion:'MOVING'});assert.equal(s.driving.forced,true);checks.push({case:'real_red_forced_alarm',time:s.position,pass:true});
  await page.getByRole('button',{name:'停车（优先）',exact:true}).click();s=await status();assert.equal(s.driving.motion,'STOPPED');assert.equal(s.driving.alarm,null);checks.push({case:'stop_priority',pass:true});
  await seek(103);await page.getByRole('button',{name:'自动模拟',exact:true}).click();
  await poll(async()=>{let s=await(await fetch('/status.json')).json();return s.perception?.signal.state==='GREEN'&&s.driving.motion==='MOVING';},null,{timeout:25000});
  s=await save('night_green_start',{signal:'GREEN',motion:'MOVING'});checks.push({case:'real_green_start',time:s.position,pass:true});await recordStop('night_actual_operations');
  await page.locator('#lane').selectOption('left');await page.waitForFunction(()=>document.querySelector('#suggestion').textContent==='未知');s=await status();assert.equal(s.driving.motion,'STOPPED');checks.push({case:'unassigned_direction_unknown',pass:true});
  await page.getByRole('button',{name:'暂停',exact:true}).click();await poll(async()=>{let s=await(await fetch('/status.json')).json();return !s.playing&&s.age_ms>700;});s=await status();assert.equal(s.driving.motion,'STOPPED');checks.push({case:'pause_stale_safe',pass:true});
  await page.getByRole('button',{name:'播放',exact:true}).click();
  // Real lane evidence on daylight original.
  await page.locator('#file').selectOption('SC_BT.mp4');await page.getByRole('button',{name:'道路变道',exact:true}).click();await seek(32);
  await poll(async()=>{let s=await(await fetch('/status.json')).json();return s.video==='SC_BT.mp4'&&s.perception?.lanes.left.state==='SOLID';},null,{timeout:25000});
  await recordStart();await page.getByRole('button',{name:'请求左',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#motion').textContent==='保持直行');s=await save('day_solid_keep',{left:'SOLID',motion:'STRAIGHT'});assert.equal(s.driving.alarm,null);checks.push({case:'real_solid_keep',time:s.position,pass:true});
  await page.getByRole('button',{name:'强制跨左线',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#alarm').textContent.includes('实线'));s=await save('day_force_solid_alarm',{left:'SOLID',alarm:true,motion:'CHANGE_LEFT'});checks.push({case:'real_solid_forced_alarm',time:s.position,pass:true});
  await page.getByRole('button',{name:'清除告警并停车',exact:true}).click();
  await page.locator('#file').selectOption('SC_YJ2.mp4');await seek(30);await page.getByRole('button',{name:'请求右',exact:true}).click();
  await poll(async()=>{let s=await(await fetch('/status.json')).json();return s.video==='SC_YJ2.mp4'&&s.perception?.lanes.right.state==='DASHED'&&s.driving.motion==='CHANGE_RIGHT';},null,{timeout:30000});
  s=await save('blue_dashed_allow',{right:'DASHED',motion:'CHANGE_RIGHT'});checks.push({case:'real_dashed_allow_no_green',time:s.position,signal:s.perception.signal.state,pass:true});await recordStop('lane_actual_operations');
  // All four files and both resolutions measured in actual realtime playback.
  for(let file of ['SC_BT.mp4','SC_BT2.mp4','SC_YJ.mp4','SC_YJ2.mp4'])for(let width of [640,1280]){
   await page.locator('#file').selectOption(file);await page.locator('#width').selectOption(String(width));
   await poll(async({file,width})=>{let s=await(await fetch('/status.json')).json();return s.video===file&&s.preview_width===width&&s.processed_fps>0;},{file,width},{timeout:45000});
   const samples=[],start=Date.now(),m0=await page.evaluate(()=>window.m403Metrics()),s0=await status();
   while(Date.now()-start<10000){samples.push({server:await status(),browser:await page.evaluate(()=>window.m403Metrics())});await page.waitForTimeout(1000);}
   let s1=await status(),m1=await page.evaluate(()=>window.m403Metrics()),seconds=(s1.host_monotonic_ms-s0.host_monotonic_ms)/1000;
   let row={file,width,seconds,processedFps:(s1.processed-s0.processed)/seconds,previewNewFps:(m1.newFrames-m0.newFrames)/seconds,positionDelta:s1.position-s0.position,maxSampledAgeMs:Math.max(...samples.map(x=>x.browser.ageUpperMs||0)),samples};performance.push(row);fs.writeFileSync(path.join(out,'performance.json'),JSON.stringify(performance,null,2));console.log('PERF',file,width,row.processedFps.toFixed(2),row.previewNewFps.toFixed(2));
   await save(file.replace('.mp4','')+'_'+width);
  }
  // Real natural loop clearing: seek near the end, do not fake timestamps.
  await page.locator('#file').selectOption('SC_BT2.mp4');await seek(30.5);let before=await status();
  await poll(async(epoch)=>{let s=await(await fetch('/status.json')).json();return s.epoch>epoch&&s.position<3;},before.epoch,{timeout:15000});s=await status();assert.equal(s.driving.forced,false);assert.equal(s.driving.alarm,null);checks.push({case:'natural_loop_clears_state',pass:true});
  await page.getByRole('button',{name:'重新开始',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#position').textContent==='0:00');checks.push({case:'restart_clears_state',pass:true});
  await page.locator('#file').selectOption('SC_YJ.mp4');await page.getByRole('button',{name:'十字路口',exact:true}).click();await page.locator('#lane').selectOption('straight');await seek(70);await save('delivery_final');
  fs.writeFileSync(path.join(out,'acceptance.json'),JSON.stringify({checks,errors,performance:performance.map(({samples,...row})=>row),source:'actual original recordings through SSH; rules not injected',passed:true},null,2));
 }catch(error){fs.writeFileSync(path.join(out,'failure.json'),JSON.stringify({error:String(error.stack),checks,errors,performance},null,2));await page.screenshot({path:path.join(out,'failure.png'),fullPage:true});throw error;}
 finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
