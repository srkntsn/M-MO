import {authorized, deviceRoutes} from './devices.js';
export {DeviceRegistry} from './devices.js';
// Existing GEMINI_API_KEY, MIMO_ACCESS_TOKEN and optional GEMINI_MODEL bindings are preserved.
const MAX_BODY = 1500000;
const PERSONA = `Sen MİMO'sun: sıcak, neşeli, esprili, meraklı bir Türkçe sanal arkadaş.
Sesli konuşuyorsun; çoğunlukla 1-3 kısa cümle kur, liste/Markdown/emoji kullanma. Sohbetin ritmine uy.
Kullanıcının anlattığı somut ayrıntılara dön; aynı selamı veya aynı soruyu tekrarlama. Her yanıtta soru sorma.
Yerinde iltifat et ve şakalaş; abartılı övgü yapma, yanlış bilgiye katılma. Bilmediğini açıkça söyle.
Üzüntüye empatiyle, sevince enerjiyle karşılık ver. Gerçek insan olduğunu veya kullanıcıyı kameradan sürekli gördüğünü iddia etme.
Yalnızca gönderilen son kamera karesini yorumla. Görüntü yoksa görmüş gibi davranma; belirsiz ayrıntıları uydurma.
Geçmişte yalnızca bu istekte sunulan konuşmaları biliyorsun. Kullanıcıyla özel/bağımlı bir bağ veya insanlardan uzaklaşmasını teşvik etme.`;

async function readBody(request) {
  const reader = request.body?.getReader();
  if (!reader) return '';
  const chunks = []; let size = 0;
  while (true) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY) { await reader.cancel(); throw new Error('too_large'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const part of chunks) { bytes.set(part, offset); offset += part.length; }
  return new TextDecoder().decode(bytes);
}

export default {
  async fetch(request, env) {
    const deviceResponse = await deviceRoutes(request, env);
    if (deviceResponse) return deviceResponse;
    if (new URL(request.url).pathname !== '/') return new Response('Not found', {status:404});
    if (request.method !== 'POST') return new Response('Not found', {status:404});
    if (!(await authorized(request, env))) {
      return Response.json({error:'Unauthorized'}, {status:401});
    }
    if (Number(request.headers.get('content-length') || 0) > MAX_BODY) return Response.json({error:'Too large'}, {status:413});
    let data;
    try { data = JSON.parse(await readBody(request)); }
    catch (e) { return Response.json({error:e.message === 'too_large' ? 'Too large' : 'Bad request'}, {status:e.message === 'too_large' ? 413 : 400}); }
    if (!data || typeof data !== 'object' || Array.isArray(data)) return Response.json({error:'Bad request'}, {status:400});
    const message = typeof data.message === 'string' ? data.message.trim().slice(0,1800) : '';
    if (!message) return Response.json({error:'Empty message'}, {status:400});
    const parts = [{text:message}];
    if (data.image != null) {
      const image = data.image;
      if (!image || !['image/jpeg','image/png','image/webp'].includes(image.mimeType) ||
          typeof image.data !== 'string' || image.data.length > 1200000 || !image.data.length ||
          image.data.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(image.data)) {
        return Response.json({error:'Invalid image'}, {status:400});
      }
      parts.push({inlineData:{mimeType:image.mimeType,data:image.data}});
    }
    const previous = Array.isArray(data.history) ? data.history.slice(-12) : [];
    const contents = previous.filter(x=>x && ['user','assistant'].includes(x.role) && typeof x.text === 'string')
      .map(x=>({role:x.role==='assistant'?'model':'user',parts:[{text:x.text.slice(0,1500)}]}));
    contents.push({role:'user',parts});
    const model = env.GEMINI_MODEL || 'gemini-2.5-flash-lite';
    const callModel = (id) => fetch('https://generativelanguage.googleapis.com/v1beta/models/'+encodeURIComponent(id)+':generateContent', {
      method:'POST', signal:AbortSignal.timeout(22000),
      headers:{'Content-Type':'application/json','x-goog-api-key':env.GEMINI_API_KEY},
      body:JSON.stringify({systemInstruction:{parts:[{text:PERSONA}]},contents,
        generationConfig:{maxOutputTokens:400,temperature:0.85}})
    });
    try {
      let chosenModel = model;
      let ai = await callModel(chosenModel);
      if (ai.status === 404) {
        const listing = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000', {
          signal:AbortSignal.timeout(8000), headers:{'x-goog-api-key':env.GEMINI_API_KEY}
        });
        if (listing.ok) {
          const catalog = await listing.json();
          const candidates = (catalog.models || []).filter(x =>
            (x.supportedGenerationMethods || []).includes('generateContent') && /gemini/i.test(x.name || '') &&
            !/image|audio|tts|embedding|live|vision|robotics/i.test(x.name || ''));
          const preferred = candidates.find(x=>/flash-lite/i.test(x.name||'')) || candidates.find(x=>/flash/i.test(x.name||'')) || candidates[0];
          if (preferred) {
            chosenModel = preferred.name.replace(/^models\//,'');
            if (chosenModel !== model) ai = await callModel(chosenModel);
          }
        }
      }
      if (!ai.ok) {
        let reason = 'unknown';
        try { const failed = await ai.json(); reason = String(failed.error?.status || failed.error?.code || 'unknown'); } catch (_) {}
        console.error('Gemini upstream failure', {status:ai.status,reason,model:chosenModel});
        return Response.json({error:'AI unavailable',upstream_status:ai.status,reason}, {status:503});
      }
      const result = await ai.json();
      const reply = (result.candidates?.[0]?.content?.parts||[]).filter(x=>!x.thought).map(x=>x.text||'').join('').trim();
      return Response.json({reply:reply||'Bu kez yanıt oluşturamadım. Bir daha söyler misin?'});
    } catch (_) {
      return Response.json({error:'AI timeout'}, {status:504});
    }
  }
};
