// Observe real FPGA restart and KEY through existing SSH. No network/control injection.
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path');
const out=path.resolve(process.argv[2]);
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:1000}}),samples=[],errors=[],frames=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{window.__frames=[];addEventListener('m401-preview-frame',e=>{window.__frames.push(e.detail);if(window.__frames.length>150)window.__frames.shift();});});
 let lastState=null,baseEpoch,baseline,resetSample,recovered,keySample;
 try{
  await page.goto('http://127.0.0.1:18080/',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.m401PreviewMetrics?.().newFramesTotal>=15,null,{timeout:20000});
  const deadline=Date.now()+300000;
  while(Date.now()<deadline){
   const started=Date.now();
   const sample=await page.evaluate(async()=>{
    const status=await(await fetch('/status.json?t=reconnect-observe',{cache:'no-store'})).json();delete status.control_token;
    const frames=window.__frames.splice(0);
    return {status,frames,metrics:window.m401PreviewMetrics(),imageHidden:document.querySelector('#image').hidden,
     text:document.querySelector('#connection-state').textContent,eventText:document.querySelector('#event-identity').textContent,
     browserAtMs:performance.now(),wallTime:new Date().toISOString()};
   });
   frames.push(...sample.frames);delete sample.frames;
   const l=sample.status.link;
   if(baseEpoch===undefined){baseEpoch=l.session_epoch;baseline=sample;fs.writeFileSync(path.join(out,'browser_ready.json'),JSON.stringify({ready:true,epoch:baseEpoch,session:l.session}));console.log('READY: live browser observing; keep this service running');}
   samples.push(sample);
   if(l.session_epoch>baseEpoch&&!resetSample)resetSample=sample;
   if(resetSample&&l.connection_state==='STREAMING'&&!recovered)recovered=sample;
   if(recovered&&!keySample&&l.feedback.recent_events.some(e=>e.result_ack?.accepted))keySample=sample;
   const state=l.session_epoch+':'+l.connection_state;
   if(state!==lastState){lastState=state;await page.screenshot({path:path.join(out,'state_'+state.replace(':','_')+'.png'),fullPage:true});console.log(state);}
   fs.appendFileSync(path.join(out,'browser_samples.jsonl'),JSON.stringify(sample)+'\n');
   if(keySample&&Date.now()-Date.parse(keySample.wallTime)>=3000)break;
   await page.waitForTimeout(Math.max(0,500-(Date.now()-started)));
  }
  await page.screenshot({path:path.join(out,'reconnect_final.png'),fullPage:true});
  const summary={baseline,resetSample,recovered,keySample,errors,samples:samples.length,
    observed_real_restart:!!resetSample,received_new_frames_after_restart:!!recovered,real_result_ack_after_restart:!!keySample,
    note:'Read-only actual browser/HTTP observation through SSH. No synthetic EVENT, frame, ACK, FPGA modification, or service restart.'};
  fs.writeFileSync(path.join(out,'browser_frames.json'),JSON.stringify(frames));
  fs.writeFileSync(path.join(out,'browser_reconnect.json'),JSON.stringify(summary,null,2));
  console.log(JSON.stringify({observed_real_restart:!!resetSample,recovered:!!recovered,key_ack:!!keySample,errors}));
 }finally{await browser.close();}
})().catch(e=>{fs.writeFileSync(path.join(out,'browser_error.txt'),String(e.stack));console.error(e);process.exitCode=1;});
