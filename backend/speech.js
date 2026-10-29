export async function speechResponse(text, env) {
  if (!text || text.length > 1400) return Response.json({error:'Invalid speech text'},{status:400});
  const model=env.GEMINI_TTS_MODEL || 'gemini-2.5-flash-preview-tts';
  try {
    const response=await fetch('https://generativelanguage.googleapis.com/v1beta/models/'+encodeURIComponent(model)+':generateContent',{
      method:'POST',signal:AbortSignal.timeout(14000),
      headers:{'Content-Type':'application/json','x-goog-api-key':env.GEMINI_API_KEY},
      body:JSON.stringify({contents:[{parts:[{text:'Aşağıdaki metni doğal, sıcak ve akıcı bir Türkçeyle seslendir. Yalnızca metni oku, açıklama ekleme.\nMETİN:\n'+text}]}],
        generationConfig:{responseModalities:['AUDIO'],speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:'Aoede'}}}}})
    });
    if(!response.ok) return Response.json({error:'Speech unavailable'},{status:503});
    const result=await response.json();
    const data=(result.candidates?.[0]?.content?.parts || []).find(x=>x.inlineData)?.inlineData;
    if(!data || typeof data.data!=='string' || data.data.length>6000000) return Response.json({error:'Invalid speech output'},{status:502});
    const decoded=atob(data.data), pcm=Uint8Array.from(decoded,x=>x.charCodeAt(0));
    if(data.mimeType?.startsWith('audio/wav')) return new Response(pcm,{headers:{'Content-Type':'audio/wav','Cache-Control':'no-store'}});
    if(!data.mimeType?.startsWith('audio/L16') && !data.mimeType?.startsWith('audio/l16') && !data.mimeType?.startsWith('audio/pcm')) return Response.json({error:'Unsupported speech format'},{status:502});
    const rate=Number(/rate=(\d+)/.exec(data.mimeType)?.[1] || 24000);
    if(rate<8000 || rate>48000 || pcm.length%2) return Response.json({error:'Invalid speech format'},{status:502});
    const wav=new Uint8Array(44+pcm.length), view=new DataView(wav.buffer);
    const str=(offset,s)=>[...s].forEach((c,i)=>wav[offset+i]=c.charCodeAt(0));
    str(0,'RIFF');view.setUint32(4,36+pcm.length,true);str(8,'WAVE');str(12,'fmt ');
    view.setUint32(16,16,true);view.setUint16(20,1,true);view.setUint16(22,1,true);
    view.setUint32(24,rate,true);view.setUint32(28,rate*2,true);view.setUint16(32,2,true);view.setUint16(34,16,true);
    str(36,'data');view.setUint32(40,pcm.length,true);wav.set(pcm,44);
    return new Response(wav,{headers:{'Content-Type':'audio/wav','Cache-Control':'no-store'}});
  } catch (_) { return Response.json({error:'Speech timeout'},{status:504}); }
}
