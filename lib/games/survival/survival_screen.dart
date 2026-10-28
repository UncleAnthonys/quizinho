import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import '../game_screen_support.dart';
import 'survival_controller.dart';
import 'survival_questions.dart';

/// Solo Survival: questions from every game, harder as you go, three lives.
class SurvivalScreen extends StatefulWidget {
  const SurvivalScreen({super.key});

  @override
  State<SurvivalScreen> createState() => _SurvivalScreenState();
}

class _SurvivalScreenState extends State<SurvivalScreen>
    with TickerProviderStateMixin<SurvivalScreen>, GameScreenSupport<SurvivalScreen> {
  SurvivalController? _c;
  late FootballGender _gender;
  int _best = 0;
  bool _newRecord = false;
  int _heardSerial = 0;
  bool _finished = false;
  String? _lastSeen;
  Timer? _autoNext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRun());
  }

  void _startRun() {
    final s = services;
    _gender = s.settings.gender;
    _best = s.settings.survivalBest(_gender);
    _newRecord = false;
    _finished = false;
    final questions = SurvivalQuestions(s.challenges, genders: _gender.mask, seenBefore: s.settings.survivalSeen);
    final c = SurvivalController(load: questions.next);
    c.addListener(() => _onChange(c));
    _c?.dispose();
    setState(() => _c = c);
    c.start();
    startClock(c.advance);
  }

  void _onChange(SurvivalController c) {
    final q = c.current;
    if (c.phase == SurvivalPhase.asking && q != null && q.id != _lastSeen) {
      _lastSeen = q.id;
      services.settings.markSurvivalSeen(q.id);
    }
    if (c.eventSerial != _heardSerial) {
      _heardSerial = c.eventSerial;
      final s = services;
      if (c.phase == SurvivalPhase.right) {
        s.sound.play(Sfx.correct);
        s.haptic(HapticStrength.medium);
        // Keep the pace up: straight on to the next one.
        _autoNext?.cancel();
        _autoNext = Timer(const Duration(milliseconds: 1100), () {
          if (mounted) c.next();
        });
      } else if (c.phase == SurvivalPhase.wrong) {
        s.sound.play(c.lastAnswer == null ? Sfx.whistle : Sfx.wrong);
        s.haptic(HapticStrength.heavy);
      }
    }
    if (c.isOver && !_finished) {
      _finished = true;
      _newRecord = services.settings.recordSurvival(_gender, c.score);
      services.sound.play(_newRecord ? Sfx.fanfare : Sfx.groan);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autoNext?.cancel();
    disposeGameSupport();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: c == null
              ? const Center(child: CircularProgressIndicator(color: Palette.yellow))
              : c.isOver
                  ? _GameOver(score: c.score, best: _best, newRecord: _newRecord, onAgain: _startRun)
                  : _play(c),
        ),
      ),
    );
  }

  Widget _play(SurvivalController c) {
    final q = c.current;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Palette.muted),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Text('SURVIVAL', style: AppText.headline(26)),
          const Spacer(),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(i < c.lives ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: i < c.lives ? Palette.danger : Palette.muted, size: 26),
            ),
          const SizedBox(width: 14),
          Text('${c.score}', style: AppText.headline(34, color: Palette.yellow)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          _Chip(c.difficulty.label.toUpperCase()),
          const SizedBox(width: 8),
          if (q != null) _Chip(q.heading),
          const Spacer(),
          if (_best > 0) Text('BEST $_best', style: AppText.label(13)),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: q == null || c.phase == SurvivalPhase.loading
            ? const Center(child: CircularProgressIndicator(color: Palette.yellow))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                _QuestionCard(q: q),
                const SizedBox(height: 12),
                if (c.phase == SurvivalPhase.asking) ...[
                  TimerBar(fraction: c.fraction, seconds: c.secondsLeft),
                  const SizedBox(height: 12),
                  PlayerPicker(
                    key: ValueKey('survival-${q.id}'),
                    index: services.repo.players,
                    voice: services.voice,
                    onPick: c.submit,
                    isAnswer: c.isRightAnswer,
                    showFlags: q.showFlags,
                    showPositions: q.showPositions,
                    onPass: c.pass,
                  ),
                ] else
                  _Result(c: c, q: q, names: _answerNames(q), onNext: c.next),
              ]),
      ),
    ]);
  }

  List<String> _answerNames(SurvivalQuestion q) {
    final players = services.repo.players;
    final found = [for (final id in q.answerIds) if (players.byId(id) case final p?) p];
    // Best-known first, so the reveal shows the ones you'd kick yourself over.
    found.sort((a, b) => b.fame.compareTo(a.fame));
    return [for (final p in found) p.name];
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Palette.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.line),
        ),
        child: Text(text, style: AppText.label(12, color: Palette.yellow)),
      );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.q});
  final SurvivalQuestion q;

  @override
  Widget build(BuildContext context) {
    final career = q.kind == SurvivalKind.career;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.line),
      ),
      child: Column(children: [
        Text(q.prompt, textAlign: TextAlign.center, style: AppText.label(17, color: Palette.text)),
        if (q.lines.isNotEmpty) const SizedBox(height: 10),
        for (final l in q.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: career
                ? Text(l, textAlign: TextAlign.center, style: AppText.headline(22))
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(l.toUpperCase(), style: AppText.headline(q.kind == SurvivalKind.connection ? 38 : 22)),
                  ),
          ),
      ]),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.c, required this.q, required this.names, required this.onNext});
  final SurvivalController c;
  final SurvivalQuestion q;
  final List<String> names;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final right = c.phase == SurvivalPhase.right;
    final said = c.lastAnswer;
    final title = right ? 'CORRECT' : (said == null ? 'TIME UP' : 'WRONG');
    final shown = names.take(8).toList();
    return Column(children: [
      Text(title, style: AppText.headline(40, color: right ? Palette.green : Palette.danger)),
      if (said != null && !right) Text('You said ${said.name}', style: AppText.label(15, color: Palette.text)),
      if (!right) ...[
        const SizedBox(height: 10),
        Text(
          q.kind == SurvivalKind.career
              ? 'IT WAS'
              : names.length == 1
                  ? 'THE ANSWER'
                  : 'YOU COULD HAVE SAID',
          style: AppText.label(13),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [for (final n in shown) Chip(label: Text(n), backgroundColor: Palette.card)],
        ),
        if (names.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+ ${names.length - shown.length} more', style: AppText.label(13)),
          ),
        const SizedBox(height: 16),
        BigButton(
          label: c.lives > 0 ? 'Next question' : 'See your score',
          icon: Icons.arrow_forward,
          onPressed: onNext,
        ),
      ],
    ]);
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.score, required this.best, required this.newRecord, required this.onAgain});
  final int score;

  /// The best before this run.
  final int best;
  final bool newRecord;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          Text(newRecord ? 'NEW PERSONAL BEST' : 'OUT OF LIVES',
              style: AppText.label(18, color: newRecord ? Palette.yellow : Palette.muted)),
          const SizedBox(height: 8),
          Text('$score', style: AppText.headline(120, color: Palette.yellow)),
          Text(score == 1 ? 'RIGHT ANSWER' : 'RIGHT ANSWERS', style: AppText.headline(26)),
          const SizedBox(height: 12),
          if (!newRecord && best > 0) Text('Your best: $best', style: AppText.label(16, color: Palette.text)),
          if (newRecord && best > 0) Text('Previous best: $best', style: AppText.label(16, color: Palette.text)),
          const Spacer(),
          BigButton(label: 'Play again', icon: Icons.replay_rounded, onPressed: onAgain),
          const SizedBox(height: 8),
          GhostButton(label: 'Home', icon: Icons.home_rounded, onPressed: () => Navigator.of(context).pop()),
        ]),
      );
}
