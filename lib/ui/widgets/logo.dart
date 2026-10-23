import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Quizinho crest: royal-blue shield with a gold rim, the white band from the
/// Brazil flag sweeping across, and a gold "Q".
class QuizinhoBadge extends StatelessWidget {
  const QuizinhoBadge({super.key, this.size = 150});

  /// Crest height. Width is ~0.88 × height.
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 150 / 170, size), painter: _CrestPainter());
}

class _CrestPainter extends CustomPainter {
  static Path _shield(Rect r) {
    final x = r.left, y = r.top, w = r.width, h = r.height, c = 0.06 * w;
    return Path()
      ..moveTo(x, y + c)
      ..quadraticBezierTo(x, y, x + c, y)
      ..lineTo(x + w - c, y)
      ..quadraticBezierTo(x + w, y, x + w, y + c)
      ..lineTo(x + w, y + 0.56 * h)
      ..quadraticBezierTo(x + w, y + 0.86 * h, x + w / 2, y + h)
      ..quadraticBezierTo(x, y + 0.86 * h, x, y + 0.56 * h)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outer = _shield(Offset.zero & size);
    final b = 0.055 * w;
    final inner = _shield(Rect.fromLTWH(b, b, w - 2 * b, h - 2 * b * 1.15));

    canvas.drawShadow(outer, Colors.black, 10, false);
    canvas.drawPath(outer, Paint()..color = Palette.yellow);
    canvas.drawPath(inner, Paint()..color = Palette.blue);

    // White band, clipped to the blue field.
    final band = Path()
      ..moveTo(b, 0.58 * h)
      ..quadraticBezierTo(w / 2, 0.38 * h, w - b, 0.50 * h)
      ..lineTo(w - b, 0.58 * h)
      ..quadraticBezierTo(w / 2, 0.46 * h, b, 0.66 * h)
      ..close();
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawPath(band, Paint()..color = Colors.white);
    canvas.restore();

    // Gold Q with a blue keyline so it cuts cleanly over the band.
    final fontSize = 0.54 * h;
    TextPainter q(Paint fg) => TextPainter(
          text: TextSpan(
            text: 'Q',
            style: TextStyle(fontFamily: AppText.body, fontWeight: FontWeight.w800, fontSize: fontSize, height: 1, foreground: fg),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    final stroke = q(Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035 * h
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.blue);
    final fill = q(Paint()..color = Palette.yellow);
    final at = Offset((w - fill.width) / 2 + 0.01 * w, 0.17 * h);
    stroke.paint(canvas, at);
    fill.paint(canvas, at);
  }

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
