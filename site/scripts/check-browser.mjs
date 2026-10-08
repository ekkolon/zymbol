import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = resolve(dirname(fileURLToPath(new URL('../dist/styles.css', import.meta.url))));
const mime = { '.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.wasm':'application/wasm','.xml':'application/xml','.svg':'image/svg+xml' };
const sleep = ms => new Promise(ok => setTimeout(ok, ms));
const root = '/zymbol/';
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url,'http://localhost').pathname);
    if (!pathname.startsWith(root)) throw new Error('Unknown path');
    const subpath = pathname.slice(root.length);
    const target = resolve(dist, subpath.endsWith('/') || !subpath ? join(subpath,'index.html') : subpath);
    if (!target.startsWith(dist+'/')) throw new Error('Invalid path');
    const bytes = await readFile(target);
    response.writeHead(200, {'Content-Type':mime[extname(target)]||'application/octet-stream','X-Content-Type-Options':'nosniff'}).end(bytes);
  } catch { response.writeHead(404).end(); }
});
await new Promise((ok,fail)=>{ server.once('error',fail);server.listen(0,'127.0.0.1',ok); });
const profile=mkdtempSync(join(tmpdir(),'zymbol-site-browser-'));
const downloads=join(profile,'downloads');
let chrome;
let socket;
const exceptions=[];
try {
  const executable = process.env.CHROME_BIN || 'google-chrome';
  chrome=spawn(executable,['--headless=new','--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--no-first-run','--disable-extensions','--remote-debugging-port=0','--remote-allow-origins=*',`--user-data-dir=${profile}`,'about:blank'],{stdio:['ignore','ignore','pipe']});
  let stderr='';chrome.stderr.setEncoding('utf8');chrome.stderr.on('data',chunk=>{stderr=(stderr+chunk).slice(-3000);});
  let port;
  for(let i=0;i<300;i++){
    if(chrome.exitCode!==null || chrome.signalCode!==null) throw new Error(`Chrome exited: ${stderr}`);
    try{port=Number(readFileSync(join(profile,'DevToolsActivePort'),'utf8').split('\n')[0]);break;}catch{await sleep(100);}
  }
  if(!port)throw new Error(`Chrome did not start: ${stderr}`);
  const tabs=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const target=tabs.find(t=>t.type==='page');
  assert.ok(target?.webSocketDebuggerUrl,'Missing Chrome page target');
  socket=new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((ok,fail)=>{socket.addEventListener('open',ok,{once:true});socket.addEventListener('error',fail,{once:true});});
  let next=0;
  const pending=new Map();
  const listeners=new Map();
  socket.addEventListener('message',event=>{
    const msg=JSON.parse(event.data);
    if(msg.id){const item=pending.get(msg.id);pending.delete(msg.id);if(item){msg.error?item.reject(Error(msg.error.message)):item.resolve(msg.result);}}
    if(msg.method==='Page.loadEventFired'){for(const resolve of listeners.get('Page.loadEventFired')||[])resolve();listeners.delete('Page.loadEventFired');}
    if(msg.method==='Runtime.exceptionThrown')exceptions.push(msg.params.exceptionDetails.exception?.description||msg.params.exceptionDetails.text);
    if(msg.method==='Log.entryAdded' && msg.params.entry.level==='error')exceptions.push(msg.params.entry.text);
  });
  const send=(method,params={})=>new Promise((ok,fail)=>{const id=++next;pending.set(id,{resolve:ok,reject:fail});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async(expression,timeout=15000)=>{
    const timeoutFail=new Promise((_,fail)=>setTimeout(()=>fail(Error(`Evaluation timed out: ${expression.slice(0,40)}`)),timeout));
    const result=await Promise.race([send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true}),timeoutFail]);
    if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));
    return result.result?.value;
  };
  const base=`http://127.0.0.1:${server.address().port}${root}`;
  await send('Runtime.enable');await send('Log.enable');await send('Page.enable');
  await send('Page.setDownloadBehavior',{behavior:'allow',downloadPath:downloads}).catch(()=>{});
  async function navigate(route){
    const loaded=new Promise(resolve=>{listeners.set('Page.loadEventFired',[resolve]);});
    const result=await send('Page.navigate',{url:base+route});
    if(result.errorText)throw Error(result.errorText);
    await Promise.race([loaded,new Promise((_,fail)=>setTimeout(()=>fail(Error(`Page load timeout: ${route}`)),15000))]);
  }
  for(const route of ['','create/','create-qr-code/','create-micro-qr/','docs/','docs/getting-started/','docs/javascript/','docs/zig/','docs/encoding/','docs/decoding/','docs/rendering/','docs/testing/']){
    await navigate(route);
    assert.ok(await evaluate('Boolean(document.querySelector("h1") && document.querySelector("link[rel=canonical]"))'),`Missing semantics: ${route}`);
    assert.ok(await evaluate('document.body.scrollWidth <= innerWidth + 1'),`Horizontal overflow: ${route}`);
  }
  for(const [route,expected] of [['create/','qr'],['create-qr-code/','qr'],['create-micro-qr/','micro']]){
    await navigate(route);
    const result=await evaluate(`new Promise(resolve=>{const end=Date.now()+16000;const poll=()=>{const label=document.getElementById('runtime-label')?.textContent;if(label==='WASM ready'&&!document.getElementById('download-svg')?.disabled){resolve({family:document.getElementById('symbol-description')?.textContent,enabled:!document.getElementById('download-png')?.disabled,src:document.getElementById('qr-image')?.src});}else if(Date.now()>end)resolve({error:label,status:document.getElementById('play-status')?.textContent});else setTimeout(poll,60)};poll()})`,20000);
    assert.ok(result.enabled,`${route} WASM failed: ${JSON.stringify(result)}`);
    assert.ok(result.family.includes(expected==='micro'?'Micro QR':'QR Code'),`Incorrect family on ${route}: ${result.family}`);
    assert.ok(result.src.startsWith('blob:'),`Missing locally-rendered preview on ${route}`);
    if(route==='create/'){
      const changed=await evaluate(`new Promise(resolve=>{document.getElementById('payload').value='12345';document.querySelector('input[value="micro"][name="family"]').click();const end=Date.now()+3500;const poll=()=>{const text=document.getElementById('symbol-description')?.textContent;if(text?.includes('Micro QR'))resolve(true);else if(Date.now()>end)resolve(false);else setTimeout(poll,45)};poll()})`);
      assert.ok(changed,'Changing to Micro QR did not re-render');
    }
  }
  for(const width of [320,390,768,1024,1440]){
    await send('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:width<760});
    for(const route of ['','create/','docs/javascript/']){
      await navigate(route);
      const data=await evaluate('({inner:innerWidth,scroll:document.documentElement.scrollWidth})');
      assert.ok(data.scroll<=data.inner+1,`${route} overflows at ${width}: ${JSON.stringify(data)}`);
    }
  }
  assert.deepEqual(exceptions,[],'Uncaught browser errors');
  console.log('Chrome page, QR/Micro WASM and responsive checks passed');
} finally {
  socket?.close();
  if(chrome){chrome.kill('SIGKILL');await Promise.race([new Promise(ok=>chrome.once('close',ok)),sleep(1200)]);}
  rmSync(profile,{recursive:true,force:true,maxRetries:5,retryDelay:100});
  await new Promise(ok=>server.close(ok));
}