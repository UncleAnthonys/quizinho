import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/web_keyboard.dart';
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
    this.color = Palette.yellow,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              // shrinks to fit narrow buttons instead of spilling out
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, color: textColor, size: 26), const SizedBox(width: 10)],
                  Text(label.toUpperCase(), style: AppText.headline(26, color: textColor)),
                ]),
              ),
            ),
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
    return ScoreStrip(
      round: '${min(t.roundNumber, t.totalRounds)}/${t.totalRounds}',
      teams: [for (var i = 0; i < t.teamCount; i++) (t.teamName(i), t.config.teams[i].colorIndex, t.scores[i])],
      highlightTeam: highlightTeam,
      extra: extra,
      showExit: true,
    );
  }
}

/// The score strip itself, from plain data — the same look on joined phones.
class ScoreStrip extends StatelessWidget {
  const ScoreStrip({
    super.key,
    required this.round,
    required this.teams,
    this.highlightTeam,
    this.extra,
    this.showExit = false,
  });

  /// "2/6"
  final String round;

  /// (name, colour index, score) per team.
  final List<(String, int, int)> teams;
  final int? highlightTeam;
  final String Function(int team)? extra;
  final bool showExit;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.line),
        ),
        // Every team's box the same height (a long "extra" no longer makes
        // one taller), however many teams there are.
        child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showExit) const Center(child: ExitMatchButton()) else const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('RD', style: AppText.label(11)),
              Text(round, style: AppText.headline(18)),
            ]),
          ),
          for (final (i, (name, colour, score)) in teams.indexed)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                decoration: BoxDecoration(
                  color: highlightTeam == i
                      ? Palette.team(colour).withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: Palette.team(colour), width: 5)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(name.toUpperCase(), style: AppText.label(13, color: Palette.text)),
                  ),
                  Text('$score', style: AppText.headline(26)),
                  // One line, shrunk to fit a narrow box (four or more teams).
                  if (extra != null)
                    FittedBox(fit: BoxFit.scaleDown, child: Text(extra!(i), maxLines: 1, style: AppText.label(11))),
                ]),
              ),
            ),
        ])),
      );
}

/// Leave the match: asks "Abandon match?" first (the match flow's guard), then home.
class ExitMatchButton extends StatelessWidget {
  const ExitMatchButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Leave match',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.close_rounded, color: Palette.muted),
        onPressed: () => Navigator.of(context).maybePop(),
      );
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
    final color = Color.lerp(Palette.danger, Palette.yellow, f)!;
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

/// The pundit's line, in place of the game's title line ([child]) for as
/// long as it shows: the title fades out, a slim gold strip fades in where it
/// was, then the title comes back. Takes no room of its own, so nothing jumps,
/// and covers nothing but the title.
class CommentaryBanner extends StatelessWidget {
  const CommentaryBanner({super.key, required this.text, required this.child});
  final String? text;
  final Widget child;

  static const _fade = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
      AnimatedOpacity(opacity: text == null ? 1 : 0, duration: _fade, child: IgnorePointer(ignoring: text != null, child: child)),
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: _fade,
            child: text == null
                ? const SizedBox.shrink(key: ValueKey('none'))
                : Padding(
                    key: ValueKey(text),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    // A long line wraps onto two rather than shrinking to fit
                    // one; it may stand taller than what it covers.
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(8)),
                        child: Text.rich(
                          TextSpan(children: [
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.mic_external_on, color: Palette.pitchDeep, size: 16),
                              ),
                            ),
                            TextSpan(text: text),
                          ]),
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: AppText.headline(17, color: Palette.pitchDeep, weight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    ]);
  }
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

/// Whose turn it is when they're playing it on their own phone: one line,
/// so the game keeps the room (Top 10's list, the grid). A phone that drops
/// out stops checking in and its turns come back to this one by themselves.
class OnTheirPhone extends StatelessWidget {
  const OnTheirPhone({super.key, required this.name, this.what = 'is answering'});
  final String name;
  final String what;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.phone_iphone_rounded, color: Palette.yellow, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text('${name.toUpperCase()} $what'.toUpperCase(),
                overflow: TextOverflow.ellipsis, style: AppText.headline(18)),
          ),
          Text('  on their phone', style: AppText.label(12)),
        ]),
      );
}

/// Solo play: the round's score out of 100, where a team match shows who won.
class SoloScore extends StatelessWidget {
  const SoloScore({super.key, required this.score, this.color = Palette.yellow});
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('YOUR SCORE', style: AppText.label(15, color: Palette.text)),
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('$score', style: AppText.headline(72, color: color)),
          Text(' / 100', style: AppText.headline(28, color: Palette.muted)),
        ]),
      ]);
}

/// A line of rules with the points ("+3", "+1") in yellow, as on the score
/// screens, so it's clear they're points.
class RuleText extends StatelessWidget {
  const RuleText(this.text, {super.key, this.style = const TextStyle(fontSize: 18, height: 1.35)});
  final String text;
  final TextStyle style;

  static final _points = RegExp(r'\+\d+');

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in _points.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m[0], style: const TextStyle(color: Palette.yellow, fontWeight: FontWeight.w800)));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// Holds a typing layout until the keyboard has really gone. [active] is
/// "typing now"; when it ends (an answer's gone in), [builder] still gets
/// `folded: true` until the keyboard has finished sliding away, so what was
/// folded (the Noughts & Crosses board) comes back in one go onto a still
/// screen, not half-covered while the keyboard drops. Browsers only (they
/// close the keyboard slowly); in the app it's a pass-through.
class KeyboardSettle extends StatefulWidget {
  const KeyboardSettle({super.key, required this.active, required this.builder});
  final bool active;
  final Widget Function(BuildContext context, bool folded) builder;

  /// Always held at least this long, then until the keyboard reads 0.
  static const minHold = Duration(milliseconds: 450);
  static const maxHold = Duration(milliseconds: 1500);

  @override
  State<KeyboardSettle> createState() => _KeyboardSettleState();
}

class _KeyboardSettleState extends State<KeyboardSettle> {
  bool _held = false;
  Timer? _check;
  final _since = Stopwatch();

  @override
  void didUpdateWidget(KeyboardSettle old) {
    super.didUpdateWidget(old);
    // Browsers only: the app closes its keyboard smoothly already.
    if (kIsWeb && old.active && !widget.active) {
      _held = true;
      _since
        ..reset()
        ..start();
      _schedule();
    } else if (widget.active) {
      _held = false;
      _check?.cancel();
    }
  }

  void _schedule() {
    _check?.cancel();
    _check = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_held) return;
      final keyboard = keyboardInset.value + MediaQuery.viewInsetsOf(context).bottom;
      final waited = _since.elapsed;
      if ((keyboard == 0 && waited >= KeyboardSettle.minHold) || waited >= KeyboardSettle.maxHold) {
        setState(() => _held = false);
      } else {
        _schedule();
      }
    });
  }

  @override
  void dispose() {
    _check?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.active || _held);
}

/// Part of a game screen that makes way for the keyboard. In a browser it
/// slides shut (and back) in step with the keyboard instead of vanishing in
/// one frame, which looked jerky on joined phones; in the app it's instant,
/// as the app's keyboard handling already looks smooth. Stays built while
/// hidden, so nothing resets.
class Collapse extends StatelessWidget {
  const Collapse({super.key, required this.hidden, required this.child});
  final bool hidden;
  final Widget child;

  static const duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: hidden ? 0 : 1),
        duration: kIsWeb ? duration : Duration.zero,
        curve: Curves.easeOutCubic,
        child: child,
        // Always the same shape, so what's inside keeps its state.
        // Coming back (the keyboard closing) it's simply there, as in the app:
        // growing while the keyboard slid away showed a half-drawn board.
        // Going, it folds away.
        builder: (context, v, child) => ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: hidden ? v : 1,
            child: Opacity(opacity: hidden ? v : 1, child: IgnorePointer(ignoring: hidden, child: child)),
          ),
        ),
      );
}

/// A wrong answer: the question card (or the square) shakes and flashes
/// red - on the main phone and every joined phone at once. [trigger]
/// changes once per wrong answer (the game's event serial); null = nothing.
/// [delay]: wait first (a square on a board that's sliding back into view
/// as the keyboard closes).
class MissShake extends StatefulWidget {
  const MissShake({super.key, required this.trigger, required this.child, this.delay = Duration.zero});
  final int? trigger;
  final Widget child;
  final Duration delay;

  @override
  State<MissShake> createState() => _MissShakeState();
}

class _MissShakeState extends State<MissShake> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  Timer? _wait;

  /// The last wrong answer shaken, app-wide: a wrong answer often swaps the
  /// screen's layout (answering -> steal), so the card showing it is a new
  /// one - it must still play, but only once.
  static int? _played;

  @override
  void initState() {
    super.initState();
    _maybePlay();
  }

  @override
  void didUpdateWidget(MissShake old) {
    super.didUpdateWidget(old);
    _maybePlay();
  }

  void _maybePlay() {
    final t = widget.trigger;
    if (t == null || t == _played) return;
    _played = t;
    _wait?.cancel();
    if (widget.delay == Duration.zero) {
      _a.forward(from: 0);
    } else {
      _wait = Timer(widget.delay, () {
        if (mounted) _a.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (context, child) {
          final t = _a.value;
          // A quick shake in the first half; the red flashes up and fades.
          final shake = _a.isAnimating && t < 0.5 ? sin(t / 0.5 * pi * 6) * 12 * (1 - t / 0.5) : 0.0;
          final red = !_a.isAnimating ? 0.0 : (t < 0.12 ? t / 0.12 : 1 - (t - 0.12) / 0.88).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(shake, 0),
            // The card's own shape turns red; what's on it still shows.
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(Palette.danger.withValues(alpha: 0.6 * red), BlendMode.srcATop),
              child: child,
            ),
          );
        },
      );
}
