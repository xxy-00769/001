// Targeted web regression in an isolated installed Edge test profile.
// argv: playwright-module, edge-executable, tunneled-url, evidence-directory.
const {chromium} = require(process.argv[2]);
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const assert = require('node:assert/strict');
const base = process.argv[4], out = process.argv[5];
fs.mkdirSync(out, {recursive:true});
const root='/home/orangepi/fpga_gs_m401_v0_1_1_20261021/runs/web_fixture_v011';
function control(command) {
  execFileSync('ssh',['-p','22','-o','HostKeyAlias=10.168.29.122','-o','StrictHostKeyChecking=yes',
    '-o','BatchMode=yes','orangepi@192.168.0.4',command],{encoding:'utf8',timeout:10000});
}
(async () => {
  const browser=await chromium.launch({executablePath:process.argv[3],headless:true});
  const page=await browser.newPage({viewport:{width:1365,height:1100}});
  const errors=[]; page.on('pageerror',error=>errors.push(error.message));
  const report={version:'v0.1.1',mode:'FILE_TEST',base,checks:[],errors};
  async function screenshot(name) {await page.screenshot({path:path.join(out,name+'.png'),fullPage:true});}
  async function decoded() {
    await page.waitForFunction(()=>{
      const image=document.getElementById('image');
      return !image.hidden && image.complete && image.naturalWidth>0;
    },null,{timeout:15000});
  }
  async function frame() {return Number(await page.locator('#frame').textContent());}
  try {
    await page.goto(base,{waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>document.getElementById('image-state').textContent.includes('等待首帧'));
    assert(await page.locator('#image').isHidden());
    assert.equal(await page.locator('#diagnostic').evaluate(el=>el.open),false);
    await screenshot('01_waiting_first_frame');
    report.checks.push('Actual empty server: waiting first frame, image hidden, diagnostics collapsed');
    control('touch '+root+'/start');
    await decoded();
    const firstFrame=await frame();
    const firstSrc=await page.locator('#image').getAttribute('src');
    const firstPixels=await page.locator('#image').evaluate(image=>{
      const canvas=document.createElement('canvas');canvas.width=128;canvas.height=72;
      canvas.getContext('2d').drawImage(image,0,0,128,72);return canvas.toDataURL();
    });
    await page.waitForFunction(({fid,src})=>Number(document.getElementById('frame').textContent)>fid &&
      document.getElementById('image').getAttribute('src')!==src,{fid:firstFrame,src:firstSrc},{timeout:10000});
    await decoded();
    const secondPixels=await page.locator('#image').evaluate(image=>{
      const canvas=document.createElement('canvas');canvas.width=128;canvas.height=72;
      canvas.getContext('2d').drawImage(image,0,0,128,72);return canvas.toDataURL();
    });
    assert.notEqual(firstPixels,secondPixels);
    report.frames=[firstFrame,await frame()];
    report.checks.push('Live homepage: frame ID, blob URL and decoded pixel content changed without reload');
    await screenshot('02_actual_file_updating');
    report.http=[];
    for(const route of ['/latest.jpg','/latest.jpg?t=arbitrary-123','/raw.jpg','/raw.jpg?t=raw','/status.json','/status.json?t=status']) {
      const response=await page.request.get(base+route);
      assert.equal(response.status(),200);
      const headers=response.headers();
      assert(headers['cache-control'].includes('no-store'));
      assert.equal(headers.pragma,'no-cache');assert.equal(headers.expires,'0');
      const bytes=await response.body();
      if(route.includes('.jpg')) {
        assert(headers['content-type'].startsWith('image/jpeg'));
        const size=await page.evaluate(async ({data})=>{
          const blob=await(await fetch('data:image/jpeg;base64,'+data)).blob();
          const bitmap=await createImageBitmap(blob);const size=[bitmap.width,bitmap.height];bitmap.close();return size;
        },{data:bytes.toString('base64')});
        assert.deepEqual(size,[1280,720]);
        report.http.push({route,status:response.status(),size,cache:headers['cache-control'],sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
      } else {
        const status=JSON.parse(bytes.toString());assert.equal(status.mode,'FILE_TEST');assert(status.processed>0);
        report.http.push({route,status:response.status(),mode:status.mode,processed:status.processed,cache:headers['cache-control']});
      }
    }
    control('touch '+root+'/pause');
    await page.waitForFunction(()=>document.getElementById('image-state').textContent.includes('画面获取失败'),null,{timeout:10000});
    assert(await page.locator('#image').isHidden());
    await screenshot('03_image_failure_explained');
    report.checks.push('Actual server JPEG unavailable: HTTP 503 shown, broken image hidden, automatic retry');
    const pausedFrame=await frame();
    control('rm '+root+'/pause');
    await decoded();
    await page.waitForFunction(fid=>Number(document.getElementById('frame').textContent)>fid,pausedFrame);
    await screenshot('04_recovered_without_reload');
    report.checks.push('Restored real FILE_TEST frames: recovered automatically without page reload');
    await page.route('**/status.json*',route=>route.abort());
    await page.waitForFunction(()=>document.getElementById('data-state').textContent.includes('状态获取失败'));
    await page.unroute('**/status.json*');
    await page.waitForFunction(()=>document.getElementById('data-state').textContent.startsWith('已处理'));
    report.checks.push('Status fetch failure explicitly shown and automatically recovered');
    await page.locator('summary').click();
    assert(await page.locator('#diagnostics').isVisible());
    await page.locator('summary').click();
    report.final={frame:await frame(),fps:await page.locator('#fps').textContent(),
      mode:await page.locator('#mode').textContent(),signal:await page.locator('#signal').textContent()};
    assert.equal(errors.length,0);
    fs.writeFileSync(path.join(out,'browser_report.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify(report,null,2));
  } finally {
    control('touch '+root+'/stop');
    await browser.close();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
