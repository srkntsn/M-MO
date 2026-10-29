import 'dart:typed_data';

import 'package:image/image.dart' as img;

const cameraImageLimit = 180000;

// Executed in an isolate: decoding and JPEG encoding must not block the face.
Uint8List prepareCameraImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('invalid_image');
  var image = img.bakeOrientation(decoded);
  if (image.width > 960 || image.height > 960) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 960)
        : img.copyResize(image, height: 960);
  }
  for (final quality in [80, 65, 50]) {
    final result = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (result.length <= cameraImageLimit) return result;
  }
  // Some devices produce unusually noisy images. Reduce dimensions, too.
  for (final edge in [640, 480, 320]) {
    final smaller = image.width >= image.height
        ? img.copyResize(image, width: edge)
        : img.copyResize(image, height: edge);
    final result = Uint8List.fromList(img.encodeJpg(smaller, quality: 55));
    if (result.length <= cameraImageLimit) return result;
  }
  throw const FormatException('image_too_large');
}
