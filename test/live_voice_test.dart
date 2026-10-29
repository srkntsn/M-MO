import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_ai/live_voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  test(
      'one recorder across turns; microphone still transmits during playback and interruption',
      () async {
    final calls = <String>[];
    final errors = <String>[];
    messenger.setMockMethodCallHandler(LiveVoice.audio, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('mimo/live/events'), (call) async => null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<WebSocket>();
    server.listen((request) async {
      accepted.complete(await WebSocketTransformer.upgrade(request));
    });
    final live = LiveVoice(
        onState: (_) {},
        onLevel: (_) {},
        onTool: (_, __) async => 'ok',
        onError: errors.add,
        connect: (uri, token) {
          expect(uri.scheme, 'wss');
          expect(uri.path, '/live');
          expect(token, 'access');
          return WebSocket.connect('ws://127.0.0.1:${server.port}');
        });
    await live.start('https://mimo.example/', 'access');
    final socket = await accepted.future;
    final received = <dynamic>[];
    socket.listen(received.add);
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));
    void send(Map<String, dynamic> packet) => socket.add(jsonEncode(packet));
    Future<void> mic() async {
      await messenger.handlePlatformMessage(
          'mimo/live/events',
          codec.encodeSuccessEnvelope(Uint8List.fromList([1, 0, 2, 0])),
          (_) {});
      await settle();
    }

    try {
      send({'type': 'ready'});
      await settle();
      expect(calls.where((x) => x == 'start').length, 1);
      send({'type': 'audio', 'data': 'AQACAA=='});
      await settle();
      expect(calls, contains('play'));
      await mic();
      expect(received.whereType<List<int>>().length, 1);
      send({'type': 'interrupt'});
      send({'type': 'turn'});
      await settle();
      expect(calls, contains('clear'));
      send({'type': 'audio', 'data': 'AwAEAA=='});
      await settle();
      await mic();
      expect(received.whereType<List<int>>().length, 2);
      expect(calls.where((x) => x == 'start').length, 1);
      expect(calls.where((x) => x == 'stop'), isEmpty);
      expect(errors, isEmpty);
      await live.stop();
      expect(calls, contains('stop'));
    } finally {
      await live.stop();
      await socket.close();
      await server.close(force: true);
      messenger.setMockMethodCallHandler(LiveVoice.audio, null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('mimo/live/events'), null);
    }
  });
}
