import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Quizinho club badge: oval crest with the name arched over the top, 2026
/// underneath, and a split field — Brazil on the left, England on the right.
class QuizinhoBadge extends StatelessWidget {
  const QuizinhoBadge({super.key, this.size = 150});

  /// Badge height. Width is 260/320 of the height.
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 260 / 320, size), painter: _BadgePainter());
}

class _BadgePainter extends CustomPainter {
  static const _navy = Color(0xFF0F235A);
  static const _green = Color(0xFF009C3B);
  static const _red = Color(0xFFCE1124);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.height / 320; // design units → pixels
    final c = size.center(Offset.zero);
    Rect oval(double rx, double ry) => Rect.fromCenter(center: c, width: 2 * rx * k, height: 2 * ry * k);

    canvas.drawShadow(Path()..addOval(oval(122, 152)), Colors.black, 10, false);
    canvas.drawOval(oval(122, 152), Paint()..color = Palette.yellow); // gold rim
    canvas.drawOval(oval(116, 146), Paint()..color = _navy); // name ring
    canvas.drawOval(oval(84, 112), Paint()..color = Palette.yellow); // inner rim

    // Split field, clipped to the inner oval.
    final field = oval(80, 108);
    canvas.save();
    canvas.clipPath(Path()..addOval(field));
    // Left: Brazil
    canvas.drawRect(Rect.fromLTRB(field.left, field.top, c.dx, field.bottom), Paint()..color = _green);
    final lx = c.dx - field.width / 4 - 2 * k;
    canvas.drawPath(
      Path()
        ..moveTo(lx, c.dy - 62 * k)
        ..lineTo(lx + 34 * k, c.dy)
        ..lineTo(lx, c.dy + 62 * k)
        ..lineTo(lx - 34 * k, c.dy)
        ..close(),
      Paint()..color = Palette.yellow,
    );
    canvas.drawCircle(Offset(lx, c.dy), 20 * k, Paint()..color = Palette.blue);
    // Right: England (St George's cross)
    canvas.drawRect(Rect.fromLTRB(c.dx, field.top, field.right, field.bottom), Paint()..color = Colors.white);
    final rx = c.dx + field.width / 4;
    canvas.drawRect(Rect.fromLTRB(rx - 9 * k, field.top, rx + 9 * k, field.bottom), Paint()..color = _red);
    canvas.drawRect(Rect.fromLTRB(c.dx, c.dy - 9 * k, field.right, c.dy + 9 * k), Paint()..color = _red);
    // Gold divider
    canvas.drawRect(Rect.fromLTRB(c.dx - 2 * k, field.top, c.dx + 2 * k, field.bottom), Paint()..color = Palette.yellow);
    canvas.restore();

    _arcText(canvas, c, k, 'QUIZINHO', centerDeg: -90, spreadDeg: 92, size: 30, top: true);
    _arcText(canvas, c, k, '2026', centerDeg: 90, spreadDeg: 40, size: 32, top: false);
  }

  /// Letters placed one by one around the ring, upright to the reader.
  void _arcText(Canvas canvas, Offset c, double k, String text,
      {required double centerDeg, required double spreadDeg, required double size, required bool top}) {
    final n = text.length;
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1) - 0.5;
      final deg = centerDeg + spreadDeg * t * (top ? 1 : -1);
      final rad = deg * 3.141592653589793 / 180;
      final pos = c + Offset(100 * k * _cos(rad), (top ? 128 : 129) * k * _sin(rad));
      final tp = TextPainter(
        text: TextSpan(
          text: text[i],
          style: TextStyle(fontFamily: AppText.display, fontWeight: FontWeight.w900, fontSize: size * k, color: Colors.white, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate((top ? deg + 90 : deg - 90) * 3.141592653589793 / 180);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  static double _sin(double r) => math.sin(r);
  static double _cos(double r) => math.cos(r);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Slanted "QUIZ" (white) + "INHO" (gold), with a gold/blue kit-trim underline.
class QuizinhoWordmark extends StatelessWidget {
  const QuizinhoWordmark({super.key, this.size = 76});
  final double size;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.14),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'QUIZ', style: AppText.headline(size)),
                TextSpan(text: 'INHO', style: AppText.headline(size, color: Palette.yellow)),
              ]),
            ),
          ),
          SizedBox(height: size * 0.12),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: size * 1.1, height: size * 0.055, color: Palette.yellow),
            SizedBox(width: size * 0.1),
            Container(width: size * 1.1, height: size * 0.055, color: Palette.blue),
          ]),
        ]),
      );
}
