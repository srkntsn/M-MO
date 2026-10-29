import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mimo_ai/camera_image.dart';
import 'package:mimo_ai/invitations.dart';

void main() {
  test('noisy photos from either orientation fit the wire budget', () {
    final random = Random(42);
    for (final portrait in [true, false]) {
      final source = img.Image(
        width: portrait ? 1200 : 1600,
        height: portrait ? 1600 : 1200,
      );
      for (final pixel in source) {
        pixel.setRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
      final result = prepareCameraImage(
        Uint8List.fromList(img.encodeJpg(source, quality: 95)),
      );
      expect(result.length, lessThanOrEqualTo(cameraImageLimit));
      final decoded = img.decodeJpg(result)!;
      expect(max(decoded.width, decoded.height), lessThanOrEqualTo(960));
      expect(
        decoded.width / decoded.height,
        closeTo(source.width / source.height, .01),
      );
    }
  });
  test('corrupt camera data fails instead of being uploaded', () {
    expect(
      () => prepareCameraImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
  test('activation accepts only bounded codes and clean HTTPS origins', () {
    Uri link(String server, String code) => Uri(
          scheme: 'mimo',
          host: 'activate',
          queryParameters: {'server': server, 'invite': code},
        );
    expect(Invitation.parse(link('https://worker.test', 'a' * 64)), isNotNull);
    for (final server in [
      'http://worker.test',
      'https://user:password@worker.test',
      'https://worker.test/path',
      'https://worker.test/?q=1',
    ]) {
      expect(Invitation.parse(link(server, 'a' * 64)), isNull);
    }
    expect(Invitation.parse(link('https://worker.test', 'bad')), isNull);
  });
}
