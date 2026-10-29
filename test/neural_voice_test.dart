import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_ai/neural_voice.dart';

void main() {
  test('wave envelope follows silent and voiced frames', () {
    final bytes = Uint8List(44 + 3840);
    final view = ByteData.sublistView(bytes);
    void str(int at, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[at + i] = value.codeUnitAt(i);
      }
    }

    str(0, 'RIFF');
    str(8, 'WAVE');
    str(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, 24000, Endian.little);
    view.setUint16(34, 16, Endian.little);
    str(36, 'data');
    view.setUint32(40, 3840, Endian.little);
    for (var i = 44 + 1920; i + 1 < bytes.length; i += 2) {
      view.setInt16(i, 12000, Endian.little);
    }
    final levels = waveEnvelope(bytes);
    expect(levels.length, 2);
    expect(levels.first, 0);
    expect(levels.last, greaterThan(.9));
  });
  test('corrupt audio does not drive a speaking mouth', () {
    expect(waveEnvelope(Uint8List(0)), isEmpty);
  });
}
