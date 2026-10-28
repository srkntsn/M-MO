// Cloudflare Workers: deploy this file, then set GEMINI_API_KEY and MIMO_ACCESS_TOKEN as secrets.
// Do not publish those values or place them in the Android application.
export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return new Response('Not found', {status:404});
    const auth = request.headers.get('Authorization') || '';
    if (!env.MIMO_ACCESS_TOKEN || auth !== 'Bearer ' + env.MIMO_ACCESS_TOKEN) {
      return Response.json({error:'Unauthorized'}, {status:401});
    }
    const size = Number(request.headers.get('content-length') || 0);
    if (size > 12000) return Response.json({error:'Too large'}, {status:413});
    let data;
    try { data = await request.json(); } catch { return Response.json({error:'Bad request'}, {status:400}); }
    const message = typeof data.message === 'string' ? data.message.trim().slice(0,1800) : '';
    if (!message) return Response.json({error:'Empty message'}, {status:400});
    const previous = Array.isArray(data.history) ? data.history.slice(-10) : [];
    const contents = previous.filter(x=>x && ['user','assistant'].includes(x.role) && typeof x.text === 'string')
      .map(x=>({role:x.role==='assistant'?'model':'user',parts:[{text:x.text.slice(0,1500)}]}));
    contents.push({role:'user',parts:[{text:message}]});
    const model = env.GEMINI_MODEL || 'gemini-2.5-flash-lite';
    const callModel = (id) => fetch('https://generativelanguage.googleapis.com/v1beta/models/'+encodeURIComponent(id)+':generateContent', {
      method:'POST',
      headers:{'Content-Type':'application/json','x-goog-api-key':env.GEMINI_API_KEY},
      body:JSON.stringify({
        systemInstruction:{parts:[{text:'Sen MİMO isimli sıcak, canlı ve saygılı bir Türkçe sanal arkadaşsın. Kısa, doğal ve açık Türkçe konuş. Gerçek bir insan olduğunu iddia etme. Kullanıcıyla konuşmalarını hatırladığın kadar bağlam içinde tut. Kişisel veya gizli bilgileri isteme.'}]},
        contents,
        generationConfig:{maxOutputTokens:320,temperature:0.75}
      })
    });
    let chosenModel = model;
    let ai = await callModel(chosenModel);
    if (ai.status === 404) {
      // Use the API key's actual accessible models rather than guessing IDs.
      const listing = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000', {
        headers: {'x-goog-api-key':env.GEMINI_API_KEY}
      });
      if (listing.ok) {
        const catalog = await listing.json();
        const candidates = (catalog.models || []).filter(x =>
          (x.supportedGenerationMethods || []).includes('generateContent') &&
          /gemini/i.test(x.name || '') &&
          !/image|audio|tts|embedding|live|vision|robotics/i.test(x.name || '')
        );
        const preferred = candidates.find(x=>/flash-lite/i.test(x.name||'')) ||
          candidates.find(x=>/flash/i.test(x.name||'')) || candidates[0];
        if(preferred) {
          chosenModel = preferred.name.replace(/^models\//,'');
          if(chosenModel !== model) ai = await callModel(chosenModel);
        }
      } else {
        console.error('Gemini model list failure', {status: listing.status});
      }
    }
    if(!ai.ok) {
      let reason = 'unknown';
      try {
        const failed = await ai.json();
        reason = String(failed.error?.status || failed.error?.code || 'unknown');
      } catch (_) {}
      console.error('Gemini upstream failure', {status: ai.status, reason, model:chosenModel});
      return Response.json({error:'AI unavailable', upstream_status:ai.status, reason}, {status:503});
    }
    const result=await ai.json();
    const reply=(result.candidates?.[0]?.content?.parts||[]).map(x=>x.text||'').join('').trim();
    return Response.json({reply:reply||'Şu anda yanıt oluşturamadım.'});
  }
};
