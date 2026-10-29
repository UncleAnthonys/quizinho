import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../match_access.dart';
import '../widgets/common.dart';

class WinnerScreen extends StatefulWidget {
  const WinnerScreen({super.key, required this.tournament});
  final Tournament tournament;

  @override
  State<WinnerScreen> createState() => _WinnerScreenState();
}

class _WinnerScreenState extends State<WinnerScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final List<_Bit> _bits;
  String _line = '';

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    final colours = [Palette.gold, Palette.yellow, Colors.white, ...Palette.teams];
    _bits = List.generate(90, (_) => _Bit(rnd.nextDouble(), rnd.nextDouble(), 0.5 + rnd.nextDouble(),
        colours[rnd.nextInt(colours.length)], rnd.nextDouble() * pi));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = AppScope.read(context);
      // The free cup is done: the next match is the full game.
      if (widget.tournament.config.warmUp) s.settings.markWarmUpPlayed();
      s.sound.play(Sfx.whistle);
      s.sound.play(Sfx.fanfare);
      s.sound.play(Sfx.cheer);
      s.sound.playClip(Clip.mcmanaman, delay: const Duration(milliseconds: 2200));
      s.haptic(HapticStrength.heavy);
      setState(() => _line = s.settings.commentaryOn ? s.commentary.winner(draw: widget.tournament.leaders.length > 1) : '');
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  void _rematch() {
    final config = widget.tournament.config;
    // After the Warm-Up Cup, a rematch is the full game with the same teams.
    MatchAccess.start(context, config.warmUp ? AppScope.read(context).settings.lastConfig() : config, rematch: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final leaders = t.leaders;
    final draw = leaders.length > 1;
    return Scaffold(
      body: PitchBackground(
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confetti,
              builder: (context, child) => CustomPaint(painter: _ConfettiPainter(_bits, _confetti.value)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const SizedBox(height: 20),
                Text('FULL TIME', style: AppText.label(18)),
                const Icon(Icons.emoji_events_rounded, color: Palette.gold, size: 110),
                Text(draw ? 'IT’S A DRAW' : 'CHAMPIONS', style: AppText.headline(30, color: Palette.gold)),
                const SizedBox(height: 6),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  for (final l in leaders) TeamChip(name: t.teamName(l), colorIndex: t.config.teams[l].colorIndex, size: 34),
                ]),
                const SizedBox(height: 10),
                if (_line.isNotEmpty)
                  Text(_line, textAlign: TextAlign.center, style: AppText.headline(22, color: Palette.text, weight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (t.playerTable.isNotEmpty) _PlayerOfTheMatch(tournament: t),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(children: [
                    for (final (pos, team) in t.standings.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(width: 30, child: Text('${pos + 1}', style: AppText.headline(24, color: Palette.muted))),
                          Container(width: 10, height: 28, color: Palette.team(t.config.teams[team].colorIndex)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(t.teamName(team).toUpperCase(), style: AppText.headline(26))),
                          Text('${t.scores[team]}', style: AppText.headline(30)),
                        ]),
                      ),
                  ]),
                ),
                BigButton(label: 'Rematch', icon: Icons.replay, onPressed: _rematch),
                const SizedBox(height: 8),
                GhostButton(label: 'Home', icon: Icons.home, onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Bit {
  _Bit(this.x, this.offset, this.speed, this.color, this.spin);
  final double x;
  final double offset;
  final double speed;
  final Color color;
  final double spin;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bits) {
      final y = ((t * b.speed + b.offset) % 1.0) * (size.height + 40) - 20;
      final x = b.x * size.width + sin((t * 6 + b.offset) * pi * 2) * 14;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin + t * 12 * b.speed);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), Paint()..color = b.color.withValues(alpha: 0.85));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Top individual scorer from face-offs and bomb turns.
class _PlayerOfTheMatch extends StatelessWidget {
  const _PlayerOfTheMatch({required this.tournament});
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final table = tournament.playerTable;
    final best = table.first;
    final colour = tournament.config.teams[best.team].colorIndex;
    final others = table.skip(1).take(3).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.gold),
      ),
      child: Column(children: [
        Text('PLAYER OF THE MATCH', style: AppText.label(13, color: Palette.gold)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.star_rounded, color: Palette.gold),
          const SizedBox(width: 6),
          Flexible(child: TeamChip(name: best.name, colorIndex: colour, size: 24)),
          const SizedBox(width: 8),
          Text('${best.points} PTS', style: AppText.headline(24, color: Palette.gold)),
        ]),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            others.map((p) => '${p.name} ${p.points}').join('  ·  '),
            textAlign: TextAlign.center,
            style: AppText.label(13),
          ),
        ],
      ]),
    );
  }
}
