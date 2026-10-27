import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() => runApp(const MimoApp());

class MimoApp extends StatelessWidget {
  const MimoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MİMO AI',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B1426),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF66D9FF), brightness: Brightness.dark),
    ),
    home: const MimoHome(),
  );
}

class MimoHome extends StatefulWidget {
  const MimoHome({super.key});
  @override
  State<MimoHome> createState() => _MimoHomeState();
}

class _MimoHomeState extends State<MimoHome> {
  final stt.SpeechToText speech = stt.SpeechToText();
  final FlutterTts tts = FlutterTts();
  final TextEditingController input = TextEditingController();
  Timer? blinkTimer;
  bool blinking = false;
  bool listening = false;
  bool talking = false;
  bool autoListen = true;
  bool processing = false;
  Timer? relistenTimer;
  String face = 'normal';
  String response = 'Merhaba! Ben MİMO. Konuşmak için mikrofona dokun.';
  String heard = '';

  @override
  void initState() {
    super.initState();
    tts.setLanguage('tr-TR');
    tts.setSpeechRate(0.48);
    tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() { talking = false; processing = false; });
      scheduleListen();
    });
    Future.delayed(const Duration(seconds: 1), startListening);
    blinkTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || face == 'sleep') return;
      setState(() => blinking = true);
      await Future.delayed(const Duration(milliseconds: 170));
      if (mounted) setState(() => blinking = false);
    });
  }

  void scheduleListen() {
    relistenTimer?.cancel();
    if (mounted && autoListen && !talking && !processing) {
      relistenTimer = Timer(const Duration(milliseconds: 900), startListening);
    }
  }

  Future<void> startListening() async {
    if (!mounted || !autoListen || talking || listening || processing) return;
    try {
      final available = await speech.initialize(
        onError: (e) {
          if (!mounted) return;
          setState(() => listening = false);
          if (e.permanent) {
            setState(() { autoListen = false; response = 'Mikrofon iznini veya ses tanıma hizmetini kontrol et.'; });
          } else { scheduleListen(); }
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' || status == 'done') {
            setState(() => listening = false);
            if (!processing && heard.trim().isNotEmpty) {
              final message = heard;
              heard = '';
              reply(message);
            } else { scheduleListen(); }
          }
        },
      );
      if (!available || !mounted) return;
      heard = '';
      await speech.listen(
        localeId: 'tr_TR',
        listenFor: const Duration(seconds: 25),
        pauseFor: const Duration(seconds: 3),
        onResult: (r) {
          if (!mounted || processing) return;
          heard = r.recognizedWords;
          setState(() => response = 'Duyduğum: ${r.recognizedWords}');
          if (r.finalResult && heard.trim().isNotEmpty) {
            final message = heard;
            heard = '';
            reply(message);
          }
        },
      );
      if (mounted) setState(() => listening = speech.isListening);
    } catch (_) { scheduleListen(); }
  }

  String moodFor(String text) {
    final q = text.toLowerCase();
    if (RegExp(r'üzgün|mutsuz|ağlı|kötüyüm|canım sıkkın').hasMatch(q)) return 'sad';
    if (RegExp(r'mutlu|harika|süper|sevindim|teşekkür|güzel').hasMatch(q)) return 'happy';
    if (RegExp(r'şaşır|inanamıyorum|vay be').hasMatch(q)) return 'surprised';
    return 'normal';
  }

  Future<void> speak(String answer) async {
    if (speech.isListening) await speech.stop();
    await tts.stop();
    if (!mounted) return;
    setState(() { response = answer; talking = true; });
    await tts.speak(answer);
  }

  String answerFor(String message) {
    final q = message.toLowerCase().trim();
    if (q.contains('merhaba') || q.contains('selam')) return 'Merhaba! Seninle tanıştığıma sevindim.';
    if (q.contains('nasılsın')) return 'Çok iyiyim! Senin günün nasıl geçiyor?';
    if (q.contains('adın ne') || q.contains('kimsin')) return 'Ben MİMO. Senin sanal robot arkadaşınım.';
    if (q.contains('saat')) {
      final n = DateTime.now();
      return 'Şu anda saat ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}.';
    }
    if (q.contains('teşekkür')) return 'Ne demek! Seninle sohbet etmek çok güzel.';
    if (q.contains('mutlu')) { setState(() => face = 'happy'); return 'Ben de mutluyum!'; }
    if (q.contains('uyu') || q.contains('uyku')) { setState(() => face = 'sleep'); return 'Peki, biraz dinleniyorum.'; }
    if (q.contains('uyan')) { setState(() => face = 'normal'); return 'Uyandım! Buradayım.'; }
    return 'Seni duydum. Şu anda ilk sürümdeyim; gelişmiş yapay zekâ sohbetini yakında ekleyeceğiz.';
  }

  Future<void> reply(String message) async {
    if (message.trim().isEmpty || processing) return;
    processing = true;
    setState(() => face = moodFor(message));
    input.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    await speak(answerFor(message));
  }

  Future<void> toggleMic() async {
    setState(() => autoListen = !autoListen);
    if (autoListen) {
      scheduleListen();
    } else {
      relistenTimer?.cancel();
      await speech.stop();
      if (mounted) setState(() => listening = false);
    }
  }

  @override
  void dispose() {
    blinkTimer?.cancel();
    relistenTimer?.cancel();
    speech.stop();
    tts.stop();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eyeHeight = blinking || face == 'sleep' ? 9.0 : face == 'happy' ? 26.0 : face == 'sad' ? 45.0 : face == 'surprised' ? 75.0 : 65.0;
    return Scaffold(
      appBar: AppBar(title: const Text('MİMO AI'), centerTitle: true, backgroundColor: Colors.transparent),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Text('Senin dijital arkadaşın', style: TextStyle(color: Color(0xFF9AAFCB))),
              const Spacer(),
              Container(
                width: double.infinity,
                height: 260,
                decoration: BoxDecoration(
                  color: const Color(0xFF172A48),
                  borderRadius: BorderRadius.circular(64),
                  border: Border.all(color: const Color(0xFF4B789F), width: 3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      eye(eyeHeight), const SizedBox(width: 28), eye(eyeHeight),
                    ]),
                    const SizedBox(height: 18),
                    Text(face == 'happy' ? 'ᴗ' : face == 'sleep' ? '—' : face == 'sad' ? '︵' : face == 'surprised' ? '○' : talking ? '◯' : '⌣',
                      style: const TextStyle(fontSize: 40, color: Color(0xFF72DEFF))),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(response, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 18),
              Text(autoListen ? (listening ? 'Dinliyorum…' : talking ? 'Konuşuyorum…' : 'Otomatik dinleme açık') : 'Dinleme kapalı'),
              const Spacer(),
              FilledButton.icon(
                onPressed: toggleMic,
                icon: Icon(autoListen ? Icons.mic : Icons.mic_off),
                label: Text(autoListen ? 'Dinlemeyi kapat' : 'Dinlemeyi aç'),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(
                  controller: input,
                  onSubmitted: reply,
                  decoration: const InputDecoration(hintText: 'MİMO’ya yaz...', border: OutlineInputBorder()),
                )),
                IconButton(onPressed: () => reply(input.text), icon: const Icon(Icons.send)),
              ]),
              const SizedBox(height: 10),
              const Text('İlk sürüm: hazır yanıtlar • Bulut yapay zekâ henüz bağlı değil',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget eye(double height) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeInOut,
    width: 78, height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF6CDCFF),
      borderRadius: BorderRadius.circular(36),
      boxShadow: const [BoxShadow(color: Color(0x5551CFFF), blurRadius: 18)],
    ),
  );
}
