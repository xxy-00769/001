const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:1100}});
 try {
  const files=fs.readdirSync('reports').filter(x=>/^startup_.*html$/.test(x)).sort();
  const file=path.resolve('reports',files.at(-1));
  await page.goto(pathToFileURL(file).href,{waitUntil:'domcontentloaded'});
  await page.getByRole('heading',{name:'服务正常，FPGA尚未连接。启动成功不代表通信正常。'}).waitFor();
  await page.frameLocator('iframe').locator('#placeholder').waitFor();
  const wait=await page.frameLocator('iframe').locator('#image-state').innerText();
  if(!wait.includes('等待首帧'))throw new Error(wait);
  await page.screenshot({path:'reports/operator_page.png',fullPage:true});
  fs.writeFileSync('reports/browser_operator_check.json',JSON.stringify({ok:true,file,waiting:wait,checks:['Offline warning visible','Real tunneled preview embedded','Waiting first frame; no fabricated image']},null,2));
  console.log('Operator page verified:',file,wait);
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
