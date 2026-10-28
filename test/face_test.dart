import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimo_ai/face.dart';

void main() {
  testWidgets('3D face paints all conversation states without overflow', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    for (final state in FaceMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MimoFace(mode: state, energy: .8)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
