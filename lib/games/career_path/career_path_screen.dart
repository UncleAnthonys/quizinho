import 'package:flutter/material.dart';

import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../domain/warm_up_cup.dart';
import '../../multiplayer/buzz_bridge.dart';
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
      final q = t.config.warmUp
          ? (i < WarmUpCup.careers.length ? await source.fixedCareer(WarmUpCup.careers[i]) : null)
          : await source.careerPath(t.config.difficulty, t.usedIds(_mode), eras: t.config.eraMask, genders: t.config.genderMask);
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
      handleEvent(c.eventSerial, c.lastEvent,
          miss: c.lastMiss, clip: punditClip(c, faceOff: _faces.current != null));
      if (mounted) setState(() {});
    });
    final room = services.room;
    if (room != null) {
      _bridge = BuzzBridge(
        room: room,
        controller: c,
        tournament: t,
        players: services.repo.players,
        title: 'CAREER PATH',
        prompt: 'Who had this career?',
        question: () {
          final resolved = c.phase == BuzzPhase.resolved || c.phase == BuzzPhase.finished;
          final shown = resolved ? c.clueCount : c.revealed;
          return {
            'spells': [
              for (final s in c.current.spells.take(shown))
                {'c': s.club.name, 's': s.startYear, 'e': s.endYear, 'l': s.isLoan},
            ],
            'shown': shown,
            'highlight': c.revealed - 1,
            if (!resolved) 'worth': c.pointsAvailable * widget.round.multiplier,
            if (!resolved) 'clock': c.allRevealed ? 'FINAL CHANCE' : 'NEXT CLUB IN',
          };
        },
        answerIds: () => {c.current.player.id},
        reveal: () => ['It was ${c.current.player.name}'],
        faceOff: () => _faces.current,
        paused: () => _faces.awaitingReady,
        multiplier: widget.round.multiplier,
      )
        ..addListener(() {
          if (mounted) setState(() {});
        })
        ..start();
    }
    setState(() => _c = c);
    startClock((dt) {
      if (!_faces.awaitingReady) c.advance(dt);
    });
  }

  /// Plays the question on the room's phones, when there is a room.
  BuzzBridge? _bridge;

  @override
  void dispose() {
    disposeGameSupport();
    _bridge?.dispose();
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
      remoteAnswerer: _bridge?.remote?.name,
      phoneTeams: _bridge?.phoneTeams() ?? const {},
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
        // Once answered, the ring stays on the club that was showing when they
        // got it (revealing stops at that moment), not the last club.
        CareerTrail(
          spells: c.current.spells,
          shown: shown,
          highlight: c.revealed - 1,
          maxHeight: compact ? 190 : (resolved ? 200 : 250),
        ),
      ]),
      resolvedDetail: Text(
        'It was ${c.current.player.name}.',
        textAlign: TextAlign.center,
        style: AppText.headline(24, color: Palette.muted, weight: FontWeight.w700),
      ),
    );
  }
}

/// The clubs revealed so far, newest at the bottom; [highlight] is ringed.
class CareerTrail extends StatelessWidget {
  const CareerTrail({required this.spells, required this.shown, required this.highlight, required this.maxHeight});
  final List<CareerSpell> spells;
  final int shown;

  /// Index of the ringed club: the newest while revealing, the answered one after.
  final int highlight;
  final double maxHeight;

  /// Every club revealed so far stays on screen — earlier clubs jog the
  /// memory. More than four clubs switch to two columns (read left to right,
  /// numbered) so rows stay big instead of shrinking to nothing.
  @override
  Widget build(BuildContext context) {
    final visible = spells.take(shown).toList();
    return LayoutBuilder(builder: (context, box) {
      final cols = visible.length > 4 && box.maxWidth >= 300 ? 2 : 1;
      final rows = (visible.length / cols).ceil();
      const gap = 6.0;
      final rowH = ((maxHeight - gap * (rows - 1)) / rows).clamp(30.0, 64.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: gap),
            SizedBox(
              height: rowH,
              child: Row(children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) const SizedBox(width: gap),
                  Expanded(
                    child: r * cols + c < visible.length
                        ? _tile(r * cols + c, visible, compact: cols == 2)
                        : const SizedBox(),
                  ),
                ],
              ]),
            ),
          ],
        ]),
      );
    });
  }

  Widget _tile(int idx, List<CareerSpell> visible, {required bool compact}) {
    final s = visible[idx];
    final newest = idx == highlight;
    final name = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(s.club.name.toUpperCase(), style: AppText.headline(newest ? 30 : 24)),
    );
    final years = Row(mainAxisSize: MainAxisSize.min, children: [
      if (s.isLoan)
        Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(5)),
          child: Text('LOAN', style: AppText.label(11, color: Palette.pitchDeep)),
        ),
      Text(s.yearsLabel, style: AppText.label(compact ? 12 : 15, color: Palette.text)),
    ]);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: newest ? Palette.cardHigh : Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: newest ? Palette.yellow : Palette.line, width: newest ? 2 : 1),
      ),
      child: Row(children: [
        Text('${idx + 1}', style: AppText.headline(18, color: Palette.yellow)),
        const SizedBox(width: 8),
        Expanded(
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // Two columns (lots of clubs): club name gets most of the
                  // height, years sit small underneath.
                  children: [
                    Expanded(flex: 5, child: name),
                    Expanded(
                      flex: 3,
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: years),
                    ),
                  ],
                )
              : name,
        ),
        if (!compact) ...[const SizedBox(width: 8), years],
      ]),
    );
  }
}
