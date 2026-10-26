import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import '../buzz_game_view.dart' show LoadingRound, OutOfChallenges;
import '../game_screen_support.dart';
import 'pointless_controller.dart';

const _studio = Color(0xFF29C5FF);

class PointlessScreen extends StatefulWidget {
  const PointlessScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<PointlessScreen> createState() => _PointlessScreenState();
}

class _PointlessScreenState extends State<PointlessScreen>
    with TickerProviderStateMixin<PointlessScreen>, GameScreenSupport<PointlessScreen> {
  static const _mode = GameModeId.pointless;
  PointlessController? _c;
  bool _empty = false;
  int _seen = 0;
  int _lastSecond = -1;

  Tournament get _t => widget.round.tournament;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await services.challenges.pointless(_t.config.difficulty, _t.usedIds(_mode), eras: _t.config.eraMask, genders: _t.config.genderMask);
    if (!mounted) return;
    if (b == null) {
      setState(() => _empty = true);
      return;
    }
    _t.markUsed(_mode, b.id);
    final c = PointlessController(category: b, teamCount: _t.teamCount, startTeam: _t.standings.last)..start();
    c.addListener(() => _onChange(c));
    setState(() => _c = c);
    startClock(c.advance);
  }

  void _onChange(PointlessController c) {
    if (c.eventSerial != _seen) {
      _seen = c.eventSerial;
      final s = services;
      switch (c.lastEvent) {
        case PtEvent.wrong || PtEvent.timeUp:
          s.sound.play(Sfx.wrong);
          s.haptic(HapticStrength.heavy);
          say(_pick(const ['Not on the list — that’s the full 100.', 'Ouch. 100 points.', 'Wrong! Maximum score.']));
        case PtEvent.duplicate:
          _toast('Already said — pick another!');
        case PtEvent.scored || PtEvent.pointless:
          s.haptic(HapticStrength.light); // the column does the rest
        case null:
          break;
      }
    }
    if (c.phase == PtPhase.answering) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        if (sec <= 5 && sec > 0) services.sound.play(Sfx.tickFast, volume: 0.7);
      }
    } else {
      _lastSecond = -1;
    }
    if (mounted) setState(() {});
  }

  String _pick(List<String> lines) => lines[Random().nextInt(lines.length)];

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1100)));

  @override
  void dispose() {
    disposeGameSupport();
    _c?.dispose();
    super.dispose();
  }

  Widget _teamChip(int team, {double size = 18}) =>
      TeamChip(name: _t.teamName(team), colorIndex: _t.config.teams[team].colorIndex, size: size);

  @override
  Widget build(BuildContext context) {
    if (_empty) {
      return OutOfChallenges(mode: _mode, onContinue: () => widget.round.onComplete(RoundResult.empty(_mode, _t.teamCount)));
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    return ValueListenableBuilder<bool>(
      valueListenable: answerTyping,
      builder: (context, typing, _) => _scaffold(c, typing && c.phase == PtPhase.answering),
    );
  }

  /// [typing]: keyboard up — scoreboard and totals step aside so the
  /// suggestions get the room. Same widget at each index either way, so the
  /// answer box is never rebuilt (that closed the keyboard before).
  Widget _scaffold(PointlessController c, bool typing) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: PitchBackground(
          child: SafeArea(
            child: Column(children: [
              typing
                  ? const SizedBox.shrink()
                  : Scoreboard(tournament: _t, highlightTeam: c.phase == PtPhase.finished ? null : c.currentTeam),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Row(children: [
                  Text('POINTLESS', style: AppText.label(16, color: _studio)),
                  const Spacer(),
                  if (widget.round.multiplier > 1)
                    Text('x${widget.round.multiplier} POINTS', style: AppText.label(15, color: Palette.gold)),
                ]),
              ),
              _CategoryCard(prompt: c.category.prompt, compact: c.phase != PtPhase.finished),
              typing ? const SizedBox.shrink() : CommentaryBanner(text: commentaryText),
              Expanded(
                child: switch (c.phase) {
                  PtPhase.answering => _answering(c, typing),
                  PtPhase.reveal => _reveal(c),
                  PtPhase.finished => _finished(c),
                },
              ),
            ]),
          ),
        ),
      );

  Widget _totals(PointlessController c) => Row(children: [
        for (var t = 0; t < _t.teamCount; t++)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: c.phase != PtPhase.finished && c.currentTeam == t ? _studio : Palette.line,
                  width: c.phase != PtPhase.finished && c.currentTeam == t ? 2 : 1,
                ),
              ),
              child: Column(children: [
                FittedBox(fit: BoxFit.scaleDown, child: _teamChip(t, size: 14)),
                Text('${c.totalOf(t)}', style: AppText.headline(34, color: _studio)),
                for (final a in c.answersOf(t))
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${a.label}  ${a.score}',
                        style: AppText.label(12, color: a.valid ? Palette.text : Palette.danger)),
                  ),
              ]),
            ),
          ),
      ]);

  Widget _answering(PointlessController c, bool typing) {
    final team = c.currentTeam;
    final colour = _t.config.teams[team].colorIndex;
    final clubs = c.category.answersAreClubs;
    return ListView(padding: const EdgeInsets.fromLTRB(13, 4, 13, 16), children: [
      typing ? const SizedBox.shrink() : _totals(c),
      typing ? const SizedBox.shrink() : const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _teamChip(team, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('ANSWER ${c.goNumber} OF ${c.answersPerTeam}', style: AppText.headline(24)),
          ),
        ),
      ]),
      typing
          ? const SizedBox.shrink()
          : Text('Confer — the most obscure right answer wins.',
              textAlign: TextAlign.center, style: AppText.label(13)),
      const SizedBox(height: 8),
      TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
      const SizedBox(height: 8),
      PlayerPicker(
        key: ValueKey('pt-${c.turn}'),
        index: clubs ? services.repo.clubIndex : services.repo.players,
        voice: services.voice,
        accent: Palette.team(colour),
        hint: clubs ? 'Say or type a club…' : 'Say or type a name…',
        onPick: c.submit,
        onPass: c.giveUp,
        onDisputed: (typed, allowed) {
          if (allowed) {
            c.submitDisputed(typed);
          } else {
            c.giveUp();
          }
        },
      ),
    ]);
  }

  Widget _reveal(PointlessController c) {
    final a = c.lastAnswer!;
    return GestureDetector(
      onTap: c.next,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(children: [
          _teamChip(a.team, size: 20),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(a.label.toUpperCase(), style: AppText.headline(30)),
          ),
          const SizedBox(height: 8),
          Expanded(child: _Column(key: ValueKey('col-${c.answers.length}'), answer: a, sounds: services)),
          Text('TAP TO CONTINUE', style: AppText.label(12)),
        ]),
      ),
    );
  }

  Widget _finished(PointlessController c) {
    final winners = c.winners;
    final index = c.category.answersAreClubs ? services.repo.clubIndex : services.repo.players;
    final given = {for (final a in c.answers) if (a.id != null) a.id!};
    final all = [
      for (final id in c.category.answerIds)
        if (index.byId(id) != null) (index.byId(id)!.name, c.category.scores[id] ?? 0, given.contains(id)),
    ]..sort((x, y) => x.$2.compareTo(y.$2));
    return ListView(padding: const EdgeInsets.fromLTRB(13, 4, 13, 16), children: [
      _totals(c),
      const SizedBox(height: 10),
      Text(winners.length > 1 ? 'IT’S A TIE!' : 'LOWEST SCORE WINS!',
          textAlign: TextAlign.center, style: AppText.headline(30, color: _studio)),
      const SizedBox(height: 4),
      for (var t = 0; t < _t.teamCount; t++)
        if (c.result().points[t]! > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _teamChip(t, size: 18),
              const SizedBox(width: 10),
              Text('+${c.result().points[t]! * widget.round.multiplier}', style: AppText.headline(30, color: Palette.yellow)),
              if (c.answersOf(t).any((a) => a.pointless))
                Text('  incl. POINTLESS bonus', style: AppText.label(12, color: Palette.gold)),
            ]),
          ),
      const SizedBox(height: 10),
      Text('EVERY ANSWER (${all.length}) — LOWEST FIRST', style: AppText.label(13)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (name, score, said) in all)
          Chip(
            backgroundColor: score == 0 ? _studio : (said ? Palette.cardHigh : Palette.card),
            label: Text('$name  $score',
                style: TextStyle(
                  fontWeight: said || score == 0 ? FontWeight.w800 : FontWeight.w500,
                  color: score == 0 ? Palette.pitchDeep : Palette.text,
                )),
          ),
      ]),
      const SizedBox(height: 16),
      BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
    ]);
  }
}

/// The Pointless column: drops from 100 to the score, ticking on the way.
/// Wrong answers stay full and red.
class _Column extends StatefulWidget {
  const _Column({super.key, required this.answer, required this.sounds});
  final PtAnswer answer;
  final AppServices sounds;

  @override
  State<_Column> createState() => _ColumnState();
}

class _ColumnState extends State<_Column> with SingleTickerProviderStateMixin {
  late final int _target = widget.answer.score;
  late final AnimationController _drop = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.answer.valid ? 500 + (100 - _target) * 17 : 1),
  );
  int _lastStep = 100;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _drop.addListener(_tick);
    _drop.forward().whenComplete(_landed);
  }

  double get _value => 100 - (100 - _target) * Curves.easeOut.transform(_drop.value);

  void _tick() {
    final step = (_value / 4).floor();
    if (step != _lastStep) {
      _lastStep = step;
      widget.sounds.sound.play(Sfx.spinTick, volume: 0.45);
    }
    setState(() {});
  }

  void _landed() {
    if (!mounted || !widget.answer.valid) return;
    setState(() => _done = true);
    final s = widget.sounds;
    if (_target == 0) {
      s.sound.play(Sfx.fanfare);
      s.sound.play(Sfx.cheer);
      s.haptic(HapticStrength.heavy);
    } else {
      s.sound.play(Sfx.reveal, volume: 0.8);
      s.haptic(HapticStrength.medium);
    }
  }

  @override
  void dispose() {
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.answer;
    final v = a.valid ? _value : 100.0;
    final pointless = a.valid && _done && _target == 0;
    final colour = !a.valid ? Palette.danger : (pointless ? Palette.yellow : _studio);
    return LayoutBuilder(builder: (context, box) {
      final h = max(60.0, box.maxHeight - 70);
      return Column(children: [
        Text(pointless ? 'POINTLESS!' : '${v.round()}', style: AppText.headline(pointless ? 54 : 64, color: colour)),
        const SizedBox(height: 4),
        Container(
          width: 110,
          height: h,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.line, width: 2),
          ),
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.all(5),
          child: FractionallySizedBox(
            heightFactor: max(0.0, v / 100),
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colour, colour.withValues(alpha: 0.55)],
                ),
              ),
            ),
          ),
        ),
        if (!a.valid)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(a.label == 'Time up' ? 'OUT OF TIME' : 'NOT ON THE LIST', style: AppText.headline(20, color: Palette.danger)),
          ),
      ]);
    });
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.prompt, required this.compact});
  final String prompt;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 8 : 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _studio, width: 2),
        ),
        child: Text(prompt.toUpperCase(), textAlign: TextAlign.center, style: AppText.headline(compact ? 20 : 26)),
      );
}
