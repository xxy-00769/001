// Real LIVE_FRONT through the SSH forward; no fixtures or injected video.
const fs=require('fs'),path=require('path');
const {chromium}=require(process.argv[2]);
const out=path.resolve(process.argv[3]);fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:1000}});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{window.__front15Frames=[];window.addEventListener('m401-preview-frame',e=>{
  window.__front15Frames.push(e.detail);if(window.__front15Frames.length>2500)window.__front15Frames.shift();
 });});
 try{
  await page.goto('http://127.0.0.1:18080/',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.__front15Frames.length>=30,null,{timeout:20000});
  fs.writeFileSync(path.join(out,'browser_ready.json'),JSON.stringify({ready:true,time:new Date().toISOString()}));
  const deadline=Date.now()+100000;
  let window=null;
  while(!window){
   if(Date.now()>deadline)throw Error('Collector did not finish in 100 seconds');
   try{
    const candidate=JSON.parse(fs.readFileSync(path.join(out,'window.json'),'utf8'));
    if(candidate.first&&candidate.last)window=candidate;
   }catch(e){if(!['EBUSY','ENOENT','EACCES'].includes(e.code)&&!(e instanceof SyntaxError))throw e;}
   if(!window)await page.waitForTimeout(250); // scp creates a file before releasing its Windows lock.
  }
  const a=window.first.monotonic*1000,b=window.last.monotonic*1000;
  const frames=await page.evaluate(()=>window.__front15Frames);
  const selected=frames.filter(f=>f.receivedMonotonicMs>=a&&f.receivedMonotonicMs<=b);
  const m=await page.evaluate(()=>window.m401PreviewMetrics());
  const image=await page.locator('#image').evaluate(i=>({visible:!i.hidden,width:i.naturalWidth,height:i.naturalHeight,complete:i.complete}));
  const stats={source:'LIVE_FRONT, actual Edge image.decode via SSH forward',window_seconds:window.window_seconds,
   decoded_unique_frames:selected.length,new_frame_fps:selected.length/window.window_seconds,
   decoded_interval_fps:(selected.length-1)/((selected.at(-1).decodedAtMs-selected[0].decodedAtMs)/1000),
   max_decode_gap_ms:Math.max(...selected.slice(1).map((f,i)=>f.decodedAtMs-selected[i].decodedAtMs)),
   first_frame:selected[0]?.frame,last_frame:selected.at(-1)?.frame,
   unique_sequences:new Set(selected.map(x=>x.sequence)).size,max_in_flight:m.maxInFlight,
   duplicate_responses:m.duplicateResponses,image,errors,
   displayed_text:await page.locator('body').innerText(),
   age_note:'Frame selection uses Orange Pi complete-receive timestamps; browser decode gaps use browser monotonic clock. No FPGA/PC clock subtraction.'};
  fs.writeFileSync(path.join(out,'browser_acceptance.json'),JSON.stringify(stats,null,2));
  fs.writeFileSync(path.join(out,'browser_frames.json'),JSON.stringify(selected));
  await page.screenshot({path:path.join(out,'browser_preview.png'),fullPage:true});
  console.log(JSON.stringify(stats));
 }finally{await browser.close();}
})().catch(e=>{fs.writeFileSync(path.join(out,'browser_error.txt'),String(e.stack));process.exitCode=1;});
