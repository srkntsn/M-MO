import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'face.dart';
import 'invitations.dart';
import 'camera_image.dart';
import 'avatar.dart';
import 'neural_voice.dart';
import 'updater.dart';
import 'providers.dart';
import 'recognition_turn.dart';

final appLinks = AppLinks();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MimoApp());
}

class MimoApp extends StatelessWidget {
  const MimoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MİMO',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true)
            .copyWith(scaffoldBackgroundColor: const Color(0xFF060D1A)),
        home: const MimoHome(),
      );
}

class MimoHome extends StatefulWidget {
  const MimoHome({super.key});
  @override
  State<MimoHome> createState() => _MimoHomeState();
}

class _MimoHomeState extends State<MimoHome> with WidgetsBindingObserver {
  final speech = stt.SpeechToText();
  final tts = FlutterTts();
  final neuralVoice = NeuralVoice();
  final updater = AppUpdater();
  CustomAI? customAI;
  final history = <Map<String, String>>[];
  final inviteAccess = InviteAccess();
  StreamSubscription<Uri>? linkSubscription;
  Uri? pendingInvite;
  bool booting = true;
  bool permissionFlow = false;
  String endpoint = '', token = '', mood = 'warm';
  FaceMode mode = FaceMode.idle;
  double energy = 0;
  bool active = true,
      settingsOpen = false,
      sleeping = false,
      busy = false,
      speechReady = false,
      starting = false;
  bool microphoneBlocked = false, preparingSpeech = false;
  int generation = 0, listenId = 0, failures = 0;
  Timer? restart, settle, watchdog, listeningHealth;
  final recognitionTurn = RecognitionTurn();
  DateTime lastListenRequest = DateTime.fromMillisecondsSinceEpoch(0);
  bool cloudVoice = false;
  HttpClient? inFlight;
  CameraController? camera;
  String heard = '';
  String speechWord = '';
  int speechOffset = 0;
  bool get canListen =>
      mounted &&
      active &&
      !settingsOpen &&
      !sleeping &&
      !busy &&
      !microphoneBlocked &&
      speechReady &&
      !booting &&
      !permissionFlow &&
      mode != FaceMode.speaking;
  void display(FaceMode value) {
    if (mounted) setState(() => mode = value);
  }

  bool valid(int id) => mounted && active && !settingsOpen && generation == id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    linkSubscription = appLinks.uriLinkStream.listen(
      receiveInvite,
      onError: (Object _) {
        display(FaceMode.error);
      },
    );
    listeningHealth = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!canListen ||
          starting ||
          speech.isListening ||
          (settle?.isActive ?? false) ||
          (restart?.isActive ?? false)) return;
      if (DateTime.now().difference(lastListenRequest).inMilliseconds > 1000)
        schedule();
    });
    boot();
  }

  Future<void> boot() async {
    final prefs = await SharedPreferences.getInstance();
    cloudVoice = prefs.getBool('cloud_voice') ?? false;
    endpoint = prefs.getString('endpoint') ?? '';
    token = prefs.getString('access') ?? '';
    final credential = await inviteAccess.load();
    if (credential != null) {
      endpoint = credential['endpoint']!;
      token = credential['token']!;
    } else if (token.isNotEmpty) {
      await inviteAccess.save(endpoint, token);
    }
    await prefs.remove('access');
    pendingInvite ??= await appLinks.getInitialLink();
    try {
      final saved = jsonDecode(prefs.getString('conversation') ?? '[]');
      if (saved is List) {
        for (final item in saved.take(12)) {
          if (item is Map &&
              ['user', 'assistant'].contains(item['role']) &&
              item['text'] is String) {
            history.add({
              'role': item['role'] as String,
              'text': item['text'] as String,
            });
          }
        }
      }
    } catch (_) {
      /* Ignore an invalid local history. */
    }
    await tts.setLanguage('tr-TR');
    await tts.setSpeechRate(.49);
    await tts.setPitch(1.0);
    await tts.awaitSpeakCompletion(true);
    final voice = prefs.getString('voice');
    if (voice != null) {
      final list = await tts.getVoices;
      if (list is List) {
        final matches = list.whereType<Map>().where((x) => x['name'] == voice);
        if (matches.isNotEmpty)
          await tts.setVoice({
            'name': voice,
            'locale': matches.first['locale'].toString(),
          });
      }
    }
    tts.setProgressHandler((text, start, end, word) {
      if (mounted && mode == FaceMode.speaking)
        setState(() {
          speechWord = word;
          speechOffset = start;
          energy = .5 + (word.length % 5) / 10;
        });
    });
    if (!mounted) return;
    await explainPermissions();
    if (!mounted) return;
    booting = false;
    if (pendingInvite != null) {
      final link = pendingInvite!;
      pendingInvite = null;
      await activateInvitation(link);
      return;
    }
    if (endpoint.isEmpty || token.isEmpty) {
      await openSettings();
      return;
    }
    await prepareSpeech();
    if (mounted && active && !settingsOpen) {
      await say(
        'Merhaba, buradayım! Benimle doğrudan konuşabilirsin. Konuşmamı kesmek için yüzüme dokun. Kamera için, kameraya bak demen yeterli.',
      );
      schedule();
      unawaited(checkUpdate(automatic: true));
    }
  }

  Future<void> prepareSpeech() async {
    if (preparingSpeech) return;
    preparingSpeech = true;
    try {
      if (!(await Permission.microphone.isGranted)) {
        microphoneBlocked = true;
        speechReady = false;
        display(FaceMode.error);
        return;
      }
      try {
        speechReady = await speech.initialize(
          onError: (e) {
            if (!mounted || !active || settingsOpen || busy) return;
            if (e.errorMsg.contains('permission')) {
              microphoneBlocked = true;
              display(FaceMode.error);
            } else if (e.errorMsg.contains('not_available')) {
              speechReady = false;
              recoverSpeech();
            } else {
              if (!e.errorMsg.contains('no_match') &&
                  !e.errorMsg.contains('speech_timeout')) failures++;
              finishRecognition();
            }
          },
          onStatus: (status) {
            if (!mounted || !active || settingsOpen || busy) return;
            if (status == 'done' || status == 'notListening')
              finishRecognition();
          },
        );
        microphoneBlocked = false;
      } catch (_) {
        speechReady = false;
      }
      if (!speechReady && !microphoneBlocked) recoverSpeech();
      if (microphoneBlocked) display(FaceMode.error);
    } finally {
      preparingSpeech = false;
    }
  }

  void recoverSpeech() {
    if (!mounted || !active || settingsOpen || sleeping || microphoneBlocked)
      return;
    restart?.cancel();
    restart = Timer(const Duration(seconds: 3), resumeListening);
  }

  void finishRecognition() {
    if (!canListen) return;
    if (settle?.isActive ?? false) return;
    final session = listenId;
    settle = Timer(const Duration(milliseconds: 650), () => consume(session));
  }

  Future<void> stopRecognition() async {
    try {
      await speech.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {/* A stalled platform call must not hold the conversation. */}
  }

  void schedule() {
    restart?.cancel();
    if (!canListen) return;
    final delay = failures == 0 ? 250 : (400 * (1 + failures.clamp(0, 3)));
    restart = Timer(Duration(milliseconds: delay), listen);
  }

  Future<void> listen() async {
    if (!canListen || speech.isListening || starting) return;
    starting = true;
    final session = recognitionTurn.begin();
    listenId = session;
    lastListenRequest = DateTime.now();
    heard = '';
    try {
      display(FaceMode.listening);
      await speech
          .listen(
            listenOptions: stt.SpeechListenOptions(
              localeId: 'tr_TR',
              listenFor: const Duration(seconds: 30),
              pauseFor: const Duration(seconds: 2),
              partialResults: true,
              cancelOnError: false,
              listenMode: stt.ListenMode.dictation,
            ),
            onSoundLevelChange: (level) {
              if (mounted && mode == FaceMode.listening)
                setState(() => energy = ((level + 2) / 12).clamp(0.0, 1.0));
            },
            onResult: (r) {
              if (!canListen || session != listenId) return;
              heard = r.recognizedWords;
              recognitionTurn.update(session, heard);
              if (r.finalResult) consume(session);
            },
          )
          .timeout(const Duration(seconds: 4));
      if (!canListen || session != listenId) {
        await stopRecognition();
        return;
      }
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 34), () async {
        if (session != listenId || !canListen) return;
        try {
          await speech.stop().timeout(const Duration(seconds: 2));
        } catch (_) {}
        consume(session);
      });
      if (!speech.isListening) schedule();
    } catch (_) {
      failures++;
      schedule();
    } finally {
      starting = false;
    }
  }

  void consume(int session) {
    if (!canListen || session != listenId) return;
    settle?.cancel();
    watchdog?.cancel();
    final text = recognitionTurn.take(session);
    heard = '';
    if (text == null) {
      schedule();
      return;
    }
    failures = 0;
    unawaited(respond(text));
  }

  Future<void> say(String text) async {
    if (!mounted || !active || settingsOpen) return;
    await stopRecognition();
    if (!mounted || !active || settingsOpen) return;
    final spokenGeneration = generation;
    speechWord = '';
    energy = 0;
    display(FaceMode.speaking);
    try {
      final server = Uri.tryParse(endpoint);
      if (cloudVoice && server != null && token.isNotEmpty) {
        final played = await neuralVoice.speak(server, token, text, (level) {
          if (valid(spokenGeneration) && mode == FaceMode.speaking)
            setState(() => energy = level);
        });
        if (!valid(spokenGeneration) || played) return;
      }
      final speechLimit =
          Duration(seconds: (text.length / 10 + 5).ceil().clamp(6, 55));
      await tts.speak(text).timeout(speechLimit);
    } catch (_) {
      await tts.stop();
    } finally {
      if (valid(spokenGeneration) && mode == FaceMode.speaking)
        display(FaceMode.idle);
    }
  }

  CameraLensDirection preferredLens = CameraLensDirection.back;
  Future<Map<String, dynamic>?> capture(int id) async {
    // Camera opens only after an explicit voice command, not during normal chat.
    await say(
      preferredLens == CameraLensDirection.front
          ? 'Ön kamerayla bir kare alıyorum.'
          : 'Arka kamerayı göstermek istediğin şeye çevir.',
    );
    if (!valid(id)) return null;
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('no_camera');
    final matches = cameras.where((x) => x.lensDirection == preferredLens);
    if (matches.isEmpty) throw StateError('camera_missing');
    if (!(await Permission.camera.isGranted))
      throw StateError('camera_permission');
    final selected = matches.first;
    final controller = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    camera = controller;
    XFile? picture;
    try {
      await controller.initialize();
      if (!valid(id)) return null;
      display(FaceMode.camera);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!valid(id)) return null;
      picture = await controller.takePicture();
      final bytes = await compute(
        prepareCameraImage,
        await picture.readAsBytes(),
      );
      if (!valid(id)) return null;
      return {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)};
    } finally {
      if (identical(camera, controller)) {
        camera = null;
        await controller.dispose();
      }
      if (picture != null) {
        try {
          await File(picture.path).delete();
        } catch (_) {}
      }
    }
  }

  Future<String> ask(
    String message,
    int id, {
    Map<String, dynamic>? image,
  }) async {
    customAI = await CustomAI.load();
    if (customAI != null) {
      try {
        final reply = await customAI!.ask(message, history, image: image);
        if (valid(id)) {
          history.add({
            'role': 'user',
            'text':
                image != null ? '$message [Kamera karesi paylaşıldı.]' : message
          });
          history.add({'role': 'assistant', 'text': reply});
          if (history.length > 12) history.removeRange(0, history.length - 12);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('conversation', jsonEncode(history));
        }
        return reply;
      } catch (e) {
        return e is FormatException
            ? e.message
            : 'Kendi yapay zekâ bağlantın yanıt vermedi. Gelişmiş ayarlardan hazır hizmete dönebilirsin.';
      }
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        token.isEmpty) {
      return 'Bağlantı ayarlarımı tamamlayalım. Yüzüme uzun basarak ayarları açabilirsin.';
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    inFlight = client;
    try {
      final request =
          await client.postUrl(uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $token');
      request.add(
        utf8.encode(
          jsonEncode({
            'message': message,
            'history': history,
            if (image != null) 'image': image,
          }),
        ),
      );
      final response = await request.close().timeout(
            const Duration(seconds: 32),
          );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 401)
        return 'Sunucu erişim parolam eşleşmiyor. Bağlantı ayarlarını kontrol edelim.';
      if (response.statusCode == 429)
        return 'Biraz hızlı konuştuk! Kısa bir ara verip tekrar deneyelim.';
      if (response.statusCode == 413)
        return 'Sunucu fotoğrafı boyutu nedeniyle kabul etmedi. Otomatik tekrar denemiyorum; dinlemeye dönüyorum.';
      if (response.statusCode != 200)
        return image != null
            ? 'Kamerayı şu anda yorumlayamadım. Sunucunun kamera destekli yeni sürümde olduğundan emin olalım.'
            : 'Şu an yapay zekâ servisine ulaşamadım. Biraz sonra yeniden deneyelim.';
      final result = jsonDecode(body);
      final reply = result is Map ? result['reply'] : null;
      if (reply is! String || reply.trim().isEmpty)
        return 'Yanıtı anlayamadım. Tekrar dener misin?';
      if (valid(id)) {
        history.add({
          'role': 'user',
          'text': image != null
              ? '$message [Kamera karesi paylaşıldı; görüntü saklanmadı.]'
              : message,
        });
        history.add({'role': 'assistant', 'text': reply});
        if (history.length > 12) history.removeRange(0, history.length - 12);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('conversation', jsonEncode(history));
      }
      return reply;
    } catch (_) {
      return 'Bağlantım koptu. İnterneti kontrol edip yeniden konuşabiliriz.';
    } finally {
      client.close(force: true);
      if (identical(inFlight, client)) inFlight = null;
    }
  }

  String normalize(String text) =>
      text.toLowerCase().replaceAll('İ', 'i').replaceAll('ı', 'i');
  Future<void> respond(String message) async {
    if (busy || !active || settingsOpen) return;
    busy = true;
    final id = ++generation;
    restart?.cancel();
    settle?.cancel();
    watchdog?.cancel();
    await stopRecognition();
    try {
      if (!valid(id)) return;
      final q = normalize(message);
      if (RegExp(r'^(mimo[ ,]*)?(uyu|uyku modu|dinlen|dinlemeyi kapat)[.!?]*$')
          .hasMatch(q)) {
        sleeping = true;
        await say(
          'Biraz dinleniyorum. Yeniden konuşmak için yüzüme dokunman yeterli.',
        );
        if (valid(id)) display(FaceMode.sleeping);
        return;
      }
      if (q.contains('geçmişi unut') ||
          q.contains('gecmisi unut') ||
          q.contains('sohbeti sil')) {
        history.clear();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('conversation');
        await say(
          'Bu cihazdaki sohbet geçmişini sildim. Yeni bir başlangıç yapalım.',
        );
        return;
      }
      if (q.contains('ayarlari aç') || q.contains('ayarlari ac')) {
        await openSettings();
        return;
      }
      if (q.contains('güncelle') ||
          q.contains('guncelle') ||
          q.contains('yeni sürümü aç') ||
          q.contains('yeni surumu ac')) {
        await checkUpdate();
        return;
      }
      final wantsCamera = RegExp(
        r'kameraya bak|kamerayi aç|kamerayi ac|kamera aç|kamera ac|ön kamera|on kamera|arka kamera|beni görebiliyor|beni gorebiliyor|bana bak|buna bak|şuna bak|suna bak|bunu anlat|şunu anlat|sunu anlat|ne görüyorsun|ne goruyorsun|bunu oku',
      ).hasMatch(q);
      Map<String, dynamic>? image;
      if (wantsCamera) {
        if (q.contains('ön kamera') ||
            q.contains('on kamera') ||
            q.contains('beni gör') ||
            q.contains('beni gor') ||
            q.contains('bana bak')) {
          preferredLens = CameraLensDirection.front;
        } else if (q.contains('arka kamera')) {
          preferredLens = CameraLensDirection.back;
        }
        try {
          image = await capture(id);
        } catch (error) {
          if (valid(id))
            await say(
              error.toString().contains('camera_missing')
                  ? 'İstediğin kamera bu cihazda bulunmuyor.'
                  : error.toString().contains('image_too_large')
                      ? 'Fotoğrafı uygun boyuta indiremedim. Dinlemeye dönüyorum.'
                      : 'Kamera karesini alamadım. Kamera iznini kontrol edelim.',
            );
          return;
        }
        if (!valid(id) || image == null) return;
      }
      if (!valid(id)) return;
      setState(
        () => mood = RegExp(r'üzgün|mutsuz|kötüyüm|sikkin').hasMatch(q)
            ? 'gentle'
            : RegExp(r'harika|güzel|mutlu|şaka').hasMatch(q)
                ? 'happy'
                : 'warm',
      );
      display(FaceMode.thinking);
      final answer = await ask(message, id, image: image);
      if (valid(id)) await say(answer);
    } finally {
      if (generation == id && mounted) {
        busy = false;
        if (active && !settingsOpen && !sleeping) {
          display(microphoneBlocked ? FaceMode.error : FaceMode.idle);
          schedule();
        }
      }
    }
  }

  Future<void> checkUpdate({bool automatic = false}) async {
    if (settingsOpen || updater.running) return;
    Map<String, dynamic>? update;
    try {
      update = await updater.check();
    } catch (_) {
      if (!automatic)
        await say('Güncelleme kontrol edilemedi. İnterneti kontrol edelim.');
      return;
    }
    if (update == null) {
      if (!automatic) await say('Yayımlanmış daha yeni bir sürüm bulunmuyor.');
      return;
    }
    if (!mounted || !active || settingsOpen) return;
    settingsOpen = true;
    generation++;
    listenId++;
    busy = false;
    restart?.cancel();
    settle?.cancel();
    watchdog?.cancel();
    inFlight?.close(force: true);
    await stopRecognition();
    await tts.stop();
    await neuralVoice.stop();
    if (!mounted) return;
    bool working = false;
    double progress = 0;
    String? error;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
            builder: (context, refresh) => AlertDialog(
                  title: const Text('MİMO güncellemesi'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(update!['play'] == true
                        ? 'Google Play yeni sürümü indirip kuracak.'
                        : 'Yeni test sürümü uygulama içinden indirilecek. Android kurulum onayını isteyecek; ilk kez bu kaynaktan kurarken izin vermen gerekebilir.'),
                    if (working)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: LinearProgressIndicator(
                              value: progress > 0 ? progress : null)),
                    if (error != null)
                      Text(error!,
                          style: const TextStyle(color: Colors.orange)),
                  ]),
                  actions: [
                    TextButton(
                        onPressed:
                            working ? null : () => Navigator.pop(context),
                        child: const Text('Şimdi değil')),
                    FilledButton(
                        onPressed: working
                            ? null
                            : () async {
                                refresh(() {
                                  working = true;
                                  error = null;
                                });
                                try {
                                  await updater.install(update!, (value) {
                                    if (context.mounted)
                                      refresh(() => progress = value);
                                  });
                                  if (context.mounted) Navigator.pop(context);
                                } catch (e) {
                                  if (context.mounted)
                                    refresh(() {
                                      working = false;
                                      error = e is FormatException
                                          ? e.message
                                          : 'Kurulum başlatılamadı. Mevcut uygulama ve ayarların korundu.';
                                    });
                                }
                              },
                        child: const Text('Güncelle')),
                  ],
                )));
    settingsOpen = false;
    if (mounted && active) {
      display(FaceMode.idle);
      await resumeListening();
    }
  }

  Future<void> interrupt() async {
    generation++;
    recognitionTurn.cancel();
    listenId = recognitionTurn.session;
    busy = false;
    heard = '';
    sleeping = false;
    restart?.cancel();
    settle?.cancel();
    watchdog?.cancel();
    inFlight?.close(force: true);
    customAI?.cancel();
    await stopRecognition();
    await tts.stop();
    await neuralVoice.stop();
    if (!mounted || !active || settingsOpen) return;
    if (!speechReady || microphoneBlocked) await prepareSpeech();
    display(microphoneBlocked ? FaceMode.error : FaceMode.idle);
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (permissionFlow || booting) return;
    if (state == AppLifecycleState.inactive) return;
    active = state == AppLifecycleState.resumed;
    if (!active) {
      generation++;
      listenId++;
      busy = false;
      heard = '';
      restart?.cancel();
      settle?.cancel();
      watchdog?.cancel();
      speech.cancel();
      tts.stop();
      neuralVoice.stop();
      customAI?.cancel();
      inFlight?.close(force: true);
      final old = camera;
      camera = null;
      old?.dispose();
      display(sleeping ? FaceMode.sleeping : FaceMode.idle);
    } else if (!settingsOpen) {
      resumeListening();
    }
  }

  Future<void> resumeListening() async {
    if (!mounted || !active || settingsOpen || booting) return;
    if (!speechReady || microphoneBlocked) await prepareSpeech();
    schedule();
  }

  Future<void> explainPermissions({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force && prefs.getBool('permissions_explained_v1') == true) return;
    if (!mounted || permissionFlow) return;
    permissionFlow = true;
    try {
      final allow = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('MİMO için iki izin'),
          content: const Text(
            'Sesli sohbet için mikrofon izni, “kameraya bak” ve “bunu oku” komutları için kamera izni gerekir. Kamera yalnızca sen istediğinde bir kare alır ve yorumlanması için sunucuya gönderir. İzin pencerelerinde “Uygulamayı kullanırken izin ver” seçeneğini seçebilirsin. Kamera izni olmadan sesli sohbeti kullanabilirsin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Şimdilik geç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('İzinleri seç'),
            ),
          ],
        ),
      );
      await prefs.setBool('permissions_explained_v1', true);
      if (allow == true) {
        final mic = await Permission.microphone.request();
        final cam = await Permission.camera.request();
        microphoneBlocked = !mic.isGranted;
        if ((!mic.isGranted || !cam.isGranted) && mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('İzinler tamamlanmadı'),
              content: Text(
                '${!mic.isGranted ? 'Mikrofon kapalı: sesli sohbet çalışmaz. ' : ''}${!cam.isGranted ? 'Kamera kapalı: görüntü yorumlama çalışmaz. ' : ''}Yüze uzun basarak izin ayarlarına tekrar ulaşabilirsin.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
                if (mic.isPermanentlyDenied || cam.isPermanentlyDenied)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await openAppSettings();
                    },
                    child: const Text('Telefon ayarları'),
                  ),
              ],
            ),
          );
        }
      }
    } finally {
      permissionFlow = false;
    }
  }

  void receiveInvite(Uri uri) {
    if (Invitation.parse(uri) == null) return;
    if (booting || settingsOpen) {
      pendingInvite = uri;
      if (!booting && mounted && Navigator.of(context).canPop())
        Navigator.of(context).pop();
      return;
    }
    activateInvitation(uri);
  }

  Future<void> activateInvitation(Uri uri) async {
    final invitation = Invitation.parse(uri);
    if (invitation == null || !mounted) return;
    settingsOpen = true;
    generation++;
    listenId++;
    restart?.cancel();
    settle?.cancel();
    watchdog?.cancel();
    inFlight?.close(force: true);
    await stopRecognition();
    await tts.stop();
    await neuralVoice.stop();
    if (!mounted) return;
    String? error;
    bool working = false;
    final activated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('MİMO daveti'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bu cihazı ${invitation.server.host} sunucusuna bağla. Adres veya parola yazman gerekmez.${token.isNotEmpty ? ' Mevcut bağlantı bu davetle değişir.' : ''}',
              ),
              if (working)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.orange)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      refresh(() {
                        working = true;
                        error = null;
                      });
                      try {
                        final nextToken = await inviteAccess.redeem(invitation);
                        endpoint = invitation.server.toString();
                        token = nextToken;
                        history.clear();
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('endpoint', endpoint);
                        await prefs.remove('access');
                        await prefs.remove('conversation');
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted)
                          refresh(() {
                            working = false;
                            error = e is FormatException
                                ? e.message
                                : 'Bağlantı kurulamadı. Aynı bağlantıyla tekrar deneyebilirsin.';
                          });
                      }
                    },
              child: const Text('Etkinleştir'),
            ),
          ],
        ),
      ),
    );
    settingsOpen = false;
    busy = false;
    if (!mounted) return;
    if (activated == true) {
      sleeping = false;
      await prepareSpeech();
      await say('Cihazın etkinleştirildi. Benimle konuşabilirsin.');
      schedule();
    } else if (endpoint.isEmpty || token.isEmpty) {
      await openSettings();
    } else {
      await resumeListening();
    }
  }

  Future<void> openDevices(BuildContext parent) async {
    final label = TextEditingController(text: 'Ortağım');
    String? error, invite;
    List<dynamic> devices = [];
    bool working = false;
    final server = Uri.parse(endpoint);
    Future<void> loadDevices() async {
      final result = await inviteAccess.request(
        server,
        '/admin/devices',
        token: token,
      );
      devices = result['devices'] as List<dynamic>? ?? [];
    }

    try {
      await loadDevices();
    } catch (e) {
      error = e is FormatException ? e.message : 'Cihaz listesi alınamadı.';
    }
    if (!parent.mounted) {
      label.dispose();
      return;
    }
    await showDialog<void>(
      context: parent,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Davet ve cihazlar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Davet 24 saat geçerlidir ve ilk etkinleştiren cihaza bağlanır. Bağlantıyı yalnızca davet edeceğin kişiye gönder.',
                ),
                TextField(
                  controller: label,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Cihaz adı'),
                ),
                if (invite != null) ...[
                  SelectableText(invite!),
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: invite!));
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Davet bağlantısı kopyalandı.'),
                          ),
                        );
                    },
                    child: const Text('Bağlantıyı kopyala'),
                  ),
                ],
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.orange)),
                if (working) const CircularProgressIndicator(),
                for (final device in devices)
                  ListTile(
                    title: Text(device['label'] as String? ?? 'Cihaz'),
                    trailing: TextButton(
                      onPressed: working
                          ? null
                          : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text(
                                    'Cihazın erişimi kapatılsın mı?',
                                  ),
                                  content: Text(
                                    '${device['label']} yeniden kullanmak için yeni davet gerektirecek.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Vazgeç'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Erişimi kapat'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true || !context.mounted) return;
                              refresh(() {
                                working = true;
                                error = null;
                              });
                              try {
                                await inviteAccess.request(
                                  server,
                                  '/admin/devices/revoke',
                                  token: token,
                                  body: {'id': device['id']},
                                );
                                await loadDevices();
                              } catch (e) {
                                error = e is FormatException
                                    ? e.message
                                    : 'İşlem tamamlanamadı.';
                              }
                              if (context.mounted)
                                refresh(() => working = false);
                            },
                      child: const Text('Erişimi kapat'),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      if (label.text.trim().isEmpty) {
                        refresh(() => error = 'Bir cihaz adı yaz.');
                        return;
                      }
                      refresh(() {
                        working = true;
                        error = null;
                      });
                      try {
                        final result = await inviteAccess.request(
                          server,
                          '/admin/invites',
                          token: token,
                          body: {'label': label.text.trim()},
                        );
                        invite = result['url'] as String;
                      } catch (e) {
                        error = e is FormatException
                            ? e.message
                            : 'Davet oluşturulamadı.';
                      }
                      if (context.mounted) refresh(() => working = false);
                    },
              child: const Text('Davet oluştur'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    label.dispose();
  }

  Future<void> openSettings() async {
    if (!mounted || settingsOpen) return;
    settingsOpen = true;
    generation++;
    listenId++;
    busy = false;
    restart?.cancel();
    settle?.cancel();
    watchdog?.cancel();
    await stopRecognition();
    await tts.stop();
    await neuralVoice.stop();
    customAI?.cancel();
    inFlight?.close(force: true);
    if (!mounted) return;
    final url = TextEditingController(text: endpoint),
        secret = TextEditingController(text: token);
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: endpoint.isNotEmpty,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('MİMO bağlantısı'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Normal ekranda yalnızca yüzüm var. Ayarlara yüzüme uzun basarak dönersin. Mikrofon yalnızca uygulama açıkken dinler. “Kameraya bak” dediğinde tek kare Gemini’ye gönderilir; fotoğraf cihazda saklanmaz. Son 6 konuşma cihazda tutulur; “geçmişi unut” diyerek silebilirsin.',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Bulut sesi'),
                  subtitle: const Text(
                      'Kapalıyken telefonun sesiyle daha hızlı yanıt verir. Bulut sesi bağlantıya göre bekletebilir.'),
                  value: cloudVoice,
                  onChanged: (value) async {
                    refresh(() => cloudVoice = value);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('cloud_voice', value);
                  },
                ),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'HTTPS sunucu adresi',
                  ),
                ),
                TextField(
                  controller: secret,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Sunucu erişim parolası',
                  ),
                ),
                const Text(
                  'Gemini API anahtarını buraya girme.',
                  style: TextStyle(fontSize: 12),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.orange)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => explainPermissions(force: true),
              child: const Text('Mikrofon ve kamera izinleri'),
            ),
            if (endpoint.isNotEmpty &&
                token.isNotEmpty &&
                !token.startsWith('device_'))
              TextButton(
                onPressed: () => openDevices(context),
                child: const Text('Davet ve cihazlar'),
              ),
            TextButton(
                onPressed: () => customAISettings(context),
                child: const Text('Gelişmiş yapay zekâ')),
            if (endpoint.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            FilledButton(
              onPressed: () async {
                final uri = Uri.tryParse(url.text.trim());
                if (uri == null ||
                    uri.scheme != 'https' ||
                    uri.host.isEmpty ||
                    uri.userInfo.isNotEmpty ||
                    secret.text.trim().isEmpty) {
                  refresh(
                    () => error =
                        'Geçerli HTTPS adresi ve erişim parolası gerekli.',
                  );
                  return;
                }
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('endpoint', url.text.trim());
                await inviteAccess.save(url.text.trim(), secret.text.trim());
                endpoint = url.text.trim();
                token = secret.text.trim();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    // Text fields can still be mounted during the dialog's exit animation.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      url.dispose();
      secret.dispose();
    });
    settingsOpen = false;
    if (pendingInvite != null && mounted) {
      final link = pendingInvite!;
      pendingInvite = null;
      await activateInvitation(link);
      return;
    }
    if (mounted && active) {
      sleeping = false;
      if (!speechReady || microphoneBlocked) await prepareSpeech();
      schedule();
    }
  }

  @override
  void dispose() {
    linkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    active = false;
    restart?.cancel();
    settle?.cancel();
    watchdog?.cancel();
    listeningHealth?.cancel();
    speech.cancel();
    tts.stop();
    neuralVoice.dispose();
    customAI?.cancel();
    inFlight?.close(force: true);
    camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Semantics(
          label: mode == FaceMode.listening
              ? 'MİMO dinliyor'
              : mode == FaceMode.speaking
                  ? 'MİMO konuşuyor'
                  : mode == FaceMode.camera
                      ? 'MİMO kameraya bakıyor'
                      : mode == FaceMode.sleeping
                          ? 'MİMO dinleniyor'
                          : 'MİMO',
          hint:
              'Konuşmasını kesmek veya uyandırmak için dokun. Bağlantı ayarları için uzun bas.',
          onTap: interrupt,
          onLongPress: openSettings,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: interrupt,
            onLongPress: openSettings,
            child: BlenderAvatar(
                mode: mode,
                energy: energy,
                mood: mood,
                word: speechWord,
                wordOffset: speechOffset),
          ),
        ),
      );
}
