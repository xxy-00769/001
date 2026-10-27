// Read-only screenshot of the actual current hardware EVENT; no mode change.
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path');
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1280,height:1000}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:18080/',{waitUntil:'domcontentloaded'});
  let ready=true;
  try{await page.waitForFunction(()=>window.m401PreviewMetrics?.().newFramesTotal>=15&&document.querySelector('#event-identity').textContent.includes('event_id='),null,{timeout:8000});}
  catch{ready=false;}
  fs.writeFileSync(path.join(__dirname,'capture_diagnostic.json'),JSON.stringify({ready,errors,text:await page.locator('body').innerText(),metrics:await page.evaluate(()=>window.m401PreviewMetrics?.())},null,2));
  const status=await page.evaluate(async()=>await(await fetch('/status.json?t=real-event-capture')).json());
  delete status.control_token;
  fs.writeFileSync(path.join(__dirname,'hardware_event_status.json'),JSON.stringify(status,null,2));
  await page.locator('section.panel').screenshot({path:path.join(__dirname,'m402_real_event_panel.png')});
  await page.screenshot({path:path.join(__dirname,'m402_real_event.png'),fullPage:true});
  console.log(JSON.stringify({events:status.link.feedback.counts,controls:status.link.feedback.controls,preview:await page.evaluate(()=>window.m401PreviewMetrics())}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
