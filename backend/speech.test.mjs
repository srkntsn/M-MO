import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('./speech.js',import.meta.url),'utf8');
const {speechResponse}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('speech wraps PCM in a valid WAV and sends voice configuration',async()=>{
 const original=globalThis.fetch;let body;
 globalThis.fetch=async(url,options)=>{
  body=JSON.parse(options.body);assert.equal(options.headers['x-goog-api-key'],'test-key');
  return Response.json({candidates:[{content:{parts:[{inlineData:{mimeType:'audio/L16;codec=pcm;rate=24000',data:Buffer.from([0,0,255,127]).toString('base64')}}]}}]});
 };
 try{
  const response=await speechResponse('Merhaba',{GEMINI_API_KEY:'test-key'});
  assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');
  const bytes=Buffer.from(await response.arrayBuffer());
  assert.equal(bytes.subarray(0,4).toString(),'RIFF');assert.equal(bytes.readUInt32LE(40),4);
  assert.equal(bytes.readUInt32LE(24),24000);assert.deepEqual([...bytes.subarray(44)],[0,0,255,127]);
  assert.equal(body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName,'Aoede');
 }finally{globalThis.fetch=original;}
});
test('invalid text never calls provider; upstream errors stay private',async()=>{
 assert.equal((await speechResponse('',{})).status,400);
 assert.equal((await speechResponse('x'.repeat(1401),{})).status,400);
 const original=globalThis.fetch;globalThis.fetch=async()=>Response.json({error:'private-key'},{status:403});
 try{const response=await speechResponse('Merhaba',{});assert.equal(response.status,503);assert.ok(!(await response.text()).includes('private-key'));}
 finally{globalThis.fetch=original;}
});
