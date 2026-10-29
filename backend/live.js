// Gemini Live relay. The API key never leaves the Worker; existing auth applies.
const UPSTREAM = 'https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
export const LIVE_TOOLS = ['capture_camera', 'open_settings', 'sleep', 'forget', 'check_update'];
export function liveSetup(model, persona, handle) {
  return {setup:{model:`models/${model}`,generationConfig:{responseModalities:['AUDIO'],maxOutputTokens:512,speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:'Aoede'}}}},
    systemInstruction:{parts:[{text:persona+`\nCanlı sesli sohbettesin. Kullanıcı konuşmaya başlayınca sus ve dinle. Türkçe konuş. Doğal duraklamalarına alan tanı. Kamera yalnızca kullanıcı açıkça görmeni, okumanı veya kamerayı açmanı istediğinde capture_camera aracıyla tek kare alınır. Görüntü almadan gördüğünü söyleme. Ayarlar, uyku, geçmiş silme ve güncelleme isteklerinde ilgili aracı kullan. Uyurken ses alamazsın; uyanmak için yüze dokunulur.`}]},
    realtimeInputConfig:{automaticActivityDetection:{disabled:false,prefixPaddingMs:300,silenceDurationMs:800},activityHandling:'START_OF_ACTIVITY_INTERRUPTS'},
    inputAudioTranscription:{},outputAudioTranscription:{},contextWindowCompression:{slidingWindow:{}},sessionResumption:handle?{handle}:{},
    tools:[{functionDeclarations:[
      {name:'capture_camera',description:'Yalnızca kullanıcının açık kamera/görme/okuma isteği üzerine tek fotoğraf al.',parameters:{type:'OBJECT',properties:{lens:{type:'STRING',enum:['front','back']}},required:['lens']}},
      ...LIVE_TOOLS.slice(1).map(name=>({name,description:{open_settings:'Bağlantı ayarlarını aç.',sleep:'Kullanıcı dinlemeyi kapatmak veya uyutmak istedi.',forget:'Kullanıcı sohbet geçmişini silmek istedi.',check_update:'Yeni uygulama sürümünü kontrol et.'}[name]}))
    ]}]}};
}
export function clientPacket(data, pending) {
  if(data instanceof ArrayBuffer) {
    if(data.byteLength===0 || data.byteLength>3200 || data.byteLength%2) throw Error('bad_audio');
    let bytes='';for(const b of new Uint8Array(data))bytes+=String.fromCharCode(b);
    return {realtimeInput:{audio:{mimeType:'audio/pcm;rate=16000',data:btoa(bytes)}}};
  }
  if(typeof data!=='string' || data.length>1201000) throw Error('bad_packet');
  const p=JSON.parse(data);
  if(p.type==='image' && typeof p.data==='string' && p.data.length<=1200000 && p.data.length%4===0 && /^[A-Za-z0-9+/]+={0,2}$/.test(p.data))
    return {realtimeInput:{video:{mimeType:'image/jpeg',data:p.data}}};
  if(p.type==='tool' && pending.has(p.id) && typeof p.result==='string' && p.result.length<=1000) {
    const name=pending.get(p.id);pending.delete(p.id);
    return {toolResponse:{functionResponses:[{id:p.id,name,response:{result:p.result}}]}};
  }
  throw Error('bad_packet');
}
export async function chooseLiveModel(env) {
  if(env.GEMINI_LIVE_MODEL && /^[\w.-]{1,100}$/.test(env.GEMINI_LIVE_MODEL)) return env.GEMINI_LIVE_MODEL;
  const r=await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000',{headers:{'x-goog-api-key':env.GEMINI_API_KEY},signal:AbortSignal.timeout(8000)});
  if(!r.ok) throw Error('live_catalog');
  const models=(await r.json()).models||[];
  const live=models.filter(m=>(m.supportedGenerationMethods||[]).some(x=>/bidigeneratecontent/i.test(x)) && !/transcri|translat|thinking/i.test(m.name));
  const selected=live.find(m=>m.name==='models/gemini-3.8-live') || live.find(m=>/native-audio/.test(m.name)) || live.find(m=>/flash.*live/.test(m.name)) || live[0];
  if(!selected) throw Error('live_unavailable');
  return selected.name.replace(/^models\//,'');
}
export async function liveResponse(request,env,persona) {
  if(request.headers.get('Upgrade')?.toLowerCase()!=='websocket')return Response.json({error:'WebSocket required'},{status:426});
  if(!env.GEMINI_API_KEY)return Response.json({error:'Live not configured'},{status:503});
  let upstream,model;
  try {
    model=await chooseLiveModel(env);
    const r=await fetch(UPSTREAM,{headers:{Upgrade:'websocket','x-goog-api-key':env.GEMINI_API_KEY},signal:AbortSignal.timeout(12000)});
    upstream=r.webSocket;
    if(!upstream)return Response.json({error:'Live unavailable',upstream_status:r.status},{status:503});
    upstream.accept();
  }catch(_){return Response.json({error:'Live unavailable'},{status:503});}
  const pair=new WebSocketPair(),client=pair[0],server=pair[1];server.accept();
  let initialized=false,ready=false,closed=false,received=0,windowStart=Date.now();
  const pending=new Map();
  const send=p=>{if(!closed)server.send(JSON.stringify(p));};
  const close=(code=1000,reason='closed')=>{if(closed)return;closed=true;clearTimeout(setupTimer);clearTimeout(lifetime);try{server.close(code,reason);}catch(_){}try{upstream.close(1000,'closed');}catch(_){} };
  const setupTimer=setTimeout(()=>close(1011,'live_setup_timeout'),18000);
  const lifetime=setTimeout(()=>close(1000,'session_limit'),60*60*1000);
  server.addEventListener('message',e=>{
    try {
      const now=Date.now();if(now-windowStart>=1000){received=0;windowStart=now;}
      received+=typeof e.data==='string'?e.data.length:e.data.byteLength;
      if(received>1500000)throw Error('rate');
      if(!initialized){
        const p=JSON.parse(e.data);if(p.type!=='start' || (p.handle!=null && (typeof p.handle!=='string'||p.handle.length>4096)))throw Error('start');
        initialized=true;upstream.send(JSON.stringify(liveSetup(model,persona,p.handle)));return;
      }
      if(!ready)throw Error('not_ready');
      upstream.send(JSON.stringify(clientPacket(e.data,pending)));
    }catch(_){close(1008,'invalid_live_message');}
  });
  upstream.addEventListener('message',async e=>{
    try {
      const raw=typeof e.data==='string'?e.data:new TextDecoder().decode(e.data);
      const p=JSON.parse(raw);
      if(p.setupComplete){ready=true;clearTimeout(setupTimer);send({type:'ready',model});}
      if(p.error){send({type:'error',code:'live_upstream'});close(1008,'live_upstream');return;}
      const s=p.serverContent;
      if(s){
        if(s.interrupted)send({type:'interrupt'});
        for(const part of s.modelTurn?.parts||[]){const a=part.inlineData;if(a?.mimeType?.startsWith('audio/pcm') && typeof a.data==='string')send({type:'audio',data:a.data});}
        if(s.outputTranscription?.text)send({type:'transcript',text:s.outputTranscription.text.slice(0,4000)});
        if(s.turnComplete)send({type:'turn'});
      }
      for(const f of p.toolCall?.functionCalls||[]){if(LIVE_TOOLS.includes(f.name)&&typeof f.id==='string'&&pending.size<8){pending.set(f.id,f.name);send({type:'tool',id:f.id,name:f.name,args:f.args||{}});}}
      for(const id of p.toolCallCancellation?.ids||[])pending.delete(id);
      if(p.sessionResumptionUpdate?.resumable && p.sessionResumptionUpdate.newHandle)send({type:'resume',handle:p.sessionResumptionUpdate.newHandle});
      if(p.goAway)send({type:'reconnect'});
    }catch(_){close(1011,'live_protocol');}
  });
  server.addEventListener('close',()=>close());server.addEventListener('error',()=>close(1011));
  upstream.addEventListener('close',e=>close([1007,1008].includes(e.code)?1008:1012,'live_disconnected'));
  upstream.addEventListener('error',()=>close(1011,'live_network'));
  return new Response(null,{status:101,webSocket:client});
}
