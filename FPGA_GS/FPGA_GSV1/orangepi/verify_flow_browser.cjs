// v0.1.2 FILE_TEST only. Existing Edge + Playwright, via the real SSH tunnel.
// argv: playwright module, Edge executable, tunneled base URL, evidence directory.
const {chromium}=require(process.argv[2]);
const fs=require('node:fs'), path=require('node:path'), assert=require('node:assert/strict');
const base=process.argv[4], out=process.argv[5];fs.mkdirSync(out,{recursive:true});
(async()=>{
  const browser=await chromium.launch({executablePath:process.argv[3],headless:true});
  const page=await browser.newPage({viewport:{width:1365,height:1100}});
  const errors=[], statuses=[], requests={images:0,status:0,active:0,maxActive:0};
  let latestStatus=null;
  const report={version:'v0.1.2',mode:'FILE_TEST',base,checks:[],errors};
  page.on('pageerror',error=>errors.push(error.message));
  page.on('request',request=>{
    if(request.url().includes('/stream.mjpg')){
      requests.images++;requests.active++;requests.maxActive=Math.max(requests.maxActive,requests.active);
    }
    if(request.url().includes('/status.json'))requests.status++;
  });
  function finished(request){if(request.url().includes('/stream.mjpg'))requests.active--;}
  page.on('requestfinished',finished);page.on('requestfailed',finished);
  page.on('response',async response=>{
    if(response.url().includes('/status.json') && response.ok()){
      try {latestStatus=await response.json();statuses.push({hostMs:Date.now(),...latestStatus});}catch{}
    }
  });
  async function shot(name){await page.screenshot({path:path.join(out,name+'.png'),fullPage:true});}
  async function decoded(){await page.waitForFunction(()=>{
    const image=document.getElementById('image');return !image.hidden&&image.complete&&image.naturalWidth>0;
  },null,{timeout:15000});}
  async function pixels(){return page.locator('#image').evaluate(image=>{
    const canvas=document.createElement('canvas');canvas.width=128;canvas.height=72;
    canvas.getContext('2d').drawImage(image,0,0,128,72);return canvas.toDataURL();
  });}
  try{
    // Controlled HTTP503 in this browser only; the production app keeps running.
    await page.route('**/stream.mjpg*',route=>route.fulfill({status:503,body:'waiting test'}));
    await page.goto(base,{waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>document.getElementById('image-state').textContent.includes('等待首帧'));
    assert(await page.locator('#image').isHidden());await shot('01_waiting');
    await page.unroute('**/stream.mjpg*');await decoded();
    report.checks.push('Browser first-frame HTTP503: waiting text and hidden image, automatic recovery');
    await page.waitForFunction(()=>window.m401PreviewMetrics().newFramesTotal>=60);
    const firstPixels=await pixels();
    const first=await page.evaluate(()=>({time:performance.now(),metrics:window.m401PreviewMetrics()}));
    const firstStatus=latestStatus, firstRequestCounts={...requests};
    report.samples=[];
    for(let i=0;i<30;i++){
      await page.waitForTimeout(1000); // The requested timed continuous-playback measurement.
      report.samples.push({browser:await page.evaluate(()=>({time:performance.now(),...window.m401PreviewMetrics()})),server:latestStatus});
    }
    const last=await page.evaluate(()=>({time:performance.now(),metrics:window.m401PreviewMetrics()}));
    const lastStatus=latestStatus, seconds=(last.time-first.time)/1000;
    const serverSeconds=(lastStatus.host_monotonic_ms-firstStatus.host_monotonic_ms)/1000;
    report.requests={...requests,scope:'Before forced-reload/error fixtures; includes waiting and warmup'};
    report.measurement={seconds,newFrames:last.metrics.newFramesTotal-first.metrics.newFramesTotal,
      previewUniqueFps:(last.metrics.newFramesTotal-first.metrics.newFramesTotal)/seconds,
      processedFrames:lastStatus.processed-firstStatus.processed,
      processedFps:(lastStatus.processed-firstStatus.processed)/serverSeconds,
      serverMeasurementSeconds:serverSeconds,firstServerStatusMs:firstStatus.host_monotonic_ms,lastServerStatusMs:lastStatus.host_monotonic_ms,
      firstLoop:firstStatus.playback.loop_index,lastLoop:lastStatus.playback.loop_index,
      sourceFps:lastStatus.playback.source_fps,
      imageRequests:requests.images-firstRequestCounts.images,statusRequests:requests.status-firstRequestCounts.status,
      duplicates:last.metrics.duplicateResponses-first.metrics.duplicateResponses,maxInFlight:last.metrics.maxInFlight};
    function stats(values){const sorted=values.sort((a,b)=>a-b);return {min:sorted[0],p50:sorted[Math.floor(sorted.length*.5)],p95:sorted[Math.floor(sorted.length*.95)],max:sorted.at(-1)};}
    report.measurement.imageAgeUpperMs=stats(report.samples.map(x=>x.browser.imageAgeUpperMs));
    report.measurement.mediaLagMs=stats(report.samples.map(x=>x.server.playback.media_lag_ms));
    report.measurement.processTotalMs=stats(report.samples.map(x=>x.server.stage_ms.process_total));
    fs.writeFileSync(path.join(out,'browser_flow_report.json'),JSON.stringify(report,null,2));
    console.log('30s measurement:',JSON.stringify(report.measurement));
    assert.notEqual(await pixels(),firstPixels);
    assert.equal(last.metrics.maxInFlight,1);assert.equal(requests.maxActive,1);
    assert(lastStatus.playback.loop_index-firstStatus.playback.loop_index>=2);
    assert.equal(lastStatus.playback.source_fps,30);
    assert.equal(await page.locator('#diagnostic').evaluate(el=>el.open),false);
    await shot('02_continuous_file_test');
    report.checks.push('Continuous 30s real FILE_TEST: decoded pixels changed, at least two loop boundaries, one MJPEG connection in flight');
    report.http=[];
    for(const route of ['/latest.jpg','/latest.jpg?t=arbitrary','/raw.jpg','/raw.jpg?t=raw','/status.json?t=status']){
      const response=await page.request.get(base+route);assert.equal(response.status(),200);
      const headers=response.headers();assert(headers['cache-control'].includes('no-store'));
      const entry={route,status:response.status(),cache:headers['cache-control']};
      if(route.includes('.jpg')){
        const data=(await response.body()).toString('base64');
        entry.size=await page.evaluate(async data=>{
          const blob=await(await fetch('data:image/jpeg;base64,'+data)).blob();
          const bitmap=await createImageBitmap(blob);const size=[bitmap.width,bitmap.height];bitmap.close();return size;
        },data);assert.deepEqual(entry.size,route.startsWith('/raw')?[1280,720]:[lastStatus.preview_encoding.width,Math.round(lastStatus.preview_encoding.width*720/1280)]);
      }
      report.http.push(entry);
    }
    // Freeze exactly one published JPEG to prove repeats never count as new frames.
    const frozen=await page.request.get(base+'/latest.jpg');
    const frozenBody=await frozen.body(), frozenHeaders=frozen.headers();
    const frozenPacket=Buffer.concat([Buffer.from('--frame\r\nContent-Type: image/jpeg\r\nContent-Length: '+frozenBody.length+
      '\r\nX-Frame-Sequence: '+frozenHeaders['x-frame-sequence']+'\r\nX-Frame-ID: '+frozenHeaders['x-frame-id']+
      '\r\nX-Frame-Received-Ms: '+latestStatus.latest.received_monotonic*1000+'\r\n\r\n'),frozenBody,Buffer.from('\r\n')]);
    await page.route('**/stream.mjpg*',route=>route.fulfill({status:200,body:frozenPacket,
      contentType:'multipart/x-mixed-replace; boundary=frame'}));
    await page.reload({waitUntil:'domcontentloaded'});
    const duplicatesBefore=await page.evaluate(()=>window.m401PreviewMetrics().duplicateResponses);
    await page.waitForFunction(({seq,duplicates})=>window.m401PreviewMetrics().lastSequence===seq &&
      window.m401PreviewMetrics().duplicateResponses>=duplicates+2,
      {seq:frozenHeaders['x-frame-sequence'],duplicates:duplicatesBefore});
    const frozenStart=await page.evaluate(()=>window.m401PreviewMetrics());await page.waitForTimeout(1200);
    const frozenEnd=await page.evaluate(()=>window.m401PreviewMetrics());
    assert.equal(frozenStart.newFramesTotal,frozenEnd.newFramesTotal);
    assert(frozenEnd.duplicateResponses>frozenStart.duplicateResponses);
    await page.unroute('**/stream.mjpg*');
    await page.waitForFunction(seq=>window.m401PreviewMetrics().lastSequence!==seq,frozenHeaders['x-frame-sequence']);
    report.checks.push('Repeated identical frame sequence adds zero preview new frames; fresh frames recover');
    await page.route('**/stream.mjpg*',route=>route.abort());
    await page.reload({waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>document.getElementById('image-state').textContent.includes('画面获取失败'));
    assert(await page.locator('#image').isHidden());await shot('03_failure');
    await page.unroute('**/stream.mjpg*');await decoded();await shot('04_recovered');
    report.checks.push('Browser image request failure: explicit message, broken image hidden, automatic recovery');
    assert.equal(errors.length,0);
    report.statusHistory=statuses;
    fs.writeFileSync(path.join(out,'browser_flow_report.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify({...report,samples:undefined,statusHistory:undefined},null,2));
  } finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
