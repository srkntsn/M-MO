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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import 'face.dart';
import 'invitations.dart';
import 'camera_image.dart';

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
  bool microphoneBlocked = false;
  int generation = 0, listenId = 0, failures = 0;
  Timer? restart, settle, watchdog;
  HttpClient? inFlight;
  CameraController? camera;
  String heard = '';
  bool get canListen =>
      mounted &&
      active &&
      !settingsOpen &&
      !sleeping &&
      !busy &&
      !microphoneBlocked &&
      speechReady &&
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
    boot();
  }

  Future<void> boot() async {
    final prefs = await SharedPreferences.getInstance();
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
    await tts.setPitch(1.04);
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
        setState(() => energy = .5 + (word.length % 5) / 10);
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
    }
  }

  Future<void> prepareSpeech() async {
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
          if (e.errorMsg.contains('permission') ||
              e.errorMsg.contains('not_available')) {
            microphoneBlocked = true;
            display(FaceMode.error);
          } else {
            if (!e.errorMsg.contains('no_match') &&
                !e.errorMsg.contains('speech_timeout'))
              failures++;
            schedule();
          }
        },
        onStatus: (status) {
          if (!mounted || !active || settingsOpen || busy) return;
          if (status == 'done' || status == 'notListening') {
            final session = listenId;
            settle?.cancel();
            settle = Timer(
              const Duration(milliseconds: 450),
              () => consume(session),
            );
          }
        },
      );
      microphoneBlocked = !speechReady;
    } catch (_) {
      speechReady = false;
      microphoneBlocked = true;
    }
    if (microphoneBlocked) display(FaceMode.error);
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
    final session = ++listenId;
    heard = '';
    try {
      display(FaceMode.listening);
      await speech.listen(
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
          if (r.finalResult) consume(session);
        },
      );
      if (!canListen || session != listenId) {
        await speech.cancel();
        return;
      }
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 34), () async {
        if (session != listenId || !canListen) return;
        await speech.stop();
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
    final text = heard.trim();
    heard = '';
    if (text.isEmpty) {
      schedule();
      return;
    }
    listenId++;
    failures = 0;
    respond(text);
  }

  Future<void> say(String text) async {
    if (!mounted || !active || settingsOpen) return;
    await speech.cancel();
    if (!mounted || !active || settingsOpen) return;
    final spokenGeneration = generation;
    display(FaceMode.speaking);
    try {
      await tts.speak(text).timeout(const Duration(seconds: 65));
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
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 12));
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
        const Duration(seconds: 55),
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
    await speech.cancel();
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
      if (q.contains('güncelleme') || q.contains('guncelleme')) {
        await checkUpdate();
        return;
      }
      if (q.contains('yeni sürümü aç') ||
          q.contains('yeni surumu ac') ||
          q == 'mimo güncelle' ||
          q == 'güncelle') {
        final opened = await launchUrl(
          Uri.parse('https://github.com/srkntsn/M-MO/releases/latest'),
          mode: LaunchMode.externalApplication,
        );
        if (!opened)
          await say(
            'İndirme sayfasını açamadım. GitHub üzerindeki MİMO sürümlerine bakabilirsin.',
          );
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

  Future<void> checkUpdate() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(
            Uri.parse(
              'https://api.github.com/repos/srkntsn/M-MO/releases/latest',
            ),
          )
          .timeout(const Duration(seconds: 10));
      request.headers.set('User-Agent', 'MIMO-Android');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        await say('Henüz yayımlanmış yeni bir sürüm bulamadım.');
        return;
      }
      final release = jsonDecode(await utf8.decoder.bind(response).join());
      final tag = release['tag_name']?.toString() ?? '';
      final latest =
          int.tryParse(
            RegExp(r'build\.(\d+)$').firstMatch(tag)?.group(1) ?? '',
          ) ??
          0;
      final current = await PackageInfo.fromPlatform();
      if (latest > (int.tryParse(current.buildNumber) ?? 0)) {
        await say(
          'Yeni sürüm hazır! Yeni sürümü aç dersen indirme sayfasını açarım. Android kurulumu senin onayını isteyecek.',
        );
      } else {
        await say('Şu an son yayımlanan sürümü kullanıyorsun.');
      }
    } catch (_) {
      await say(
        'Güncellemeleri şu anda kontrol edemedim. Biraz sonra tekrar deneyelim.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> interrupt() async {
    generation++;
    listenId++;
    busy = false;
    heard = '';
    sleeping = false;
    restart?.cancel();
    settle?.cancel();
    watchdog?.cancel();
    inFlight?.close(force: true);
    await speech.cancel();
    await tts.stop();
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
    await speech.cancel();
    await tts.stop();
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
                            error = e is FormatException ? e.message : 'Bağlantı kurulamadı. Aynı bağlantıyla tekrar deneyebilirsin.';
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
    await speech.cancel();
    await tts.stop();
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
    speech.cancel();
    tts.stop();
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
      hint: 'Konuşmasını kesmek veya uyandırmak için dokun. Bağlantı ayarları için uzun bas.',
      onTap: interrupt,
      onLongPress: openSettings,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interrupt,
        onLongPress: openSettings,
        child: MimoFace(mode: mode, energy: energy, mood: mood),
      ),
    ),
  );
}
