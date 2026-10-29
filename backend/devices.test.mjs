import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = await readFile(new URL('./devices.js',import.meta.url),'utf8');
const {DeviceRegistry,deviceRoutes,authorized,digest} = await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));

// Serialized transactional storage models the DO atomic redemption boundary.
class Storage {
  data = new Map(); tail = Promise.resolve();
  async get(k) { return structuredClone(this.data.get(k)); }
  async put(k,v) { this.data.set(k,structuredClone(v)); }
  async delete(k) { for (const key of Array.isArray(k) ? k : [k]) this.data.delete(key); }
  async list({prefix,limit}) { return new Map([...this.data].filter(([k])=>k.startsWith(prefix)).slice(0,limit)); }
  transaction(fn) { const p=this.tail.then(()=>fn(this)); this.tail=p.catch(()=>{}); return p; }
}
function setup() {
  const storage = new Storage(), object = new DeviceRegistry({storage});
  const env = {MIMO_ACCESS_TOKEN:'owner-test',MIMO_DEVICES:{idFromName:()=>1,get:()=>({fetch:(u,o)=>object.fetch(new Request(u,o))})}};
  const req = (path,body,owner=false) => new Request('https://worker.test'+path,{
    method:body ? 'POST':'GET',headers:owner ? {Authorization:'Bearer owner-test'}:{},body:body ? JSON.stringify(body):undefined,
  });
  return {env,req,storage};
}
const secret = 'device_'+'a'.repeat(64), other = 'device_'+'b'.repeat(64);
test('owner-only invite and device administration; missing binding fails clearly',async()=>{
 const {env,req}=setup();
 for (const path of ['/admin/invites','/admin/devices','/admin/devices/revoke']) assert.equal((await deviceRoutes(req(path,{}),env)).status,401);
 assert.equal((await deviceRoutes(req('/admin/invites',{label:'Partner'},true),{MIMO_ACCESS_TOKEN:'owner-test'})).status,503);
});
test('invitation atomically binds one device; retry is idempotent; revocation stops access',async()=>{
 const {env,req,storage}=setup();
 const invitation=await (await deviceRoutes(req('/admin/invites',{label:'Ortağım'},true),env)).json();
 const code=new URL(invitation.url).hash.slice(1);
 assert.equal(code.length,64); assert.ok(!invitation.url.includes('owner-test'));
 const results=await Promise.all([secret,other].map(deviceToken=>deviceRoutes(req('/auth/redeem',{code,deviceToken}),env)));
 assert.deepEqual(results.map(x=>x.status).sort(),[200,409]);
 const winner=results.findIndex(x=>x.status===200);
 const winningSecret=[secret,other][winner], losingSecret=[secret,other][1-winner];
 const {id}=await results[winner].json();
 assert.equal((await deviceRoutes(req('/auth/redeem',{code,deviceToken:winningSecret}),env)).status,200);
 assert.equal(JSON.stringify([...storage.data]).includes(winningSecret),false);
 const auth = new Request('https://worker.test/',{headers:{Authorization:'Bearer '+winningSecret}});
 assert.equal(await authorized(auth,env),true);
 assert.equal(await authorized(new Request('https://worker.test/',{headers:{Authorization:'Bearer '+losingSecret}}),env),false);
 const listing=await (await deviceRoutes(req('/admin/devices',null,true),env)).json();
 assert.equal(listing.devices[0].label,'Ortağım'); assert.equal(JSON.stringify(listing).includes('hash'),false);
 assert.equal((await deviceRoutes(req('/admin/devices/revoke',{id},true),env)).status,200);
 assert.equal(await authorized(auth,env),false);
 assert.equal((await deviceRoutes(req('/auth/redeem',{code,deviceToken:winningSecret}),env)).status,409);
});
test('expired, malformed and oversized activation rejected without storing devices',async()=>{
 const {env,req,storage}=setup(); const code='c'.repeat(64);
 await storage.put('invite:'+await digest(code),{expiresAt:Date.now()-1,label:'Expired'});
 assert.equal((await deviceRoutes(req('/auth/redeem',{code,deviceToken:secret}),env)).status,410);
 assert.equal((await deviceRoutes(req('/auth/redeem',{code:'bad',deviceToken:secret}),env)).status,400);
 assert.equal((await deviceRoutes(req('/auth/redeem',{padding:'x'.repeat(5000)}),env)).status,413);
 assert.equal((await storage.list({prefix:'device:',limit:100})).size,0);
});
test('landing page does not consume invite; no cache or third party scripts',async()=>{
 const {env,req}=setup(); const response=await deviceRoutes(req('/activate'),env);
 assert.equal(response.status,200); assert.equal(response.headers.get('Cache-Control'),'no-store');
 const html=await response.text(); assert.ok(html.includes('location.hash')); assert.ok(!html.includes('fetch('));
});
