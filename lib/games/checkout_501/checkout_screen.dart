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
import 'checkout_controller.dart';

const _oche = Color(0xFF2EE6C9);

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with TickerProviderStateMixin<CheckoutScreen>, GameScreenSupport<CheckoutScreen> {
  static const _mode = GameModeId.checkout501;
  CheckoutController? _c;
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
    final cat = await services.challenges
        .checkout(_t.config.difficulty, _t.usedIds(_mode), eras: _t.config.eraMask, genders: _t.config.genderMask);
    if (!mounted) return;
    if (cat == null) {
      setState(() => _empty = true);
      return;
    }
    _t.markUsed(_mode, cat.id);
    final c = CheckoutController(category: cat, teamCount: _t.teamCount, startTeam: _t.standings.last)..begin();
    c.addListener(() => _onChange(c));
    setState(() => _c = c);
    startClock(c.advance);
  }

  void _onChange(CheckoutController c) {
    if (c.eventSerial != _seen) {
      _seen = c.eventSerial;
      final s = services;
      switch (c.lastEvent) {
        case CoEvent.duplicate:
          _toast('Already used — that player’s gone!');
        case CoEvent.noStats:
          _toast('No numbers on record for them here — pick another.');
        case CoEvent.thrown:
          final t = c.lastThrow!;
          switch (t.outcome) {
            case CoOutcome.checkout:
              s.sound.play(Sfx.fanfare);
              s.sound.play(Sfx.cheer);
              s.haptic(HapticStrength.heavy);
              say(_pick(const ['GAME SHOT! And the leg!', 'CHECKED OUT! What a finish!', 'Bullseye! They’re out!']));
            case CoOutcome.scored:
              s.sound.play(Sfx.kick);
              s.haptic(HapticStrength.medium);
              if (t.value == 180) say('ONE HUNDRED AND EIGHTYYYY!');
            case CoOutcome.bust || CoOutcome.overshoot:
              s.sound.play(Sfx.boom, volume: 0.7);
              s.sound.play(Sfx.groan, volume: 0.6);
              s.haptic(HapticStrength.heavy);
            case CoOutcome.wrong || CoOutcome.timeUp:
              s.sound.play(Sfx.wrong);
          }
        case null:
          break;
      }
    }
    if (c.phase == CoPhase.answering) {
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
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1400)));

  @override
  void dispose() {
    disposeGameSupport();
    _c?.dispose();
    super.dispose();
  }

  Widget _teamChip(int team, {double size = 16}) =>
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
      builder: (context, typing, _) => _scaffold(c, typing && c.phase == CoPhase.answering),
    );
  }

  /// Same widget at each index whether typing or not, so the answer box is
  /// never rebuilt (that closed the keyboard before).
  Widget _scaffold(CheckoutController c, bool typing) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: PitchBackground(
          child: SafeArea(
            child: Column(children: [
              typing ? const SizedBox.shrink() : Scoreboard(tournament: _t, highlightTeam: c.phase == CoPhase.finished ? null : c.currentTeam),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Row(children: [
                  Text('FOOTBALL 501', style: AppText.label(16, color: _oche)),
                  const Spacer(),
                  if (widget.round.multiplier > 1)
                    Text('x${widget.round.multiplier} POINTS', style: AppText.label(15, color: Palette.gold)),
                ]),
              ),
              _CategoryCard(prompt: c.category.prompt, compact: typing),
              typing ? const SizedBox.shrink() : _board(c),
              typing ? const SizedBox.shrink() : CommentaryBanner(text: commentaryText),
              Expanded(
                child: switch (c.phase) {
                  CoPhase.answering => _answering(c),
                  CoPhase.reveal => _reveal(c),
                  CoPhase.finished => _finished(c),
                },
              ),
            ]),
          ),
        ),
      );

  /// The darts scoreboard: each team's score big, the history crossed out.
  Widget _board(CheckoutController c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var t = 0; t < _t.teamCount; t++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: c.phase != CoPhase.finished && c.currentTeam == t ? _oche : Palette.line,
                    width: c.phase != CoPhase.finished && c.currentTeam == t ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  FittedBox(fit: BoxFit.scaleDown, child: _teamChip(t, size: 14)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${max(0, c.remaining[t])}', style: AppText.headline(46, color: _oche)),
                  ),
                  for (final th in c.throwsOf(t).reversed.take(3))
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_short(th.label)} ${_tag(th)}',
                        style: AppText.label(11, color: th.outcome == CoOutcome.scored || th.outcome == CoOutcome.checkout
                            ? Palette.text
                            : Palette.danger),
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      );

  String _short(String name) => name.split(' ').last;

  String _tag(CoThrow t) => switch (t.outcome) {
        CoOutcome.scored || CoOutcome.checkout => '−${t.value}',
        CoOutcome.bust || CoOutcome.overshoot => 'BUST',
        CoOutcome.wrong || CoOutcome.timeUp => '✗',
      };

  Widget _answering(CheckoutController c) {
    final team = c.currentTeam;
    final colour = _t.config.teams[team].colorIndex;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 16), children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _teamChip(team, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('ON ${max(0, c.remaining[team])} · DART ${c.dartNumber}/${c.maxTurns}', style: AppText.headline(22)),
          ),
        ),
      ]),
      Text(
        c.remaining[team] <= CheckoutController.maxDart
            ? 'Finish between 0 and −${CheckoutController.checkoutWindow} to check out!'
            : 'Over ${CheckoutController.maxDart} = bust. Players named are gone for everyone.',
        textAlign: TextAlign.center,
        style: AppText.label(13, color: c.remaining[team] <= CheckoutController.maxDart ? Palette.gold : Palette.muted),
      ),
      const SizedBox(height: 8),
      TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
      const SizedBox(height: 8),
      PlayerPicker(
        key: ValueKey('co-${c.turn}'),
        index: services.repo.players,
        voice: services.voice,
        accent: Palette.team(colour),
        hint: 'Say or type a player…',
        onPick: c.submit,
        onPass: c.pass,
      ),
    ]);
  }

  Widget _reveal(CheckoutController c) {
    final t = c.lastThrow!;
    final (headline, colour) = switch (t.outcome) {
      CoOutcome.checkout => ('CHECKED OUT!', Palette.yellow),
      CoOutcome.scored => ('${t.before} → ${t.after}', _oche),
      CoOutcome.bust => ('BUST — OVER 180', Palette.danger),
      CoOutcome.overshoot => ('BUST — TOO FAR (${t.before - t.value})', Palette.danger),
      CoOutcome.wrong => (t.label == 'Passed' ? 'PASSED' : 'NEVER PLAYED FOR THEM', Palette.danger),
      CoOutcome.timeUp => ('OUT OF TIME', Palette.danger),
    };
    return GestureDetector(
      onTap: c.next,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _teamChip(t.team, size: 22),
            const SizedBox(height: 6),
            if (t.label != 'Time up' && t.label != 'Passed') Text(t.label.toUpperCase(), style: AppText.headline(32)),
            if (t.apps != null)
              Text('${t.apps} APPS + ${t.goals} GOALS = ${t.value}', style: AppText.headline(26, color: Palette.muted)),
            const SizedBox(height: 6),
            Text(headline, style: AppText.headline(48, color: colour)),
            const SizedBox(height: 8),
            Text('TAP TO CONTINUE', style: AppText.label(12)),
          ]),
        ),
      ),
    );
  }

  Widget _finished(CheckoutController c) {
    final winners = c.winners;
    final players = services.repo.players;
    // Players nobody named, most famous first — what you could have had.
    final unused = [
      for (final e in c.category.values.entries)
        if (!c.used.contains(e.key) && players.byId(e.key) != null) (players.byId(e.key)!, e.value.$1 + e.value.$2),
    ]..sort((a, b) => b.$1.fame.compareTo(a.$1.fame));
    return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 16), children: [
      Text(c.checkedOut != null ? 'GAME SHOT!' : 'CLOSEST TO ZERO WINS', textAlign: TextAlign.center,
          style: AppText.headline(34, color: _oche)),
      const SizedBox(height: 6),
      for (final w in winners)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _teamChip(w, size: 22),
          const SizedBox(width: 10),
          Text('+${CheckoutController.winPoints * widget.round.multiplier}', style: AppText.headline(40, color: Palette.yellow)),
        ]),
      const SizedBox(height: 12),
      Text('SOME YOU COULD HAVE HAD', style: AppText.label(13)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (p, v) in unused.take(16)) Chip(label: Text('${p.name}  $v'), backgroundColor: Palette.card),
      ]),
      const SizedBox(height: 16),
      BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
    ]);
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
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 6 : 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _oche, width: 2),
        ),
        child: Text(prompt.toUpperCase(), textAlign: TextAlign.center, style: AppText.headline(compact ? 18 : 24)),
      );
}
