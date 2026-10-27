// Browser smoke check of the unmodified production FILE_TEST startup path.
const {chromium}=require(process.argv[2]);
const fs=require('node:fs'), path=require('node:path'), assert=require('node:assert/strict');
(async()=>{
  const browser=await chromium.launch({executablePath:process.argv[3],headless:true});
  try {
    const page=await browser.newPage({viewport:{width:1365,height:1100}});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.goto(process.argv[4],{waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>!document.getElementById('image').hidden && document.getElementById('image').naturalWidth>0);
    const first=Number(await page.locator('#frame').textContent());
    await page.waitForFunction(fid=>Number(document.getElementById('frame').textContent)>=fid+25,first,{timeout:15000});
    const status=await(await page.request.get(process.argv[4]+'/status.json?t=production')).json();
    assert.equal(status.mode,'FILE_TEST');assert.equal(status.link,null);
    assert(status.processed_fps>3.5 && status.processed_fps<6);
    assert.equal(await page.locator('#diagnostic').evaluate(el=>el.open),false);
    assert.equal(errors.length,0);
    const report={startup:'main.py --mode FILE_TEST',url:page.url(),frames:[first,status.latest.frame_id],
      processed:status.processed,processed_fps:status.processed_fps,imageWidth:await page.locator('#image').evaluate(el=>el.naturalWidth),
      diagnosticsCollapsed:true,errors};
    fs.mkdirSync(process.argv[5],{recursive:true});
    await page.screenshot({path:path.join(process.argv[5],'05_production_file_test.png'),fullPage:true});
    fs.writeFileSync(path.join(process.argv[5],'running_report.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify(report,null,2));
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
