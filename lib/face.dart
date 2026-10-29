import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum FaceMode { idle, listening, thinking, speaking, camera, sleeping, error }

/// Actual perspective-projected triangle meshes; no network assets or WebView.
class MimoFace extends StatefulWidget {
  const MimoFace({
    super.key,
    required this.mode,
    this.energy = 0,
    this.mood = 'warm',
  });
  final FaceMode mode;
  final double energy;
  final String mood;
  @override
  State<MimoFace> createState() => _MimoFaceState();
}

class _MimoFaceState extends State<MimoFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  )..repeat();
  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _FacePainter(clock, widget.mode, widget.energy, widget.mood),
      size: Size.infinite,
    ),
  );
}

class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V operator +(_V b) => _V(x + b.x, y + b.y, z + b.z);
  _V operator -(_V b) => _V(x - b.x, y - b.y, z - b.z);
  _V cross(_V b) => _V(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  double dot(_V b) => x * b.x + y * b.y + z * b.z;
  _V get unit {
    final n = math.sqrt(dot(this));
    return n < 0.000001 ? const _V(0, 0, 1) : _V(x / n, y / n, z / n);
  }
}

class _Triangle {
  _Triangle(this.a, this.b, this.c, this.ca, this.cb, this.cc);
  final _V a, b, c;
  final Color ca, cb, cc;
  double get depth => a.z + b.z + c.z;
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.clock, this.mode, this.energy, this.mood)
    : super(repaint: clock);
  final Animation<double> clock;
  final FaceMode mode;
  final double energy;
  final String mood;
  final List<_Triangle> faces = [];
  double yaw = 0, pitch = 0;
  _V rotate(_V p) {
    final x = p.x * math.cos(yaw) + p.z * math.sin(yaw);
    final z = -p.x * math.sin(yaw) + p.z * math.cos(yaw);
    return _V(
      x,
      p.y * math.cos(pitch) - z * math.sin(pitch),
      p.y * math.sin(pitch) + z * math.cos(pitch),
    );
  }

  void triangle(
    _V a,
    _V b,
    _V c,
    Color material, {
    bool luminous = false,
    _V? na,
    _V? nb,
    _V? nc,
  }) {
    a = rotate(a);
    b = rotate(b);
    c = rotate(c);
    final normal = (b - a).cross(c - a).unit;
    if (normal.z <= 0) return;
    Color shade(_V n) {
      final diffuse = math.max(0.0, n.dot(const _V(-.4, -.6, .7).unit));
      final gloss = math
          .pow(math.max(0.0, n.dot(const _V(-.2, -.3, .94).unit)), 36)
          .toDouble();
      final rim = math.pow(1 - n.z.abs().clamp(0.0, 1.0), 3).toDouble() * .12;
      final light = luminous ? .83 + diffuse * .17 : .25 + diffuse * .70 + rim;
      int channel(double v) => (v * 255 * light + gloss * (luminous ? 20 : 65))
          .round()
          .clamp(0, 255);
      return Color.fromARGB(
        255,
        channel(material.r),
        channel(material.g),
        channel(material.b),
      );
    }

    faces.add(
      _Triangle(
        a,
        b,
        c,
        shade(na == null ? normal : rotate(na)),
        shade(nb == null ? normal : rotate(nb)),
        shade(nc == null ? normal : rotate(nc)),
      ),
    );
  }

  void ellipsoid(
    _V center,
    _V radius,
    Color color, {
    int rings = 16,
    int segments = 28,
    bool luminous = false,
  }) {
    final points = <_V>[], normals = <_V>[];
    for (var i = 0; i <= rings; i++) {
      for (var j = 0; j <= segments; j++) {
        final a = math.pi * i / rings, b = 2 * math.pi * j / segments;
        final x = math.sin(a) * math.cos(b),
            y = math.cos(a),
            z = math.sin(a) * math.sin(b);
        points.add(center + _V(radius.x * x, radius.y * y, radius.z * z));
        normals.add(_V(x / radius.x, y / radius.y, z / radius.z).unit);
      }
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < segments; j++) {
        final a = i * (segments + 1) + j,
            b = a + 1,
            c = a + segments + 1,
            d = c + 1;
        triangle(
          points[a],
          points[b],
          points[c],
          color,
          luminous: luminous,
          na: normals[a],
          nb: normals[b],
          nc: normals[c],
        );
        triangle(
          points[b],
          points[d],
          points[c],
          color,
          luminous: luminous,
          na: normals[b],
          nb: normals[d],
          nc: normals[c],
        );
      }
    }
  }

  void drawSurface(Canvas canvas, Offset center, double scale) {
    if (faces.isEmpty) return;
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    Offset project(_V v) {
      final f = 3.7 / (3.7 - v.z);
      return center + Offset(v.x * scale * f, v.y * scale * f);
    }

    // A surface draw avoids seams and thousands of individual drawPaths.
    final positions = <Offset>[], colors = <Color>[];
    for (final f in faces) {
      positions.addAll([project(f.a), project(f.b), project(f.c)]);
      colors.addAll([f.ca, f.cb, f.cc]);
    }
    final mesh = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
    );
    canvas.drawVertices(mesh, BlendMode.srcOver, Paint()..color = Colors.white);
    mesh.dispose();
    faces.clear();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value * 120;
    final asleep = mode == FaceMode.sleeping;
    yaw = math.sin(t * .54) * .12 + (mode == FaceMode.thinking ? .16 : 0);
    pitch = math.sin(t * .8) * .045 + (asleep ? -.12 : 0);
    final center = Offset(
      size.width / 2,
      size.height / 2 + math.sin(t * 1.4) * 4,
    );
    final scale = math.min(size.width / 2.65, size.height / 3.0);
    final accent = mode == FaceMode.camera
        ? const Color(0xFF79F4B3)
        : mode == FaceMode.error
        ? const Color(0xFFFFB980)
        : const Color(0xFF63DFFF);
    canvas.drawCircle(
      center,
      scale * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: .12), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: scale * 1.5)),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, scale * 1.37),
        width: scale * 1.6,
        height: scale * .16,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: .6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
    faces.clear();
    ellipsoid(
      const _V(0, 0, 0),
      const _V(1, 1.07, .63),
      const Color(0xFF35617C),
      rings: 32,
      segments: 56,
    );
    // Raised dark glass visor, eyes and pupils are separate 3D volumes.
    ellipsoid(
      const _V(0, -.06, .52),
      const _V(.79, .76, .26),
      const Color(0xFF101E35),
      rings: 24,
      segments: 48,
    );
    drawSurface(canvas, center, scale);
    final cycle = t % 4.7;
    final blink = asleep
        ? .06
        : cycle > 4.48
        ? .08 + (.92 * ((cycle - 4.59).abs() / .11).clamp(0.0, 1.0))
        : 1.0;
    final eyeHeight = (mood == 'happy' ? .23 : .29) * blink;
    for (final x in [-.36, .36]) {
      ellipsoid(
        _V(x, -.20, .868),
        _V(.245, eyeHeight, .105),
        accent,
        luminous: true,
        rings: 12,
        segments: 24,
      );
      drawSurface(canvas, center, scale);
      if (blink > .3) {
        final gaze = math.sin(t * .43) * .035;
        ellipsoid(
          _V(x + gaze, -.19, .967),
          _V(.075, .125 * blink, .03),
          const Color(0xFF092F47),
          rings: 10,
          segments: 16,
        );
        drawSurface(canvas, center, scale);
        ellipsoid(
          _V(x + gaze - .026, -.235, .993),
          const _V(.022, .027, .012),
          const Color(0xFFF2FFFF),
          luminous: true,
          rings: 6,
          segments: 10,
        );
        drawSurface(canvas, center, scale);
      }
    }
    final speaking = mode == FaceMode.speaking;
    final opening = speaking
        ? .035 + .13 * (.5 + .5 * math.sin(t * 22)) * math.max(.3, energy)
        : .012;
    // A continuous 3D lip rim, with a dark visor interior as the mouth opens.
    _V lip(int i, int j) {
      final a = 2 * math.pi * i / 48, b = 2 * math.pi * j / 8;
      return _V(
        (.25 + .012 * math.cos(b)) * math.cos(a),
        .35 +
            .08 * math.pow(math.sin(a), 2) +
            (.012 + opening + .012 * math.cos(b)) * math.sin(a),
        .90 + .012 * math.sin(b),
      );
    }

    for (var i = 0; i < 48; i++) {
      for (var j = 0; j < 8; j++) {
        final a = lip(i, j),
            b = lip(i + 1, j),
            c = lip(i, j + 1),
            d = lip(i + 1, j + 1);
        triangle(a, b, c, accent, luminous: true);
        triangle(b, d, c, accent, luminous: true);
      }
    }
    drawSurface(canvas, center, scale);
    Offset project(_V v) {
      final f = 3.7 / (3.7 - v.z);
      return center + Offset(v.x * scale * f, v.y * scale * f);
    }

    // Small integrated forehead light conveys state without text or controls.
    final pulse = .45 + .45 * math.sin(t * (mode == FaceMode.thinking ? 6 : 2));
    final led = project(const _V(0, -.91, .31));
    canvas.drawCircle(
      led,
      3.2,
      Paint()
        ..color = accent.withValues(alpha: asleep ? .15 : pulse.clamp(.1, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) =>
      old.mode != mode || old.energy != energy || old.mood != mood;
}
