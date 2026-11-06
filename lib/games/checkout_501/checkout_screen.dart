import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../multiplayer/turn_bridge.dart';
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

  /// Bumped when an answer is turned away without using the turn, so the
  /// answer box resets and can be used again.
  int _pickerKey = 0;

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
    if (roomFor(_t) case final room?) _phones = TurnBridge(room, _t)..start();
    setState(() => _c = c);
    _syncPhones(c);
    startClock(c.advance);
  }

  /// The team's dart on their captain's phone, when they've joined.
  TurnBridge? _phones;

  void _syncPhones(CheckoutController c) {
    final p = _phones;
    if (p == null) return;
    if (c.phase != CoPhase.answering) {
      p.idle('Football 501', game: 'co', board: _view(c));
      return;
    }
    final team = c.currentTeam;
    p.show(
      key: '${_t.rounds.length}-co-${c.turn}-$_pickerKey',
      team: team,
      stage: TurnStage.answer,
      title: 'FOOTBALL 501 · DART ${c.dartNumber}/${c.maxTurns}',
      headline: c.category.prompt,
      sub: 'You’re on ${max(0, c.remaining[team])} — apps + goals come off. Over ${CheckoutController.maxDart} = bust.',
      game: 'co',
      board: _view(c),
      left: c.secondsLeft,
      total: c.answerSeconds.toDouble(),
      index: services.repo.players,
      answers: {...c.category.values.keys, ...c.category.noStats},
      hint: 'Say or type a player…',
      onPick: c.submit,
      onPass: c.pass,
    );
  }

  void _onChange(CheckoutController c) {
    if (c.eventSerial != _seen) {
      _seen = c.eventSerial;
      final s = services;
      switch (c.lastEvent) {
        case CoEvent.duplicate:
          _toast('Already used — that player’s gone! Pick another.');
          _pickerKey++;
        case CoEvent.noStats:
          _toast('No league numbers on record for them at this club yet — pick another.');
          _pickerKey++;
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
    _syncPhones(c);
    if (mounted) setState(() {});
  }

  String _pick(List<String> lines) => lines[Random().nextInt(lines.length)];

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1400)));

  @override
  void dispose() {
    disposeGameSupport();
    _phones?.dispose();
    _c?.dispose();
    super.dispose();
  }

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
              Expanded(
                child: CoLayout(
                  data: _view(c),
                  multiplier: widget.round.multiplier,
                  typing: typing,
                  commentary: CommentaryBanner(text: commentaryText),
                  answerBox: _answerBox(c),
                  onContinue: c.next,
                  finish: BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
                ),
              ),
            ]),
          ),
        ),
      );

  /// Everything both the host and joined phones draw.
  Map<String, Object?> _view(CheckoutController c) {
    final players = services.repo.players;
    String short(CoThrow t) => switch (t.outcome) {
          CoOutcome.timeUp => 'Time',
          CoOutcome.wrong when t.label == 'Passed' => 'Pass',
          _ => t.label.split(' ').last,
        };
    final last = c.lastThrow;
    return {
      'phase': c.phase.name,
      'prompt': c.category.prompt,
      'team': c.currentTeam,
      'teams': [for (var i = 0; i < _t.teamCount; i++) {'name': _t.teamName(i), 'color': _t.config.teams[i].colorIndex}],
      'remaining': [for (final r in c.remaining) max(0, r)],
      'history': [
        for (var i = 0; i < _t.teamCount; i++)
          [
            for (final th in c.throwsOf(i).reversed.take(3))
              {'s': '${short(th)} ${_tag(th)}', 'ok': th.outcome == CoOutcome.scored || th.outcome == CoOutcome.checkout},
          ],
      ],
      'dart': c.dartNumber,
      'maxDarts': c.maxTurns,
      'checkedOut': c.checkedOut.isNotEmpty,
      if (last != null)
        'last': {
          'team': last.team,
          'label': last.label,
          'outcome': last.outcome.name,
          if (last.apps != null) 'apps': last.apps,
          if (last.goals != null) 'goals': last.goals,
          'value': last.value,
          'before': last.before,
          'after': last.after,
        },
      if (c.phase == CoPhase.finished) ...{
        'winners': c.winners.toList(),
        'winPoints': CheckoutController.winPoints * widget.round.multiplier,
        'unused': [
          for (final (p, v) in ([
            for (final e in c.category.values.entries)
              if (!c.used.contains(e.key) && players.byId(e.key) != null) (players.byId(e.key)!, e.value.$1 + e.value.$2),
          ]..sort((a, b) => b.$1.fame.compareTo(a.$1.fame)))
              .take(24)
              .toList()
            ..sort((a, b) => a.$2.compareTo(b.$2)))
            {'n': p.name, 'v': v},
        ],
      },
    };
  }

  String _tag(CoThrow t) => switch (t.outcome) {
        CoOutcome.scored || CoOutcome.checkout => '−${t.value}',
        CoOutcome.bust || CoOutcome.overshoot => 'BUST',
        CoOutcome.wrong || CoOutcome.timeUp => '✗',
      };

  /// The host's answer box — or who's answering on their own phone.
  Widget _answerBox(CheckoutController c) {
    final team = c.currentTeam;
    final colour = _t.config.teams[team].colorIndex;
    return Column(children: [
      TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
      const SizedBox(height: 8),
      if (_phones?.remote case final m?)
        OnTheirPhone(name: '${m.name} (${_t.teamName(team)})', onSkip: () => setState(() => _phones!.playHere()))
      else
        PlayerPicker(
          key: ValueKey('co-${c.turn}-$_pickerKey'),
          index: services.repo.players,
          voice: services.voice,
          accent: Palette.team(colour),
          hint: 'Say or type a player…',
          onPick: c.submit,
          isAnswer: (p) => c.category.values.containsKey(p.id) || c.category.noStats.contains(p.id),
          onPass: c.pass,
        ),
    ]);
  }
}

/// The whole Football 501 screen under the scores, from a plain snapshot —
/// the host and joined phones draw exactly the same thing. [answerBox] is
/// the timer + answer box (or "answering on their phone"); [finish] the
/// host's "Finish round" button.
class CoLayout extends StatelessWidget {
  const CoLayout({
    super.key,
    required this.data,
    required this.answerBox,
    this.multiplier = 1,
    this.typing = false,
    this.commentary,
    this.onContinue,
    this.finish,
  });
  final Map<String, Object?> data;
  final Widget answerBox;
  final int multiplier;
  final bool typing;
  final Widget? commentary;
  final VoidCallback? onContinue;
  final Widget? finish;

  List<Object?> _list(String k) => (data[k] as List?) ?? const [];
  Map<String, Object?> _map(Object? v) => v is Map ? v.cast<String, Object?>() : const {};
  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  Widget _teamChip(int team, {double size = 16}) {
    final t = team < _list('teams').length ? _map(_list('teams')[team]) : const <String, Object?>{};
    return TeamChip(name: '${t['name'] ?? ''}', colorIndex: _int(t['color']), size: size);
  }

  @override
  Widget build(BuildContext context) {
    final phase = '${data['phase']}';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(children: [
          Text('FOOTBALL 501', style: AppText.label(16, color: _oche)),
          const Spacer(),
          if (multiplier > 1) Text('x$multiplier POINTS', style: AppText.label(15, color: Palette.gold)),
        ]),
      ),
      _CategoryCard(prompt: '${data['prompt'] ?? ''}', compact: typing),
      typing ? const SizedBox.shrink() : _board(phase),
      if (!typing && commentary != null) commentary!,
      Expanded(
        child: switch (phase) {
          'answering' => _answering(),
          'reveal' => _reveal(),
          _ => _finished(),
        },
      ),
    ]);
  }

  /// The darts scoreboard: each team's score big, the history crossed out.
  Widget _board(String phase) {
    final team = _int(data['team']);
    final remaining = _list('remaining');
    final history = _list('history');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var t = 0; t < _list('teams').length; t++)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: phase != 'finished' && team == t ? _oche : Palette.line,
                  width: phase != 'finished' && team == t ? 2 : 1,
                ),
              ),
              child: Column(children: [
                FittedBox(fit: BoxFit.scaleDown, child: _teamChip(t, size: 14)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${t < remaining.length ? remaining[t] : ''}', style: AppText.headline(46, color: _oche)),
                ),
                for (final th in t < history.length ? (history[t] as List? ?? const []) : const [])
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${_map(th)['s'] ?? ''}',
                      style: AppText.label(11, color: _map(th)['ok'] == true ? Palette.text : Palette.danger),
                    ),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _answering() {
    final team = _int(data['team']);
    final remaining = _list('remaining');
    final on = team < remaining.length ? _int(remaining[team]) : 0;
    final checkedOut = data['checkedOut'] == true;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 16), children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _teamChip(team, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('ON $on · DART ${data['dart']}/${data['maxDarts']}', style: AppText.headline(22)),
          ),
        ),
      ]),
      Text(
        checkedOut
            ? 'LAST DART! They’ve checked out — finish closer to 0 to win it.'
            : on <= CheckoutController.maxDart
                ? 'Finish between 0 and −${CheckoutController.checkoutWindow} to check out!'
                : 'Over ${CheckoutController.maxDart} = bust. Players named are gone for everyone.',
        textAlign: TextAlign.center,
        style: AppText.label(13, color: checkedOut || on <= CheckoutController.maxDart ? Palette.gold : Palette.muted),
      ),
      const SizedBox(height: 8),
      answerBox,
    ]);
  }

  Widget _reveal() {
    final t = _map(data['last']);
    final label = '${t['label'] ?? ''}';
    final value = _int(t['value']);
    final (headline, colour) = switch ('${t['outcome']}') {
      'checkout' => ('CHECKED OUT!', Palette.yellow),
      'scored' => ('${t['before']} → ${t['after']}', _oche),
      'bust' => ('BUST — OVER 180', Palette.danger),
      'overshoot' => ('BUST — TOO FAR (${_int(t['before']) - value})', Palette.danger),
      'wrong' => (label == 'Passed' ? 'PASSED' : 'NEVER PLAYED FOR THEM', Palette.danger),
      _ => ('OUT OF TIME', Palette.danger),
    };
    return GestureDetector(
      onTap: onContinue,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _teamChip(_int(t['team']), size: 22),
            const SizedBox(height: 6),
            if (label != 'Time up' && label != 'Passed') Text(label.toUpperCase(), style: AppText.headline(32)),
            if (t['apps'] != null)
              Text('${t['apps']} APPS + ${t['goals']} GOALS = $value', style: AppText.headline(26, color: Palette.muted)),
            const SizedBox(height: 6),
            Text(headline, style: AppText.headline(48, color: colour)),
            if (onContinue != null) ...[
              const SizedBox(height: 8),
              Text('TAP TO CONTINUE', style: AppText.label(12)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _finished() => ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 16), children: [
        Text(data['checkedOut'] == true ? 'GAME SHOT!' : 'CLOSEST TO ZERO WINS',
            textAlign: TextAlign.center, style: AppText.headline(34, color: _oche)),
        const SizedBox(height: 6),
        for (final w in _list('winners'))
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _teamChip(_int(w), size: 22),
            const SizedBox(width: 10),
            Text('+${data['winPoints']}', style: AppText.headline(40, color: Palette.yellow)),
          ]),
        const SizedBox(height: 12),
        Text('WHO ELSE WAS ON THE BOARD', style: AppText.label(13)),
        Text('Red = over ${CheckoutController.maxDart}, a bust', style: AppText.label(12, color: Palette.danger)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final u in _list('unused'))
            Chip(
              label: Text('${_map(u)['n']}  ${_map(u)['v']}'),
              backgroundColor: Palette.card,
              side: _int(_map(u)['v']) > CheckoutController.maxDart
                  ? const BorderSide(color: Palette.danger, width: 2)
                  : const BorderSide(color: Palette.line),
            ),
        ]),
        if (finish != null) ...[const SizedBox(height: 16), finish!],
      ]);
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
