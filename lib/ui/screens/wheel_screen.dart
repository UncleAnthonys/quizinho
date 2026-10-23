import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../match_flow.dart';
import '../widgets/common.dart';

/// "NEXT CHALLENGE" — spin the wheel to pick the next game.
class WheelScreen extends StatefulWidget {
  const WheelScreen({super.key, required this.tournament});
  final Tournament tournament;

  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late List<GameModeId> _segments;
  Animation<double>? _angle;
  double _rotation = 0;
  int _lastSegment = -1;
  GameModeId? _landed;
  GameModeId? _wildcardGame;
  bool _spinning = false;

  AppServices get _s => AppScope.read(context);

  @override
  void initState() {
    super.initState();
    _segments = widget.tournament.wheelSegments;
    _spin.addListener(_onSpinTick);
  }

  @override
  void dispose() {
    _spin.dispose();
    _reveal.dispose();
    super.dispose();
  }

  double get _segAngle => 2 * pi / _segments.length;

  int _segmentAt(double rotation) {
    final local = (-rotation) % (2 * pi);
    return (local / _segAngle).floor() % _segments.length;
  }

  void _onSpinTick() {
    final a = _angle?.value ?? _rotation;
    setState(() => _rotation = a);
    final seg = _segmentAt(a);
    if (seg != _lastSegment) {
      _lastSegment = seg;
      _s.sound.play(Sfx.spinTick, volume: 0.5);
      _s.haptic(HapticStrength.tick);
    }
  }

  Future<void> _go() async {
    if (_spinning || _landed != null) return;
    setState(() => _spinning = true);
    final target = widget.tournament.spin();
    final i = _segments.indexOf(target);
    final jitter = (Random().nextDouble() - 0.5) * _segAngle * 0.6;
    final desired = (-(i + 0.5) * _segAngle + jitter) % (2 * pi);
    final current = _rotation % (2 * pi);
    final delta = (desired - current) % (2 * pi);
    final end = _rotation + 2 * pi * 5 + delta;
    _angle = Tween(begin: _rotation, end: end).animate(CurvedAnimation(parent: _spin, curve: Curves.easeOutQuart));
    await _spin.forward(from: 0);
    if (!mounted) return;
    _s.sound.play(Sfx.reveal);
    _s.haptic(HapticStrength.heavy);
    GameModeId? real;
    if (target == GameModeId.wildcard) real = widget.tournament.resolveWildcard();
    setState(() {
      _spinning = false;
      _landed = target;
      _wildcardGame = real;
    });
    _reveal.forward(from: 0);
  }

  void _continue() {
    final landed = _landed!;
    final mode = _wildcardGame ?? landed;
    MatchFlow.toIntro(context, widget.tournament, mode, landed == GameModeId.wildcard ? 2 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final landed = _landed;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            Scoreboard(tournament: t),
            const SizedBox(height: 12),
            Text(t.isFinalRound ? 'FINAL ROUND' : 'NEXT CHALLENGE',
                style: AppText.headline(40, color: t.isFinalRound ? Palette.gold : Palette.text)),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: _go,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Stack(alignment: Alignment.center, children: [
                        Transform.rotate(
                          angle: _rotation,
                          child: CustomPaint(size: Size.infinite, painter: _WheelPainter(_segments)),
                        ),
                        // hub
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            color: Palette.pitchDeep,
                            shape: BoxShape.circle,
                            border: Border.all(color: Palette.text, width: 4),
                          ),
                          child: const Icon(Icons.sports_soccer, color: Palette.text, size: 44),
                        ),
                        // pointer
                        const Align(
                          alignment: Alignment.topCenter,
                          child: Icon(Icons.arrow_drop_down_rounded, color: Palette.text, size: 72),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 210,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: landed == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(_spinning ? '' : 'TAP THE WHEEL OR', style: AppText.label(14)),
                        const SizedBox(height: 8),
                        BigButton(label: _spinning ? 'Spinning…' : 'Spin', icon: Icons.casino, onPressed: _spinning ? null : _go),
                      ])
                    : ScaleTransition(
                        scale: CurvedAnimation(parent: _reveal, curve: Curves.elasticOut),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Icon(landed.icon, color: landed.color, size: 38),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(landed.title.toUpperCase(), style: AppText.headline(48, color: landed.color)),
                          ),
                          if (_wildcardGame != null)
                            Text('${_wildcardGame!.title.toUpperCase()} · DOUBLE POINTS',
                                style: AppText.headline(22, color: Palette.text)),
                          const SizedBox(height: 12),
                          BigButton(label: "Let's go", icon: Icons.arrow_forward, onPressed: _continue),
                        ]),
                      ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.segments);
  final List<GameModeId> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    final seg = 2 * pi / segments.length;

    for (var i = 0; i < segments.length; i++) {
      final m = segments[i];
      final start = -pi / 2 + i * seg;
      canvas.drawArc(rect, start, seg, true, Paint()..color = m.color);
      // darker inner band for depth
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.55), start, seg, true,
          Paint()..color = Colors.black.withValues(alpha: 0.12));
      canvas.drawLine(c, c + Offset(cos(start), sin(start)) * r,
          Paint()
            ..color = Palette.pitchDeep
            ..strokeWidth = 4);

      // label along the segment's centre line
      final mid = start + seg / 2;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(mid);
      final tp = TextPainter(
        text: TextSpan(
          text: m.wheelLabel,
          style: TextStyle(
            fontFamily: AppText.display,
            fontWeight: FontWeight.w900,
            fontSize: r * (segments.length > 4 ? 0.11 : 0.13),
            color: Palette.pitchDeep,
            letterSpacing: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r * 0.62);
      tp.paint(canvas, Offset(r * 0.95 - tp.width, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Palette.text);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.segments != segments;
}
