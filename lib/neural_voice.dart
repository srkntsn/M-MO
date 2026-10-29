import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class NeuralVoice {
  final player = AudioPlayer();
  HttpClient? client;
  int generation = 0;
  Completer<void>? completion;
  StreamSubscription<void>? ended;
  StreamSubscription<Duration>? positions;
  Timer? envelope;
  Future<bool> speak(Uri server, String token, String text,
      void Function(double) onEnergy) async {
    await stop();
    final id = ++generation;
    if (text.length > 1400 || token.isEmpty) return false;
    client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final activeClient = client!;
    StreamSubscription<void>? activeEnded;
    StreamSubscription<Duration>? activePositions;
    Timer? activeEnvelope;
    var started = false;
    try {
      final req = await activeClient
          .postUrl(server.resolve('/speech'))
          .timeout(const Duration(seconds: 6));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer $token');
      req.add(utf8.encode(jsonEncode({'text': text})));
      final response = await req.close().timeout(const Duration(seconds: 16));
      if (response.statusCode != 200 || id != generation) return false;
      final data = BytesBuilder();
      var size = 0;
      await for (final part in response.timeout(const Duration(seconds: 6))) {
        size += part.length;
        if (size > 5000000) throw const FormatException('Audio too large');
        data.add(part);
      }
      if (id != generation) return false;
      final bytes = data.takeBytes();
      final levels = waveEnvelope(bytes);
      final done = Completer<void>();
      completion = done;
      ended = player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      activeEnded = ended;
      final watch = Stopwatch();
      positions = player.onPositionChanged.listen((p) {
        if (id != generation || levels.isEmpty) return;
        final index = (p.inMilliseconds ~/ 40).clamp(0, levels.length - 1);
        onEnergy(levels[index]);
      });
      activePositions = positions;
      await player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      if (id != generation) {
        await player.stop();
        return true;
      }
      started = true;
      watch.start();
      envelope = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (id != generation || levels.isEmpty) return;
        final index =
            (watch.elapsedMilliseconds ~/ 40).clamp(0, levels.length - 1);
        onEnergy(levels[index]);
      });
      activeEnvelope = envelope;
      await done.future.timeout(const Duration(seconds: 70));
      return true;
    } catch (_) {
      return started;
    } finally {
      activeClient.close(force: true);
      if (identical(client, activeClient)) client = null;
      activeEnvelope?.cancel();
      await activeEnded?.cancel();
      await activePositions?.cancel();
      if (identical(ended, activeEnded)) ended = null;
      if (identical(positions, activePositions)) positions = null;
      if (identical(envelope, activeEnvelope)) envelope = null;
      if (id == generation) onEnergy(0);
    }
  }

  Future<void> stop() async {
    generation++;
    client?.close(force: true);
    client = null;
    envelope?.cancel();
    if (completion case final done?) {
      if (!done.isCompleted) done.complete();
    }
    completion = null;
    await player.stop();
  }

  Future<void> dispose() async {
    await stop();
    await player.dispose();
  }
}

List<double> waveEnvelope(Uint8List bytes) {
  if (bytes.length < 44 ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF')
    return [];
  final data = ByteData.sublistView(bytes);
  int offset = 12, rate = 24000, channels = 1, bits = 16, start = 0, length = 0;
  while (offset + 8 <= bytes.length) {
    final name =
        ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true);
    final size = data.getUint32(offset + 4, Endian.little);
    final next = offset + 8;
    if (next + size > bytes.length) break;
    if (name == 'fmt ' && size >= 16) {
      if (data.getUint16(next, Endian.little) != 1) return [];
      channels = data.getUint16(next + 2, Endian.little);
      rate = data.getUint32(next + 4, Endian.little);
      bits = data.getUint16(next + 14, Endian.little);
    }
    if (name == 'data') {
      start = next;
      length = size;
      break;
    }
    offset = next + size + (size % 2);
  }
  if (start == 0 || bits != 16 || rate <= 0 || channels <= 0) return [];
  final step = math.max(2, (rate * channels * .04).round() * 2),
      result = <double>[];
  for (var at = start; at < start + length; at += step) {
    var sum = 0.0, count = 0;
    for (var i = at; i + 1 < math.min(at + step, start + length); i += 2) {
      final v = data.getInt16(i, Endian.little) / 32768;
      sum += v * v;
      count++;
    }
    result.add(count == 0 ? 0 : (math.sqrt(sum / count) * 5).clamp(0, 1));
  }
  return result;
}
