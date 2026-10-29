import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../match_flow.dart';
import '../widgets/common.dart';

/// Picks the next game: the games stand in a free-kick wall, one per shirt.
/// The taker runs up, the ball smacks one of them, he goes down and that's the
/// next game. The wildcard is never on show: when it's picked the wall jumps,
/// the shot skids underneath and hits a WILDCARD player lying behind the wall
/// (the "draft excluder"), and the wall steps apart so his shirt can be read. The pick itself comes from [Tournament.spin], and the animation
/// just aims at it.
class FreeKickScreen extends StatefulWidget {
  const FreeKickScreen({super.key, required this.tournament});
  final Tournament tournament;

  @override
  State<FreeKickScreen> createState() => _FreeKickScreenState();
}

/// Timeline of one kick, as fractions of [_FreeKickScreenState._kick].
abstract final class _Beat {
  static const strike = 0.32; // boot meets ball
  static const impact = 0.58; // ball meets shirt
  static const fall = 0.22; // how long the hit player takes to go down
}

class _FreeKickScreenState extends State<FreeKickScreen> with TickerProviderStateMixin {
  late final AnimationController _kick =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final List<GameModeId> _wall =
      widget.tournament.wheelSegments.where((m) => m != GameModeId.wildcard).toList();
  late final _ShirtLabels _labels = _ShirtLabels([..._wall, GameModeId.wildcard]);
  final _rnd = Random();

  int? _target; // wall index hit; null for the wildcard
  bool _under = false; // wildcard: low shot under the wall
  double _curl = 1;
  bool _struck = false;
  bool _hit = false;
  bool _running = false;
  GameModeId? _landed;
  GameModeId? _wildcardGame;

  AppServices get _s => AppScope.read(context);

  @override
  void initState() {
    super.initState();
    _kick.addListener(_onTick);
    // Teams picked, match on: Keegan sets the tone before the first kick.
    if (widget.tournament.rounds.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _s.sound.playClip(Clip.keegan, delay: const Duration(milliseconds: 400));
      });
    }
  }

  @override
  void dispose() {
    _kick.dispose();
    _idle.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _onTick() {
    final v = _kick.value;
    if (!_struck && v >= _Beat.strike) {
      _struck = true;
      _s.sound.play(Sfx.kick);
      _s.haptic(HapticStrength.medium);
    }
    if (!_hit && v >= _Beat.impact) {
      _hit = true;
      _s.sound.play(Sfx.kick, volume: 0.8);
      _s.sound.play(Sfx.ooh);
      _s.haptic(HapticStrength.heavy);
    }
  }

  Future<void> _go() async {
    if (_running || _landed != null) return;
    final target = widget.tournament.spin();
    setState(() {
      _running = true;
      _under = target == GameModeId.wildcard;
      _target = _under ? null : _wall.indexOf(target);
      _curl = _rnd.nextBool() ? 1 : -1;
    });
    _s.sound.play(Sfx.whistle, volume: 0.6);
    await _kick.forward(from: 0);
    if (!mounted) return;
    _idle.stop();
    _s.sound.play(Sfx.reveal);
    GameModeId? real;
    if (target == GameModeId.wildcard) real = widget.tournament.resolveWildcard();
    setState(() {
      _running = false;
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
            Expanded(
              child: GestureDetector(
                onTap: _go,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _FreeKickPainter(
                    segments: _wall,
                    labels: _labels,
                    kick: _kick,
                    idle: _idle,
                    going: _running || _landed != null,
                    target: _target,
                    under: _under,
                    curl: _curl,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 190,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: landed == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        BigButton(
                          label: _running ? 'Here it comes…' : (t.isFinalRound ? 'Pick final game' : 'Pick next game'),
                          icon: Icons.sports_soccer,
                          onPressed: _running ? null : _go,
                        ),
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

/// Shirt text, laid out once. One word per line ("BIDDING / WAR"), and words
/// are never split. The painter scales each label to fit its shirt.
class _ShirtLabels {
  _ShirtLabels(List<GameModeId> modes)
      : _byMode = {
          for (final m in modes)
            m: TextPainter(
              text: TextSpan(
                text: m.wheelLabel.split(' ').join('\n'),
                style: const TextStyle(
                  fontFamily: AppText.display,
                  fontWeight: FontWeight.w900,
                  fontSize: base,
                  height: 0.95,
                  color: Palette.pitchDeep,
                ),
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
            )..layout(),
        };

  static const double base = 40;
  final Map<GameModeId, TextPainter> _byMode;

  late final TextPainter number = TextPainter(
    text: const TextSpan(
      text: '10',
      style: TextStyle(fontFamily: AppText.display, fontWeight: FontWeight.w900, fontSize: base, color: Palette.green),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Paints [m]'s label centred on [centre], fitted inside [box].
  void paint(Canvas canvas, GameModeId m, Offset centre, Size box, {double maxFont = double.infinity}) =>
      _fit(canvas, _byMode[m]!, centre, box, maxFont);

  void paintNumber(Canvas canvas, Offset centre, Size box) => _fit(canvas, number, centre, box, double.infinity);

  static void _fit(Canvas canvas, TextPainter tp, Offset centre, Size box, double maxFont) {
    final scale = [box.width / tp.width, box.height / tp.height, maxFont / base].reduce(min);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _FreeKickPainter extends CustomPainter {
  _FreeKickPainter({
    required this.segments,
    required this.labels,
    required this.kick,
    required this.idle,
    required this.going,
    required this.target,
    required this.under,
    required this.curl,
  }) : super(repaint: Listenable.merge([kick, idle]));

  final List<GameModeId> segments;
  final _ShirtLabels labels;
  final Animation<double> kick;
  final Animation<double> idle;
  final bool going; // kick under way (or done)
  final int? target; // wall player hit; null before the kick or for the wildcard
  final bool under; // wildcard: low shot under the wall into the draft excluder
  final double curl;

  static const _skins = [
    Color(0xFFF1C296), Color(0xFF8D5536), Color(0xFFE0AC80), Color(0xFFC6865A),
    Color(0xFF6E4228), Color(0xFFE9B88C), Color(0xFFB07850),
  ];
  static const _hair = [
    Color(0xFF2A1C12), Color(0xFF111111), Color(0xFF6B4A2B), Color(0xFF1E1610),
    Color(0xFF0D0D0D), Color(0xFFB98A4E), Color(0xFF3A2614),
  ];
  static const _shorts = Color(0xFF1B2433);
  static const _taker = Palette.yellow;
  static const _takerShorts = Palette.blue;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.clipRect(Offset.zero & size);
    final t = kick.value;
    final tgt = target;
    final n = segments.length;

    // Wall geometry: one slot per game, as wide as fits.
    final slot = min(w * 0.97 / n, h * 0.17);
    final feetY = h * 0.60;
    final figH = slot * 2.25;
    final x0 = (w - slot * n) / 2;
    double px(int i) => x0 + slot * (i + 0.5);

    final spot = Offset(w * 0.5, h * 0.86);
    final ballR = max(7.0, min(w, h) * 0.03);
    // The draft excluder lies just behind the middle of the wall.
    // Lying on his side (a wall player turned 90°), feet left, head right,
    // centred behind the wall with his lower side resting on the grass.
    final lie = Offset(w / 2 - slot * 1.1, feetY - slot * 0.62);
    final excluderShirt = lie + Offset(slot * 1.37, 0);
    final chest = tgt != null ? Offset(px(tgt), feetY - figH * 0.58) : (under ? excluderShirt : spot);
    // Fall away from where the shot came from.
    final dir = tgt == null ? 1.0 : (px(tgt) >= spot.dx ? 1.0 : -1.0);

    _goal(canvas, w, h);

    // Everyone hops as the ball is struck — properly high for the low shot.
    double hop() {
      const end = _Beat.impact + 0.12;
      if (!going || t < _Beat.strike || t > end) return 0;
      return sin((t - _Beat.strike) / (end - _Beat.strike) * pi) * slot * (under ? 0.8 : 0.32);
    }

    // After the wildcard hit the wall steps apart to show who got it.
    double part(int i) {
      const from = _Beat.impact + 0.12;
      if (!under || !going || t < from) return 0;
      final u = Curves.easeInOut.transform(((t - from) / 0.2).clamp(0.0, 1.0));
      return (px(i) >= w / 2 ? 1 : -1) * slot * (n.isOdd ? 1.15 : 0.7) * u;
    }

    if (under && going && t >= _Beat.strike) {
      final hit = t >= _Beat.impact;
      final jolt = hit ? sin(((t - _Beat.impact) / 0.25).clamp(0.0, 1.0) * pi) : 0.0;
      _player(canvas, lie - Offset(0, jolt * slot * 0.2), slot, 3, pi / 2 - jolt * 0.08, hit,
          mode: GameModeId.wildcard, uprightLabel: true);
    }
    _ball(canvas, t, spot, chest, ballR, feetY, slot, dir, w, h, behindWall: true);

    final idleOn = !going;
    for (var i = 0; i < n; i++) {
      if (i == tgt) continue;
      final bob = idleOn ? sin((idle.value + i * 0.17) * 2 * pi) * slot * 0.025 : 0.0;
      _player(canvas, Offset(px(i) + part(i), feetY - hop() + bob), slot, i, 0, false);
    }
    if (tgt != null) {
      final down = t >= _Beat.impact;
      final f = down ? ((t - _Beat.impact) / _Beat.fall).clamp(0.0, 1.0) : 0.0;
      final angle = Curves.bounceOut.transform(f) * pi / 2 * 0.92 * dir;
      _player(canvas, Offset(px(tgt), feetY - (down ? 0 : hop())), slot, tgt, angle, down);
      if (down && t < _Beat.impact + 0.12) _burst(canvas, chest, slot, (t - _Beat.impact) / 0.12);
    }

    _ball(canvas, t, spot, chest, ballR, feetY, slot, dir, w, h, behindWall: false);
    _takerFigure(canvas, t, w, h, going);
  }

  void _goal(Canvas canvas, double w, double h) {
    final l = w * 0.08, r = w * 0.92, top = h * 0.05, bottom = h * 0.36;
    final net = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    const step = 12.0;
    for (var x = l; x <= r; x += step) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), net);
    }
    for (var y = top; y <= bottom; y += step) {
      canvas.drawLine(Offset(l, y), Offset(r, y), net);
    }
    canvas.drawLine(Offset(0, bottom), Offset(w, bottom),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 2);
    canvas.drawPath(
      Path()
        ..moveTo(l, bottom)
        ..lineTo(l, top)
        ..lineTo(r, top)
        ..lineTo(r, bottom),
      Paint()
        ..color = Palette.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// A wall player standing with feet at [feet], [s] = slot width, rotated
  /// [fall] radians about the feet when going down.
  ///
  /// [mode] overrides the shirt (the wildcard isn't in [segments]);
  /// [uprightLabel] keeps the shirt name level when he's lying down.
  void _player(Canvas canvas, Offset feet, double s, int i, double fall, bool hit,
      {GameModeId? mode, bool uprightLabel = false}) {
    mode ??= segments[i];
    final skin = Paint()..color = _skins[i % _skins.length];
    final sw = s * 0.94; // shoulder to shoulder, like a real wall
    RRect box(double l, double t, double r, double b, double rad) =>
        RRect.fromLTRBR(l * s, t * s, r * s, b * s, Radius.circular(rad * s));

    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    canvas.rotate(fall);

    // legs, socks, boots
    for (final side in [-1.0, 1.0]) {
      final a = side < 0 ? -0.30 : 0.06, b = side < 0 ? -0.06 : 0.30;
      canvas.drawRect(Rect.fromLTRB(a * s, -0.66 * s, b * s, -0.4 * s), skin);
      canvas.drawRect(Rect.fromLTRB(a * s, -0.42 * s, b * s, -0.08 * s), Paint()..color = Colors.white);
      canvas.drawRRect(box(a - 0.03, -0.11, b + 0.03, 0, 0.04), Paint()..color = const Color(0xFF111111));
    }
    // shorts
    canvas.drawRRect(box(-0.38, -0.94, 0.38, -0.58, 0.06), Paint()..color = _shorts);
    // shirt: sleeves, then body
    final shirt = Paint()..color = mode.color;
    canvas.drawRRect(
        RRect.fromLTRBR(-sw / 2 - 0.03 * s, -1.80 * s, sw / 2 + 0.03 * s, -1.46 * s, Radius.circular(0.12 * s)), shirt);
    final body = RRect.fromLTRBR(-sw / 2, -1.80 * s, sw / 2, -0.86 * s, Radius.circular(0.14 * s));
    if (hit) {
      // white shirts (the wildcard) glow yellow so the ring shows
      canvas.drawRRect(body.inflate(0.07 * s),
          Paint()..color = mode == GameModeId.wildcard ? Palette.yellow : Palette.text);
    }
    canvas.drawRRect(body, shirt);
    // hands together in front, the classic wall pose
    canvas.drawRRect(box(-0.20, -1.02, 0.20, -0.82, 0.10), skin);
    // name on the shirt
    if (!uprightLabel) {
      labels.paint(canvas, mode, Offset(0, -1.37 * s), Size(sw * 0.92, 0.58 * s), maxFont: 0.30 * s);
    }
    // neck and head
    canvas.drawRect(Rect.fromLTRB(-0.08 * s, -1.92 * s, 0.08 * s, -1.76 * s), skin);
    final head = Offset(0, -2.02 * s);
    canvas.drawCircle(head, 0.24 * s, skin);
    canvas.drawArc(Rect.fromCircle(center: head + Offset(0, -0.02 * s), radius: 0.255 * s), pi, pi, true,
        Paint()..color = _hair[i % _hair.length]);
    canvas.restore();
    if (uprightLabel) {
      // shirt centre (0, -1.37s) after turning by [fall]
      final centre = feet + Offset(1.37 * s * sin(fall), -1.37 * s * cos(fall));
      labels.paint(canvas, mode, centre, Size(0.84 * s, 0.5 * s), maxFont: 0.30 * s);
    }
  }

  void _burst(Canvas canvas, Offset at, double s, double u) {
    final p = Paint()
      ..color = Palette.yellow.withValues(alpha: 1 - u)
      ..strokeWidth = max(2, s * 0.06)
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 10; k++) {
      final a = k * 2 * pi / 10;
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(at + d * s * (0.5 + u * 0.3), at + d * s * (0.8 + u * 0.6), p);
    }
  }

  /// Drawn in two passes so it can pass under the wall: [behindWall] draws it
  /// only while it's further away than the wall's feet, otherwise only in front.
  void _ball(Canvas canvas, double t, Offset spot, Offset chest, double r0, double feetY, double s, double dir,
      double w, double h, {required bool behindWall}) {
    Offset pos;
    double r;
    double groundY;
    double spin = 0;
    if (!going || t < _Beat.strike) {
      pos = spot;
      r = r0;
      groundY = spot.dy;
    } else if (under && t < _Beat.impact) {
      // Low and hard along the grass, under the jumping wall.
      final u = (t - _Beat.strike) / (_Beat.impact - _Beat.strike);
      pos = Offset.lerp(spot, chest, u)! + Offset(curl * w * 0.05 * sin(u * pi), 0);
      r = _lerp(r0, r0 * 0.75, u);
      groundY = pos.dy;
      spin = u * 14;
    } else if (under) {
      // Cannons off him back towards the wall's feet and stops.
      final u = Curves.easeOut.transform(((t - _Beat.impact) / 0.3).clamp(0.0, 1.0));
      pos = chest + Offset(-curl * s * 0.5 * u, s * 0.62 * u);
      r = r0 * 0.75;
      groundY = pos.dy;
      spin = 14 + u * 3;
    } else if (t < _Beat.impact) {
      final u = Curves.easeIn.transform((t - _Beat.strike) / (_Beat.impact - _Beat.strike)) * 0.85 +
          (t - _Beat.strike) / (_Beat.impact - _Beat.strike) * 0.15;
      final ctrl = Offset((spot.dx + chest.dx) / 2 + curl * w * 0.30, (spot.dy + chest.dy) / 2 - h * 0.04);
      pos = Offset(
        (1 - u) * (1 - u) * spot.dx + 2 * (1 - u) * u * ctrl.dx + u * u * chest.dx,
        (1 - u) * (1 - u) * spot.dy + 2 * (1 - u) * u * ctrl.dy + u * u * chest.dy,
      );
      r = _lerp(r0, r0 * 0.72, u);
      groundY = _lerp(spot.dy, feetY, u);
      spin = u * 12;
    } else {
      // Rebound: drops in front of the wall, bounces once, rolls off.
      final u = ((t - _Beat.impact) / (1 - _Beat.impact)).clamp(0.0, 1.0);
      final ground = feetY + s * 0.35;
      final drop = min(1.0, u * 2.4);
      final bounce = u > 0.42 ? sin(((u - 0.42) / 0.58).clamp(0.0, 1.0) * pi) * s * 0.45 : 0.0;
      pos = Offset(chest.dx - dir * w * 0.16 * Curves.easeOut.transform(u),
          _lerp(chest.dy, ground, Curves.easeIn.transform(drop)) - bounce);
      r = r0 * 0.75;
      groundY = ground;
      spin = 12 + u * 6;
    }
    // Only the low shot ever goes behind the wall; a normal shot stays in front.
    if (under ? (pos.dy < feetY) != behindWall : behindWall) return;
    // shadow
    canvas.drawOval(Rect.fromCenter(center: Offset(pos.dx, groundY + r * 0.9), width: r * 2, height: r * 0.6),
        Paint()..color = Colors.black.withValues(alpha: 0.3));
    canvas.drawCircle(pos, r, Paint()..color = Colors.white);
    canvas.drawCircle(pos, r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, r * 0.12)
          ..color = Colors.black87);
    final patch = Path();
    for (var k = 0; k < 5; k++) {
      final a = spin + k * 2 * pi / 5;
      final p = pos + Offset(cos(a), sin(a)) * r * 0.38;
      if (k == 0) {
        patch.moveTo(p.dx, p.dy);
      } else {
        patch.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(patch..close(), Paint()..color = Colors.black87);
  }

  /// The taker, seen from behind: runs in from bottom-left, strikes, follows through.
  void _takerFigure(Canvas canvas, double t, double w, double h, bool going) {
    final k = h * 0.085;
    const start = Offset(0.14, 1.03), end = Offset(0.42, 0.95);
    double run = going ? (t / _Beat.strike).clamp(0.0, 1.0) : 0.0;
    run = Curves.easeIn.transform(run) * 0.7 + run * 0.3;
    var feet = Offset(_lerp(start.dx, end.dx, run) * w, _lerp(start.dy, end.dy, run) * h);
    if (going && t > _Beat.strike) {
      final f = ((t - _Beat.strike) / 0.15).clamp(0.0, 1.0);
      feet += Offset(w * 0.03, -h * 0.02) * Curves.easeOut.transform(f);
    }
    final phase = run * 5 * 2 * pi;
    var liftL = going && run < 1 ? max(0.0, sin(phase)) : 0.0;
    var liftR = going && run < 1 ? max(0.0, -sin(phase)) : 0.0;
    // The strike: right leg swings through.
    if (going && t > _Beat.strike - 0.04 && t < _Beat.strike + 0.12) {
      final u = ((t - (_Beat.strike - 0.04)) / 0.16).clamp(0.0, 1.0);
      liftR = sin(u * pi) * 1.6;
      liftL = 0;
    }
    final skin = Paint()..color = const Color(0xFFC6865A);

    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    for (final (a, b, lift) in [(-0.32, -0.06, liftL), (0.06, 0.32, liftR)]) {
      final up = lift * 0.35 * k;
      canvas.drawRect(Rect.fromLTRB(a * k, -1.0 * k, b * k, -0.55 * k - up), skin);
      canvas.drawRect(Rect.fromLTRB(a * k, -0.58 * k - up, b * k, -0.1 * k - up), Paint()..color = Colors.white);
      canvas.drawRRect(
          RRect.fromLTRBR((a - 0.03) * k, -0.14 * k - up, (b + 0.03) * k, -up, Radius.circular(0.05 * k)),
          Paint()..color = const Color(0xFF111111));
    }
    // arms swing opposite the legs
    for (final (side, swing) in [(-1.0, liftR - liftL), (1.0, liftL - liftR)]) {
      final x = side * 0.56 * k;
      final dy = swing * 0.18 * k;
      canvas.drawRRect(
          RRect.fromLTRBR(x - 0.1 * k, -2.25 * k + dy, x + 0.1 * k, -1.45 * k + dy, Radius.circular(0.1 * k)), skin);
    }
    canvas.drawRRect(RRect.fromLTRBR(-0.42 * k, -1.38 * k, 0.42 * k, -0.9 * k, Radius.circular(0.08 * k)),
        Paint()..color = _takerShorts);
    final shirt = Paint()..color = _taker;
    canvas.drawRRect(RRect.fromLTRBR(-0.62 * k, -2.42 * k, 0.62 * k, -2.0 * k, Radius.circular(0.16 * k)), shirt);
    canvas.drawRRect(RRect.fromLTRBR(-0.48 * k, -2.42 * k, 0.48 * k, -1.28 * k, Radius.circular(0.16 * k)), shirt);
    labels.paintNumber(canvas, Offset(0, -1.85 * k), Size(0.6 * k, 0.5 * k));
    canvas.drawRect(Rect.fromLTRB(-0.1 * k, -2.55 * k, 0.1 * k, -2.38 * k), skin);
    canvas.drawCircle(Offset(0, -2.72 * k), 0.3 * k, Paint()..color = const Color(0xFF1E1610));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FreeKickPainter old) =>
      old.going != going ||
      old.target != target ||
      old.under != under ||
      old.curl != curl ||
      old.segments != segments;
}
