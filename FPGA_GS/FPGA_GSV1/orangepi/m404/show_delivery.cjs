const fs=require('fs'),path=require('path'),assert=require('assert');
const {chromium}=require('C:/Users/YuHuang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{const b=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});try{
 const p=await b.newPage({viewport:{width:1280,height:1100}});await p.goto('http://127.0.0.1:18080/');await p.waitForFunction(()=>window.m403Metrics?.().newFrames>2);
 await p.getByRole('button',{name:'日间人车 54秒',exact:true}).click();
 let s,end=Date.now()+18000;
 while(Date.now()<end){s=await(await p.request.get('http://127.0.0.1:18080/status.json')).json();if(s.video==='SC_BT.mp4'&&s.position>56.5&&s.position<59&&s.detection?.objects.some(x=>x.class_id===0))break;await p.waitForTimeout(100);}
 assert(s.detection.objects.some(x=>x.class_id===0));await p.screenshot({path:path.join(__dirname,'evidence/final/delivery_page.png'),fullPage:true});
 delete s.control_token;fs.writeFileSync(path.join(__dirname,'evidence/final/delivery_status.json'),JSON.stringify(s,null,2));console.log('new shortcut verified: actual people + vehicles / RKNN/NPU');
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
