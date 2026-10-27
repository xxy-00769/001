// Actual page through SSH; UI controls only. Never injects a protocol EVENT.
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),assert=require('assert');
const out=path.resolve(process.argv[2]);fs.mkdirSync(out,{recursive:true});
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:1000}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 const status=()=>page.evaluate(async()=>await(await fetch('/status.json?t=browser-check',{cache:'no-store'})).json());
 let before;
 try{
  await page.goto('http://127.0.0.1:18080/',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.m401PreviewMetrics?.().newFramesTotal>=15,null,{timeout:15000});
  before=await status();assert.equal(before.release,'M4-02-r1');
  assert.equal(before.link.feedback.controls.mode,'REAL');
  const framesBefore=await page.evaluate(()=>window.m401PreviewMetrics().newFramesTotal);
  const checks=[];
  async function apply(mode,selection){
   await page.getByLabel('判定来源',{exact:true}).selectOption(mode);
   await page.getByLabel('自测结果',{exact:true}).selectOption(selection);
   await page.getByRole('button',{name:'应用到下一个真实按键',exact:true}).click();
   await page.waitForFunction(async({mode,selection})=>{
    const c=(await(await fetch('/status.json?t=control-check',{cache:'no-store'})).json()).link.feedback.controls;
    return c.mode===mode&&c.selection===selection;
   },{mode,selection},{timeout:6000});
   await page.waitForFunction(mode=>document.querySelector('#simulation-warning').hidden===(mode==='REAL'),mode,{timeout:4000});
   checks.push({mode,selection});
  }
  for(const choice of ['allow','deny','red','solid','unknown']){
   await apply('SELF_TEST',choice);
   if(choice==='red')await page.screenshot({path:path.join(out,'m402_simulation.png'),fullPage:true});
  }
  await apply('REAL','unknown');
  await page.waitForFunction(n=>window.m401PreviewMetrics().newFramesTotal>=n+30,framesBefore,{timeout:10000});
  const after=await status(),metrics=await page.evaluate(()=>window.m401PreviewMetrics());
  const image=await page.locator('#image').evaluate(i=>({visible:!i.hidden,width:i.naturalWidth,height:i.naturalHeight}));
  assert(image.visible&&image.width===640&&image.height===360);assert.equal(metrics.maxInFlight,1);assert.equal(errors.length,0);
  await page.screenshot({path:path.join(out,'m402_real.png'),fullPage:true});
  await page.locator('section.panel').screenshot({path:path.join(out,'m402_panel.png')});
  fs.writeFileSync(path.join(out,'browser_check.json'),JSON.stringify({ok:true,before,after,metrics,image,checks,errors,
   real_hardware_events_during_check:(after.link.feedback.counts.events||0)-(before.link.feedback.counts.events||0),
   note:'UI/HTTP controls and actual camera preview checked; no synthetic EVENT/RESULT_ACK sent to board. Physical key/screen tests require user.'},null,2));
  console.log(JSON.stringify({ok:true,checks,metrics,image,events:after.link.feedback.counts,errors}));
 }finally{
  // Leave normal REAL mode even if a UI assertion failed mid-self-test.
  if(before)await page.evaluate(async()=>{const s=await(await fetch('/status.json')).json();await fetch('/feedback/control',{
   method:'POST',headers:{'Content-Type':'application/json','X-M4-Control-Token':s.control_token},
   body:JSON.stringify({mode:'REAL',selection:'unknown'})});}).catch(()=>{});
  await browser.close();
 }
})().catch(e=>{fs.writeFileSync(path.join(out,'browser_error.txt'),String(e.stack));console.error(e);process.exitCode=1;});
