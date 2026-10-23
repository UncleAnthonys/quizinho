import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Quizinho badge: the Brazil flag's yellow diamond and blue globe,
/// with a football where the stars would be.
class QuizinhoBadge extends StatelessWidget {
  const QuizinhoBadge({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.45,
        height: size,
        child: CustomPaint(
          painter: _DiamondPainter(),
          child: Center(
            child: Container(
              width: size * 0.62,
              height: size * 0.62,
              decoration: BoxDecoration(
                color: Palette.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: size * 0.035),
              ),
              child: Icon(Icons.sports_soccer, color: Colors.white, size: size * 0.42),
            ),
          ),
        ),
      );
}

class _DiamondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final diamond = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w / 2, h)
      ..lineTo(0, h / 2)
      ..close();
    canvas.drawShadow(diamond, Colors.black, 6, false);
    canvas.drawPath(diamond, Paint()..color = Palette.yellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "QUIZ" in white, "INHO" in canary yellow.
class QuizinhoWordmark extends StatelessWidget {
  const QuizinhoWordmark({super.key, this.size = 76});
  final double size;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: 'QUIZ', style: AppText.headline(size)),
            TextSpan(text: 'INHO', style: AppText.headline(size, color: Palette.yellow)),
          ]),
        ),
      );
}
