// This module is re-exported by worker.js so Wrangler can bind the class.
const noCache = {'Cache-Control': 'no-store'};
const json = (body, status = 200) => Response.json(body, {status, headers:noCache});
const keyPattern = /^[a-f0-9]{64}$/;
export async function digest(value) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
const random = () => [...crypto.getRandomValues(new Uint8Array(32))].map(x=>x.toString(16).padStart(2,'0')).join('');

export class DeviceRegistry {
  constructor(state) { this.storage = state.storage; }
  async fetch(request) {
    // Only the owning Worker can obtain this object stub. No public DO URL.
    const {action, ...data} = await request.json();
    if (action === 'verify') {
      const id = await this.storage.get('token:' + data.hash);
      return json({allowed: !!id && !!(await this.storage.get('device:' + id))});
    }
    if (action === 'list') {
      const records = await this.storage.list({prefix:'device:',limit:100});
      return json({devices:[...records.values()].map(({id,label,createdAt})=>({id,label,createdAt}))});
    }
    if (action === 'revoke') {
      return this.storage.transaction(async tx => {
        const record = await tx.get('device:' + data.id);
        if (!record) return json({error:'Device not found'},404);
        await tx.delete(['device:' + data.id, 'token:' + record.hash]);
        return json({revoked:true});
      });
    }
    if (action === 'invite') {
      const code = random(), hash = await digest(code);
      const expiresAt = Date.now() + 24*60*60*1000;
      return this.storage.transaction(async tx => {
        const records = await tx.list({prefix:'invite:',limit:101});
        let live = 0;
        for (const [key, record] of records) {
          if (record.expiresAt < Date.now()) await tx.delete(key);
          else live++;
        }
        if (live >= 100) return json({error:'Too many pending invitations'},429);
        await tx.put('invite:' + hash, {expiresAt,label:data.label});
        return json({code,expiresAt});
      });
    }
    if (action === 'redeem') {
      return this.storage.transaction(async tx => {
        const key = 'invite:' + data.inviteHash;
        const invite = await tx.get(key);
        if (!invite || invite.expiresAt < Date.now()) return json({error:'Invitation expired or invalid'},410);
        // A retry after a lost response succeeds only for the original device.
        if (invite.claimedBy) {
          const record = await tx.get('device:' + invite.claimedBy);
          return record?.hash === data.deviceHash
            ? json({activated:true,id:record.id})
            : json({error:'Invitation already used'},409);
        }
        const devices = await tx.list({prefix:'device:',limit:100});
        if (devices.size >= 100) return json({error:'Device limit reached'},429);
        if (await tx.get('token:' + data.deviceHash)) return json({error:'Device token already registered'},409);
        const id = crypto.randomUUID();
        await tx.put('device:' + id, {id,hash:data.deviceHash,label:invite.label,createdAt:Date.now()});
        await tx.put('token:' + data.deviceHash,id);
        await tx.put(key,{...invite,claimedBy:id});
        return json({activated:true,id});
      });
    }
    return json({error:'Unknown operation'},400);
  }
}

function registry(env, payload) {
  const stub = env.MIMO_DEVICES.get(env.MIMO_DEVICES.idFromName('mimo-devices-v1'));
  return stub.fetch('https://registry.internal/', {method:'POST',body:JSON.stringify(payload)});
}

export async function authorized(request, env) {
  const token = request.headers.get('Authorization')?.replace(/^Bearer /,'') || '';
  if (env.MIMO_ACCESS_TOKEN && token === env.MIMO_ACCESS_TOKEN) return true;
  if (!env.MIMO_DEVICES || !/^device_[a-f0-9]{64}$/.test(token)) return false;
  const result = await registry(env,{action:'verify',hash:await digest(token)});
  return (await result.json()).allowed === true;
}

export async function deviceRoutes(request, env) {
  const url = new URL(request.url), path = url.pathname;
  if (path === '/activate' && request.method === 'GET') return activationPage();
  if (!['/admin/invites','/admin/devices','/admin/devices/revoke','/auth/redeem'].includes(path)) return null;
  const owner = !!env.MIMO_ACCESS_TOKEN && request.headers.get('Authorization') === 'Bearer ' + env.MIMO_ACCESS_TOKEN;
  if (path.startsWith('/admin/') && !owner) return json({error:'Unauthorized'},401);
  if ((path === '/admin/devices' && request.method !== 'GET') || (path !== '/admin/devices' && request.method !== 'POST')) return json({error:'Method not allowed'},405);
  if (!env.MIMO_DEVICES) return json({error:'Device activation is not configured'},503);
  if (path === '/admin/devices') return registry(env,{action:'list'});
  let body;
  try {
    // Bound the public activation body even with chunked transfer encoding.
    const reader = request.body?.getReader(); let size = 0, parts = [];
    if (!reader) return json({error:'Bad request'},400);
    while (true) {
      const {done,value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 4096) { await reader.cancel(); return json({error:'Too large'},413); }
      parts.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const p of parts) { bytes.set(p,offset); offset += p.length; }
    body = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
  } catch (_) { return json({error:'Bad request'},400); }
  if (path === '/admin/invites') {
    const label = typeof body.label === 'string' ? body.label.trim().slice(0,60) : '';
    if (!label) return json({error:'Device label required'},400);
    const response = await registry(env,{action:'invite',label});
    if (!response.ok) return response;
    const {code,expiresAt} = await response.json();
    // Fragment is never sent in HTTP request URLs or access logs.
    return json({url:url.origin + '/activate#' + code,expiresAt});
  }
  if (path === '/admin/devices/revoke') {
    if (typeof body.id !== 'string' || !/^[a-f0-9-]{36}$/.test(body.id)) return json({error:'Invalid device'},400);
    return registry(env,{action:'revoke',id:body.id});
  }
  if (!keyPattern.test(body.code || '') || !/^device_[a-f0-9]{64}$/.test(body.deviceToken || '')) return json({error:'Invalid invitation'},400);
  return registry(env,{action:'redeem',inviteHash:await digest(body.code),deviceHash:await digest(body.deviceToken)});
}

function activationPage() {
  return new Response(`<!doctype html><html lang="tr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>MİMO daveti</title><style>body{font:18px system-ui;background:#060d1a;color:#edf8ff;max-width:480px;margin:12vh auto;padding:24px}a{display:block;background:#72d9f5;color:#082233;padding:16px;margin:20px 0;border-radius:14px;text-align:center;text-decoration:none}p{line-height:1.6}</style><h1>MİMO'ya hoş geldin</h1><p>Önce güncel MİMO uygulamasını kur. Sonra bu sayfaya dönüp cihazını etkinleştir. Adres veya parola yazman gerekmiyor. Davet 24 saat geçerlidir ve tek cihaz içindir.</p><a href="https://github.com/srkntsn/M-MO/releases/latest">1. Uygulamayı indir</a><a id="activate" hidden>2. MİMO'yu etkinleştir</a><p id="status"></p><script>const code=location.hash.slice(1);if(/^[a-f0-9]{64}$/.test(code)){const a=document.getElementById('activate');a.href='mimo://activate?server='+encodeURIComponent(location.origin)+'&invite='+code;a.hidden=false}else{document.getElementById('status').textContent='Davet bağlantısı eksik. Gönderen kişiden yeni bağlantı iste.'}</script></html>`,{headers:{...noCache,'Content-Type':'text/html; charset=utf-8','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"}});
}
