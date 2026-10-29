import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('./live.js',import.meta.url),'utf8');
const {liveSetup,clientPacket,chooseLiveModel,liveResponse}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('Live input continues during output; interruption and natural pauses configured',()=>{
 const {setup}=liveSetup('test-live','persona','opaque-session');
 assert.equal(setup.realtimeInputConfig.activityHandling,'START_OF_ACTIVITY_INTERRUPTS');
 assert.equal(setup.realtimeInputConfig.automaticActivityDetection.silenceDurationMs,800);
 assert.equal(setup.sessionResumption.handle,'opaque-session');
 assert.deepEqual(setup.generationConfig.responseModalities,['AUDIO']);
 assert.deepEqual(clientPacket(new Uint8Array([1,0,2,0]).buffer,new Map()),{realtimeInput:{audio:{mimeType:'audio/pcm;rate=16000',data:'AQACAA=='}}});
 for(const p of [new ArrayBuffer(3),new ArrayBuffer(3202),'{}','{"setup":{"model":"other"}}','{"type":"tool","id":"unknown","result":"ok"}'])assert.throws(()=>clientPacket(p,new Map()));
 const pending=new Map([['call-1','capture_camera']]);
 assert.equal(clientPacket('{"type":"tool","id":"call-1","result":"sent"}',pending).toolResponse.functionResponses[0].name,'capture_camera');
 assert.equal(pending.size,0);
});
test('catalog selects an audio conversation model; inaccessible catalog fails without logging keys',async()=>{
 const original=globalThis.fetch;
 try{
  globalThis.fetch=async()=>Response.json({models:[{name:'models/gemini-tts',supportedGenerationMethods:['generateContent']},{name:'models/gemini-3.8-live',supportedGenerationMethods:['bidiGenerateContent']}]});
  assert.equal(await chooseLiveModel({GEMINI_API_KEY:'private'}),'gemini-3.8-live');
  globalThis.fetch=async()=>Response.json({error:'private'},{status:403});
  await assert.rejects(chooseLiveModel({GEMINI_API_KEY:'private'}),/live_catalog/);
 }finally{globalThis.fetch=original;}
});
class Socket extends EventTarget {
 sent=[];closed=false;accepted=false;
 accept(){this.accepted=true;}
 send(p){this.sent.push(JSON.parse(p));}
 close(code=1000){if(this.closed)return;this.closed=true;const e=new Event('close');e.code=code;this.dispatchEvent(e);}
 message(data){const e=new Event('message');e.data=data;this.dispatchEvent(e);}
}
test('relay keeps both directions open across turns, forwards interruptions, sanitizes errors',async()=>{
 const original={fetch:globalThis.fetch,Response:globalThis.Response,WebSocketPair:globalThis.WebSocketPair};
 const upstream=new Socket(),server=new Socket(),client=new Socket();
 globalThis.WebSocketPair=class {constructor(){return {0:client,1:server};}};
 globalThis.Response=class extends original.Response {constructor(body,init){if(init?.status===101)return {status:101,webSocket:init.webSocket};super(body,init);}};
 globalThis.fetch=async(url,opts)=>url.includes('/models?')?original.Response.json({models:[{name:'models/gemini-3.8-live',supportedGenerationMethods:['bidiGenerateContent']}]}):{webSocket:upstream,status:101};
 try{
  const response=await liveResponse(new Request('https://test/live',{headers:{Upgrade:'websocket'}}),{GEMINI_API_KEY:'private'},'persona');
  assert.equal(response.status,101);
  server.message('{"type":"start"}');assert.ok(upstream.sent[0].setup);
  upstream.message('{"setupComplete":{}}');
  upstream.message('{"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQACAA=="}}]}}}');
  // Microphone is still accepted while model audio is being produced.
  server.message(new Uint8Array([1,0]).buffer);assert.ok(upstream.sent.at(-1).realtimeInput.audio);
  upstream.message('{"serverContent":{"interrupted":true,"turnComplete":true}}');
  assert.ok(server.sent.find(p=>p.type==='interrupt'));assert.equal(server.closed,false);
  server.message(new Uint8Array([2,0]).buffer);assert.equal(upstream.sent.at(-1).realtimeInput.audio.data,'AgA=');
  upstream.message('{"error":{"message":"private secret"}}');
  assert.equal(JSON.stringify(server.sent).includes('private secret'),false);assert.equal(server.closed,true);
 }finally{server.close();upstream.close();Object.assign(globalThis,original);}
});
