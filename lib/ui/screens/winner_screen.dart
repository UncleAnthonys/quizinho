import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../match_access.dart';
import '../widgets/common.dart';
import '../widgets/match_table.dart';

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
    // The same snapshot the joined phones draw (MatchFlow sends it).
    final table = MatchTable.fullTime(widget.tournament);
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
                FullTimeHeader(data: table, line: _line),
                Expanded(child: ListView(children: matchTableRows(table))),
                BigButton(label: 'Rematch', icon: Icons.replay, onPressed: _rematch),
                const SizedBox(height: 8),
                GhostButton(
                  label: 'Home',
                  icon: Icons.home,
                  onPressed: () {
                    // Done for the night: end the phones' room (Rematch keeps it).
                    final s = AppScope.read(context);
                    final room = s.room;
                    s.room = null;
                    if (room != null) unawaited(room.end().whenComplete(room.dispose));
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
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
