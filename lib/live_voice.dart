import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Foreground full duplex session. Ordinary conversational turns never restart
/// the recorder. Only lifecycle, explicit sleep, or a fatal connection error do.
class LiveVoice {
  static const audio = MethodChannel('mimo/live/audio');
  static const events = EventChannel('mimo/live/events');
  final Future<WebSocket> Function(Uri, String)? connect;
  final void Function(String state) onState;
  final void Function(double level) onLevel;
  final Future<String> Function(String name, Map<String, dynamic> args) onTool;
  final void Function(String error) onError;
  LiveVoice(
      {this.connect,
      required this.onState,
      required this.onLevel,
      required this.onTool,
      required this.onError});
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription, _audioEvents;
  Timer? _retry, _setupTimeout;
  Future<void>? _stopping;
  String? _handle;
  String _endpoint = '', _token = '';
  bool _enabled = false, _ready = false, _recording = false, _muted = false;
  int _epoch = 0, _attempt = 0;
  bool get enabled => _enabled;

  Future<void> start(String endpoint, String token) async {
    await _stopping;
    if (_enabled) return;
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        token.isEmpty) {
      onError(
          'Sunucu adresi veya erişim parolası eksik. Yüze uzun basarak ayarları açabilirsin.');
      return;
    }
    _endpoint = endpoint;
    _token = token;
    _enabled = true;
    _attempt = 0;
    _audioEvents = events.receiveBroadcastStream().listen((event) {
      if (!_enabled) return;
      if (event is Uint8List) {
        if (_ready && _socket?.readyState == WebSocket.open)
          _socket!.add(event);
      } else if (event is Map) {
        if (event['type'] == 'level')
          onLevel((event['value'] as num).toDouble());
        if (event['type'] == 'audio_error' || event['type'] == 'focus_lost') {
          _fail(event['type'] == 'focus_lost'
              ? 'Telefon ses oturumunu devraldı. Hazır olduğunda yüze dokunarak sohbete dön.'
              : 'Mikrofondan ses alınamadı. Mikrofon iznini ve başka bir uygulamanın kullanıp kullanmadığını kontrol edelim.');
        }
      }
    }, onError: (Object _) => _fail('Telefonun canlı ses kanalı açılamadı.'));
    await _connect();
  }

  Future<void> _connect() async {
    if (!_enabled) return;
    final epoch = ++_epoch;
    _ready = false;
    onState('connecting');
    try {
      final uri = Uri.parse(_endpoint)
          .replace(scheme: 'wss', path: '/live', query: null, fragment: null);
      final socket = await (connect != null
              ? connect!(uri, _token)
              : WebSocket.connect(uri.toString(),
                  headers: {'Authorization': 'Bearer $_token'}))
          .timeout(const Duration(seconds: 15));
      if (!_enabled || epoch != _epoch) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 15);
      _subscription = socket.listen((data) => _message(data, epoch),
          onError: (Object _) => _disconnected(epoch),
          onDone: () => _disconnected(epoch),
          cancelOnError: true);
      socket.add(jsonEncode(
          {'type': 'start', if (_handle != null) 'handle': _handle}));
      _setupTimeout = Timer(
          const Duration(seconds: 20),
          () => _fail(
              'Canlı ses oturumu hazırlanamadı. Sunucunun Gemini Live erişimini kontrol edelim.'));
    } catch (_) {
      if (!_enabled || epoch != _epoch) return;
      _disconnected(epoch);
    }
  }

  Future<void> _message(dynamic data, int epoch) async {
    if (!_enabled || epoch != _epoch) return;
    try {
      if (data is! String || data.length > 1500000)
        throw const FormatException();
      final p = jsonDecode(data) as Map<String, dynamic>;
      switch (p['type']) {
        case 'ready':
          _setupTimeout?.cancel();
          _ready = true;
          _muted = false;
          _attempt = 0;
          if (!_recording) {
            await audio.invokeMethod<dynamic>('start');
            if (!_enabled || epoch != _epoch) return;
            _recording = true;
          }
          onState('listening');
        case 'audio':
          if (_ready && _recording && !_muted && p['data'] is String) {
            final bytes = base64Decode(p['data'] as String);
            if (bytes.length > 192000 || bytes.length.isOdd)
              throw const FormatException();
            await audio.invokeMethod<void>('play', bytes);
          }
        case 'turn':
          _muted = false;
        case 'interrupt':
          _muted = false;
          await audio.invokeMethod<void>('clear');
          onLevel(0);
          onState('listening');
        case 'resume':
          if (p['handle'] is String && (p['handle'] as String).length <= 4096)
            _handle = p['handle'] as String;
        case 'reconnect':
          await _socket?.close(1000);
          _disconnected(epoch);
        case 'error':
          _fail(
              'Gemini canlı ses oturumunu kabul etmedi. Sunucu bağlantısını kontrol edelim.');
        case 'tool':
          final result = await onTool(p['name'] as String,
              Map<String, dynamic>.from(p['args'] as Map? ?? {}));
          if (_enabled && _ready && epoch == _epoch)
            _socket?.add(
                jsonEncode({'type': 'tool', 'id': p['id'], 'result': result}));
      }
    } catch (_) {
      if (_enabled && epoch == _epoch)
        _fail(
            'Canlı ses işlenemedi. Yüze dokunarak bağlantıyı yeniden kurabilirsin.');
    }
  }

  void sendImage(String base64) {
    if (_enabled && _ready && base64.length <= 1200000)
      _socket?.add(jsonEncode({'type': 'image', 'data': base64}));
  }

  Future<void> clearPlayback({bool untilTurn = false}) async {
    if (untilTurn) _muted = true;
    if (_recording) await audio.invokeMethod<void>('clear');
    onLevel(0);
  }

  void _disconnected(int epoch) {
    if (!_enabled || epoch != _epoch) return;
    // Invalidate old callbacks immediately. Do not bounce the microphone between turns.
    ++_epoch;
    _ready = false;
    _setupTimeout?.cancel();
    final code = _socket?.closeCode;
    _socket?.close();
    _socket = null;
    _subscription?.cancel();
    unawaited(clearPlayback());
    if (code == 1008 || ++_attempt > 3) {
      _fail(
          'Canlı ses bağlantısı kurulamadı. Sunucu erişim parolasını ve Gemini Live kullanılabilirliğini kontrol edelim.');
      return;
    }
    onState('connecting');
    _retry?.cancel();
    _retry = Timer(Duration(seconds: 1 << (_attempt - 1)), _connect);
  }

  void _fail(String message) {
    if (!_enabled) return;
    unawaited(stop());
    onError(message);
  }

  Future<void> stop({bool forget = false}) {
    if (forget) _handle = null;
    return _stopping ??= _stop().whenComplete(() => _stopping = null);
  }

  Future<void> _stop() async {
    _enabled = false;
    _ready = false;
    ++_epoch;
    _retry?.cancel();
    _setupTimeout?.cancel();
    final socket = _socket;
    _socket = null;
    final subscription = _subscription;
    _subscription = null;
    final input = _audioEvents;
    _audioEvents = null;
    _recording = false;
    try {
      await audio.invokeMethod<void>('stop');
    } catch (_) {}
    unawaited(socket?.close());
    await subscription?.cancel();
    await input?.cancel();
    onLevel(0);
  }
}
