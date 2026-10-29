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

import 'face.dart';
import 'invitations.dart';
import 'camera_image.dart';
import 'avatar.dart';
import 'neural_voice.dart';
import 'updater.dart';
import 'live_voice.dart';

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
  late final LiveVoice live = LiveVoice(
    onState: (state) {
      if (mounted && active && !settingsOpen && !sleeping)
        display(state == 'connecting' ? FaceMode.thinking : FaceMode.listening);
    },
    onLevel: (level) {
      if (mounted && active && !settingsOpen && !sleeping)
        setState(() {
          energy = level;
          speechWord = '';
          speechOffset = 0;
          mode = level > 0 ? FaceMode.speaking : FaceMode.listening;
        });
    },
    onTool: liveTool,
    onError: liveError,
  );
  bool liveErrorOpen = false;

  final tts = FlutterTts();
  final neuralVoice = NeuralVoice();
  final updater = AppUpdater();
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
      microphoneReady = false;
  bool microphoneBlocked = false;
  int generation = 0;
  bool cloudVoice = false;
  CameraController? camera;
  String speechWord = '';
  int speechOffset = 0;
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
    await resumeListening();
    unawaited(checkUpdate(automatic: true));
  }

  Future<void> prepareMicrophone() async {
    microphoneBlocked = !(await Permission.microphone.isGranted);
    microphoneReady = !microphoneBlocked;
    if (microphoneBlocked) display(FaceMode.error);
  }

  // Pauses occur only for explicit settings, backgrounding or sleep.
  Future<void> stopLive() => live.stop();
  void schedule() {
    unawaited(resumeListening());
  }

  Future<void> liveError(String message) async {
    if (!mounted || !active || settingsOpen || liveErrorOpen) return;
    liveErrorOpen = true;
    display(FaceMode.error);
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Ses bağlantısı'),
                content: Text(message),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Kapat')),
                ]));
    liveErrorOpen = false;
  }

  Future<String> liveTool(String name, Map<String, dynamic> args) async {
    if (!mounted || !active || settingsOpen) return 'Uygulama etkin değil.';
    switch (name) {
      case 'capture_camera':
        if (camera != null) return 'Kamera zaten çalışıyor.';
        preferredLens = args['lens'] == 'front'
            ? CameraLensDirection.front
            : CameraLensDirection.back;
        final id = generation;
        try {
          final image = await capture(id);
          if (image == null || !valid(id)) return 'Fotoğraf alınamadı.';
          live.sendImage(image['data'] as String);
          return 'İstenen kamera karesi gönderildi. Yalnızca bu kareyi yorumla.';
        } catch (_) {
          return 'Kamera karesi alınamadı. İzinleri kontrol et.';
        }
      case 'open_settings':
        unawaited(openSettings());
        return 'Ayarlar açılıyor.';
      case 'sleep':
        sleeping = true;
        unawaited(live.stop());
        display(FaceMode.sleeping);
        return 'Dinleme kapandı.';
      case 'forget':
        history.clear();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('conversation');
        await live.stop(forget: true);
        unawaited(resumeListening());
        return 'Sohbet silindi.';
      case 'check_update':
        unawaited(checkUpdate());
        return 'Güncelleme kontrol ediliyor.';
      default:
        return 'Desteklenmeyen işlem.';
    }
  }

  Future<void> say(String text) async {
    if (!mounted || !active || settingsOpen) return;
    if (live.enabled) return;
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
    if (!live.enabled)
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
    await stopLive();
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
    if (!mounted || !active || settingsOpen) return;
    sleeping = false;
    if (live.enabled) {
      await live.clearPlayback(untilTurn: true);
      return;
    }
    await tts.stop();
    await neuralVoice.stop();
    await resumeListening();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (permissionFlow || booting) return;
    // Native onStop is an additional guard; never keep recording in background.
    active = state == AppLifecycleState.resumed;
    if (!active) {
      generation++;
      unawaited(live.stop());
      tts.stop();
      neuralVoice.stop();
      final old = camera;
      camera = null;
      old?.dispose();
      display(sleeping ? FaceMode.sleeping : FaceMode.idle);
    } else if (!settingsOpen) {
      resumeListening();
    }
  }

  Future<void> resumeListening() async {
    if (!mounted ||
        !active ||
        settingsOpen ||
        booting ||
        sleeping ||
        permissionFlow) return;
    await prepareMicrophone();
    if (!mounted || !active || settingsOpen || sleeping || microphoneBlocked)
      return;
    await live.start(endpoint, token);
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
    await stopLive();
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
    if (!mounted) return;
    if (activated == true) {
      sleeping = false;
      await prepareMicrophone();
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
    await stopLive();
    await tts.stop();
    await neuralVoice.stop();
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
                  'Normal ekranda yalnızca yüzüm var. Ayarlara yüzüme uzun basarak dönersin. Mikrofon yalnızca uygulama açıkken dinler. “Kameraya bak” dediğinde tek kare Gemini’ye gönderilir; fotoğraf cihazda saklanmaz. Canlı sohbet geçici oturumda tutulur; “geçmişi unut” yeni oturum başlatır.',
                ),
                const SizedBox(height: 16),
                const Text(
                    'Canlı ses: MİMO konuşurken de mikrofon açık kalır. Araya girerek konuşmasını kesebilirsin. Sesler Gemini’ye canlı iletilir; uygulama arka plana geçtiğinde mikrofon kapanır.'),
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
      if (!microphoneReady || microphoneBlocked) await prepareMicrophone();
      schedule();
    }
  }

  @override
  void dispose() {
    linkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    active = false;
    unawaited(live.stop());
    tts.stop();
    neuralVoice.dispose();
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
