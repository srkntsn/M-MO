import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('./worker.js',import.meta.url),'utf8');
const devices=await readFile(new URL('./devices.js',import.meta.url),'utf8');
const speech=await readFile(new URL('./speech.js',import.meta.url),'utf8');
const moduleSource=source.replaceAll("'./devices.js'", "'data:text/javascript;base64,"+Buffer.from(devices).toString('base64')+"'").replaceAll("'./speech.js'", "'data:text/javascript;base64,"+Buffer.from(speech).toString('base64')+"'");
const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(moduleSource).toString('base64'));
const env={MIMO_ACCESS_TOKEN:'test-access',GEMINI_API_KEY:'test-key'};
const request=(body,headers={})=>new Request('https://worker.test/',{method:'POST',headers:{Authorization:'Bearer test-access','Content-Type':'application/json',...headers},body:JSON.stringify(body)});
test('authentication before parsing; GET remains 404',async()=>{
 assert.equal((await worker.fetch(new Request('https://worker.test'),env)).status,404);
 assert.equal((await worker.fetch(request({message:'hi'},{Authorization:'Bearer wrong'}),env)).status,401);
});
test('invalid JSON primitives and image input rejected',async()=>{
 for(const body of [null,[],1,{}, {message:'hello',image:{mimeType:'text/html',data:'abcd'}}]) {
  assert.equal((await worker.fetch(request(body),env)).status,400);
 }
});
test('oversized body without content-length rejected',async()=>{
 const r=await worker.fetch(request({message:'x'.repeat(1500001)}),env);
 assert.equal(r.status,413);
});
test('voice history and camera image forwarded; thought excluded',async()=>{
 const original=globalThis.fetch; let sent;
 globalThis.fetch=async(url,options)=>{
  sent=JSON.parse(options.body);
  assert.equal(options.headers['x-goog-api-key'],'test-key');
  return Response.json({candidates:[{content:{parts:[{thought:true,text:'hidden'},{text:'Bu bir fincan.'}]}}]});
 };
 try {
  const response=await worker.fetch(request({message:'Buna bak',history:[{role:'assistant',text:'Selam'}],image:{mimeType:'image/jpeg',data:'/9j/2Q=='}}),env);
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{reply:'Bu bir fincan.'});
  assert.equal(sent.contents[0].role,'model');
  assert.equal(sent.contents[1].parts[1].inlineData.mimeType,'image/jpeg');
 } finally {globalThis.fetch=original;}
});
test('404 selects an accessible model; upstream failures are sanitized',async()=>{
 const original=globalThis.fetch; let calls=0;
 globalThis.fetch=async(url)=>{
  calls++;
  if(calls===1) return Response.json({error:{status:'NOT_FOUND'}},{status:404});
  if(calls===2) return Response.json({models:[{name:'models/gemini-accessible-flash',supportedGenerationMethods:['generateContent']}]});
  assert.ok(url.includes('gemini-accessible-flash'));
  return Response.json({error:{status:'RESOURCE_EXHAUSTED',message:'private detail'}},{status:429});
 };
 try {
  const r=await worker.fetch(request({message:'hello'}),env);
  assert.equal(r.status,503); const body=await r.json();
  assert.equal(body.reason,'RESOURCE_EXHAUSTED'); assert.equal(body.upstream_status,429);
  assert.equal(JSON.stringify(body).includes('private detail'),false);
 } finally {globalThis.fetch=original;}
});

test('successful model fallback is reused on the next conversation turn',async()=>{
 const original=globalThis.fetch;let calls=0;
 globalThis.fetch=async(url)=>{
  calls++;
  if(calls===1)return Response.json({error:{status:'NOT_FOUND'}},{status:404});
  if(calls===2)return Response.json({models:[{name:'models/gemini-fast-flash',supportedGenerationMethods:['generateContent']}]});
  assert.ok(url.includes('gemini-fast-flash'));
  return Response.json({candidates:[{content:{parts:[{text:'Merhaba.'}]}}]});
 };
 try {
  assert.equal((await worker.fetch(request({message:'İlk tur'}),env)).status,200);
  assert.equal(calls,3);
  assert.equal((await worker.fetch(request({message:'İkinci tur'}),env)).status,200);
  assert.equal(calls,4);
 }finally{globalThis.fetch=original;}
});
