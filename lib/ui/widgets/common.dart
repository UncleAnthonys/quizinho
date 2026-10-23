import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/tournament.dart';

/// Mown-stripe pitch with faint markings, behind every screen.
class PitchBackground extends StatelessWidget {
  const PitchBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Palette.pitch, Palette.pitchDeep],
          ),
        ),
        child: CustomPaint(painter: _PitchPainter(), child: child),
      );
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.025);
    const bands = 9;
    final h = size.height / bands;
    for (var i = 0; i < bands; i += 2) {
      canvas.drawRect(Rect.fromLTWH(0, i * h, size.width, h), stripe);
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), line);
    canvas.drawCircle(c, min(size.width, size.height) * 0.22, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Big, chunky call-to-action. Designed to be hit from across a table.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Palette.lime,
    this.textColor = Palette.pitchDeep,
    this.icon,
    this.height = 64,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: enabled ? color : color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, color: textColor, size: 26), const SizedBox(width: 10)],
              Text(label.toUpperCase(), style: AppText.headline(26, color: textColor)),
            ]),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.chevron_right, color: Palette.muted),
        label: Text(label.toUpperCase(), style: AppText.label(16)),
      );
}

/// Broadcast-style score strip shown at the top during play.
class Scoreboard extends StatelessWidget {
  const Scoreboard({super.key, required this.tournament, this.highlightTeam, this.extra});
  final Tournament tournament;
  final int? highlightTeam;

  /// Optional per-team extra (e.g. round points or lives) shown under the score.
  final String Function(int team)? extra;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('RD', style: AppText.label(11)),
            Text('${min(t.roundNumber, t.totalRounds)}/${t.totalRounds}', style: AppText.headline(18)),
          ]),
        ),
        for (var i = 0; i < t.teamCount; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              decoration: BoxDecoration(
                color: highlightTeam == i
                    ? Palette.team(t.config.teams[i].colorIndex).withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: Palette.team(t.config.teams[i].colorIndex), width: 5),
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  t.teamName(i).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(13, color: Palette.text),
                ),
                Text('${t.scores[i]}', style: AppText.headline(26)),
                if (extra != null) Text(extra!(i), style: AppText.label(11)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Horizontal countdown bar that turns red as time runs out.
class TimerBar extends StatelessWidget {
  const TimerBar({super.key, required this.fraction, this.seconds, this.height = 14});
  final double fraction;
  final double? seconds;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    final color = Color.lerp(Palette.danger, Palette.lime, f)!;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Stack(children: [
            Container(height: height, color: Colors.white.withValues(alpha: 0.08)),
            FractionallySizedBox(widthFactor: f, child: Container(height: height, color: color)),
          ]),
        ),
      ),
      if (seconds != null) ...[
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(seconds!.ceil().toString(), textAlign: TextAlign.right, style: AppText.headline(28, color: color)),
        ),
      ],
    ]);
  }
}

/// Floating one-liner from the "commentator".
class CommentaryBanner extends StatelessWidget {
  const CommentaryBanner({super.key, required this.text});
  final String? text;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: text == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Container(
                key: ValueKey(text),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Palette.gold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.mic_external_on, color: Palette.pitchDeep, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text!,
                      style: AppText.headline(20, color: Palette.pitchDeep, weight: FontWeight.w800),
                    ),
                  ),
                ]),
              ),
      );
}

class TeamChip extends StatelessWidget {
  const TeamChip({super.key, required this.name, required this.colorIndex, this.size = 18});
  final String name;
  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.6, vertical: size * 0.25),
        decoration: BoxDecoration(color: Palette.team(colorIndex), borderRadius: BorderRadius.circular(size)),
        child: Text(name.toUpperCase(), style: AppText.headline(size, color: Palette.onTeam(colorIndex))),
      );
}
