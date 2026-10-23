import 'package:flutter/material.dart';

import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../buzz_game_view.dart';
import '../buzz_race_controller.dart';
import '../game_screen_support.dart';
import 'career_path_controller.dart';

class CareerPathScreen extends StatefulWidget {
  const CareerPathScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<CareerPathScreen> createState() => _CareerPathScreenState();
}

class _CareerPathScreenState extends State<CareerPathScreen>
    with TickerProviderStateMixin<CareerPathScreen>, GameScreenSupport<CareerPathScreen> {
  static const _mode = GameModeId.careerPath;
  CareerPathController? _c;
  late final FaceOffTracker _faces = FaceOffTracker(widget.round);
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    allowTableMode();
    _load();
  }

  Future<void> _load() async {
    final t = widget.round.tournament;
    final source = services.challenges;
    final qs = <CareerPath>[];
    for (var i = 0; i < t.config.questionsPerRound; i++) {
      final q = await source.careerPath(t.config.difficulty, t.usedIds(_mode), eras: t.config.eraMask);
      if (q == null) break;
      t.markUsed(_mode, q.id);
      qs.add(q);
    }
    if (!mounted) return;
    if (qs.isEmpty) {
      setState(() => _empty = true);
      return;
    }
    final c = CareerPathController(teamCount: t.teamCount, questions: qs, answerSeconds: t.config.answerSeconds);
    _faces.sync(c);
    c.addListener(() {
      _faces.sync(c);
      handleEvent(c.eventSerial, c.lastEvent);
      if (mounted) setState(() {});
    });
    setState(() => _c = c);
    startClock((dt) {
      if (!_faces.awaitingReady) c.advance(dt);
    });
  }

  @override
  void dispose() {
    disposeGameSupport();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_empty) {
      return OutOfChallenges(
        mode: _mode,
        onContinue: () => widget.round.onComplete(RoundResult.empty(_mode, widget.round.tournament.teamCount)),
      );
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    final resolved = c.phase == BuzzPhase.resolved || c.phase == BuzzPhase.finished;
    final shown = resolved ? c.clueCount : c.revealed;

    return BuzzGameView(
      round: widget.round,
      controller: c,
      commentary: commentaryText,
      timerLabel: c.allRevealed ? 'FINAL CHANCE' : 'NEXT CLUB IN',
      onFinished: () => widget.round.onComplete(c.result()),
      faceOff: _faces.current,
      awaitingFaceOff: _faces.awaitingReady,
      onFaceOffReady: () {
        services.sound.play(Sfx.whistle);
        setState(_faces.ready);
      },
      question: (compact) => Column(children: [
        if (!resolved)
          Text(
            'WORTH ${c.pointsAvailable * widget.round.multiplier} ${c.pointsAvailable * widget.round.multiplier == 1 ? 'POINT' : 'POINTS'}',
            style: AppText.headline(compact ? 18 : 24, color: Palette.gold),
          ),
        _CareerTrail(spells: c.current.spells, shown: shown, maxHeight: compact ? 130 : (resolved ? 170 : 210)),
      ]),
      resolvedDetail: Text(
        'It was ${c.current.player.name}.',
        textAlign: TextAlign.center,
        style: AppText.headline(24, color: Palette.muted, weight: FontWeight.w700),
      ),
    );
  }
}

/// The clubs revealed so far, newest at the bottom and highlighted.
class _CareerTrail extends StatelessWidget {
  const _CareerTrail({required this.spells, required this.shown, required this.maxHeight});
  final List<CareerSpell> spells;
  final int shown;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final visible = spells.take(shown).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.builder(
        reverse: true, // keeps the newest club in view
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final idx = visible.length - 1 - i;
          final s = visible[idx];
          final newest = idx == visible.length - 1;
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: newest ? 1 : 0.7,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: newest ? 10 : 6),
              decoration: BoxDecoration(
                color: newest ? Palette.cardHigh : Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: newest ? Border.all(color: Palette.yellow, width: 2) : null,
              ),
              child: Row(children: [
                Text('${idx + 1}', style: AppText.label(14)),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(s.club.name.toUpperCase(), style: AppText.headline(newest ? 32 : 22)),
                  ),
                ),
                if (s.isLoan)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(6)),
                    child: Text('LOAN', style: AppText.label(11, color: Palette.pitchDeep)),
                  ),
                Text(s.yearsLabel, style: AppText.label(14)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
