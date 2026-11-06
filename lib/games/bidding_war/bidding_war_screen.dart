import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../domain/warm_up_cup.dart';
import '../../multiplayer/turn_bridge.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import '../buzz_game_view.dart' show LoadingRound, OutOfChallenges;
import '../game_screen_support.dart';
import 'bidding_war_controller.dart';

class BiddingWarScreen extends StatefulWidget {
  const BiddingWarScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<BiddingWarScreen> createState() => _BiddingWarScreenState();
}

class _BiddingWarScreenState extends State<BiddingWarScreen>
    with TickerProviderStateMixin<BiddingWarScreen>, GameScreenSupport<BiddingWarScreen> {
  static const _mode = GameModeId.biddingWar;
  BiddingWarController? _c;
  bool _empty = false;
  int _seen = 0;
  int _pickerKey = 0;
  int _lastSecond = -1;

  Tournament get _t => widget.round.tournament;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = _t.config.warmUp
        ? await services.challenges.fixedBidding(WarmUpCup.bidding)
        : await services.challenges.bidding(_t.config.difficulty, _t.usedIds(_mode), eras: _t.config.eraMask, genders: _t.config.genderMask);
    if (!mounted) return;
    if (b == null) {
      setState(() => _empty = true);
      return;
    }
    _t.markUsed(_mode, b.id);
    final c = BiddingWarController(category: b, teamCount: _t.teamCount, startTeam: _t.standings.last);
    c.addListener(() => _onChange(c));
    if (roomFor(_t) case final room?) _phones = TurnBridge(room, _t)..start();
    setState(() => _c = c);
    _syncPhones(c);
    startClock(c.advance);
  }

  /// The team's bids, and naming them when challenged, on their captain's
  /// phone when they've joined.
  TurnBridge? _phones;

  void _syncPhones(BiddingWarController c) {
    final p = _phones;
    if (p == null) return;
    final holder = c.holder;
    switch (c.phase) {
      case BidPhase.bidding:
        p.show(
          key: '${_t.rounds.length}-bid-${c.currentBid}-${c.currentTeam}-${c.active.length}',
          team: c.currentTeam,
          stage: TurnStage.bid,
          title: 'BIDDING WAR',
          headline: c.category.prompt,
          game: 'bid',
          board: _view(c),
          onAction: (a) {
            if (a == 'challenge') {
              c.challenge();
            } else if (a == 'pass') {
              c.pass();
            } else if (a.startsWith('raise:')) {
              final to = int.tryParse(a.substring(6));
              if (to != null && c.canRaise && to >= c.minRaise && to <= c.maxBid) c.raise(to);
            }
          },
        );
      case BidPhase.countdown:
        p.idle('${_t.teamName(holder!)} challenged — name ${c.currentBid}!', game: 'bid', board: _view(c));
      case BidPhase.answering:
        final clubs = c.category.answersAreClubs;
        p.show(
          key: '${_t.rounds.length}-bid-$_pickerKey',
          team: holder!,
          stage: TurnStage.answer,
          title: 'BIDDING WAR · ${c.correctCount} / ${c.currentBid}',
          headline: c.category.prompt,
          sub: 'Name ${c.currentBid} — keep them coming',
          game: 'bid',
          board: _view(c),
          left: c.secondsLeft,
          total: c.answerSeconds.toDouble(),
          index: clubs ? services.repo.clubIndex : services.repo.players,
          answers: c.category.answerIds.toSet(),
          clubs: clubs,
          rapid: true,
          showFlags: !c.category.hidesFlags,
          showPositions: !c.category.hidesPositions,
          hint: clubs ? 'Say or type a club…' : 'Say or type a name…',
          onPick: c.submit,
        );
      case BidPhase.finished:
        p.idle(c.completed == true ? 'Bid completed!' : 'Bluff called!', game: 'bid', board: _view(c));
    }
  }

  void _onChange(BiddingWarController c) {
    if (c.eventSerial != _seen) {
      _seen = c.eventSerial;
      final s = services;
      switch (c.lastEvent) {
        case BidEvent.raised:
          s.sound.play(Sfx.reveal, volume: 0.7);
          s.haptic(HapticStrength.medium);
        case BidEvent.challenged:
          s.sound.play(Sfx.buzzIn);
          s.sound.play(Sfx.whistle);
          s.haptic(HapticStrength.heavy);
          say(_pick(const ['PROVE IT!', 'Put your money where your mouth is!', 'Called the bluff!']));
        case BidEvent.go:
          s.sound.play(Sfx.whistle);
        case BidEvent.correct:
          s.sound.play(Sfx.correct, volume: 0.8);
          s.haptic(HapticStrength.light);
        case BidEvent.duplicate:
          s.sound.play(Sfx.wrong, volume: 0.5);
          _toast('Already got that one!');
        case BidEvent.wrong:
          s.sound.play(Sfx.wrong, volume: 0.5);
          _toast('Not on the list — keep going!');
        case BidEvent.completed:
          s.sound.play(Sfx.fanfare);
          s.sound.play(Sfx.cheer);
          s.haptic(HapticStrength.heavy);
          say(_pick(const ['BID COMPLETED! Absolute scenes.', 'Talked the talk, walked the walk!', 'They only went and did it!']));
        case BidEvent.failed:
          s.sound.play(Sfx.boom);
          s.sound.play(Sfx.groan, volume: 0.8);
          s.haptic(HapticStrength.heavy);
          say(_pick(const ['YOU BLUFFED AND GOT CAUGHT!', 'All mouth, no trousers!', 'Big talk… small delivery.']));
        case null:
          break;
      }
    }
    if (c.phase == BidPhase.answering) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        if (sec <= 10 && sec > 0) services.sound.play(sec <= 5 ? Sfx.tickFast : Sfx.tick, volume: 0.7);
      }
    } else if (c.phase == BidPhase.countdown) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        services.sound.play(Sfx.countdownBeep);
      }
    }
    _syncPhones(c);
    if (mounted) setState(() {});
  }

  String _pick(List<String> lines) => lines[Random().nextInt(lines.length)];

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1100)));

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
      return OutOfChallenges(
        mode: _mode,
        onContinue: () => widget.round.onComplete(RoundResult.empty(_mode, _t.teamCount)),
      );
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            if (c.phase == BidPhase.bidding || c.phase == BidPhase.finished) Scoreboard(tournament: _t, highlightTeam: c.phase == BidPhase.bidding ? c.currentTeam : null),
            Expanded(
              child: BidLayout(
                data: _view(c),
                multiplier: widget.round.multiplier,
                commentary: CommentaryBanner(text: commentaryText),
                controls: _controls(c),
                answerBox: _answerBox(c),
                finish: BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Everything both the host and joined phones draw.
  Map<String, Object?> _view(BiddingWarController c) {
    final finished = c.phase == BidPhase.finished;
    final players = services.repo.players;
    return {
      'phase': c.phase.name,
      'prompt': c.category.prompt,
      'teams': [for (var i = 0; i < _t.teamCount; i++) {'name': _t.teamName(i), 'color': _t.config.teams[i].colorIndex}],
      'team': c.currentTeam,
      if (c.holder != null) 'holder': c.holder,
      'bid': c.currentBid,
      'max': c.maxBid,
      'min': c.minRaise,
      'seconds': c.answerSeconds,
      'canRaise': c.canRaise,
      'canChallenge': c.canChallenge,
      'canPass': c.canPass,
      'out': [for (var i = 0; i < _t.teamCount; i++) if (!c.active.contains(i)) _t.teamName(i)],
      'count': max(1, c.secondsLeft.ceil()),
      'correct': c.correctCount,
      'named': c.named,
      if (finished) ...{
        'done': c.completed == true,
        'winner': c.completed == true ? c.holder : c.challenger,
        'points': BiddingWarController.points * widget.round.multiplier,
        'full': [
          for (final p in [
            for (final id in c.category.answerIds) if (players.byId(id) != null) players.byId(id)!,
          ]..sort((a, b) => b.fame.compareTo(a.fame)))
            p.name,
        ],
      },
    };
  }

  /// Bid / challenge / pass here — or who's deciding on their own phone.
  Widget _controls(BiddingWarController c) {
    if (c.phase == BidPhase.bidding) {
      if (_phones?.remote case final m?) {
        return OnTheirPhone(name: '${m.name} (${_t.teamName(c.currentTeam)})', what: 'is deciding',
            onSkip: () => setState(() => _phones!.playHere()));
      }
    }
    return BidControls(data: _view(c), onRaise: c.raise, onChallenge: c.challenge, onPass: c.pass);
  }

  /// The host's clock and answer box — or who's naming them on their own phone.
  Widget _answerBox(BiddingWarController c) {
    if (c.phase != BidPhase.answering) return const SizedBox.shrink();
    final colour = _t.config.teams[c.holder!].colorIndex;
    return Column(children: [
      TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
      const SizedBox(height: 10),
      if (_phones?.remote case final m?)
        OnTheirPhone(name: '${m.name} (${_t.teamName(c.holder!)})', what: 'is naming them',
            onSkip: () => setState(() => _phones!.playHere()))
      else
        _picker(c, colour),
    ]);
  }

  Widget _picker(BiddingWarController c, int colour) {
    return PlayerPicker(
      key: ValueKey('bid-$_pickerKey'),
      // Club categories ("Clubs that have won the Premier League") search clubs.
      index: c.category.answersAreClubs ? services.repo.clubIndex : services.repo.players,
      voice: services.voice,
      accent: Palette.team(colour),
      hint: c.category.answersAreClubs ? 'Say or type a club…' : 'Say or type a name…',
      onPick: c.submit,
      isAnswer: (p) => c.category.answerIds.contains(p.id),
      showFlags: !c.category.hidesFlags,
      showPositions: !c.category.hidesPositions,
      rapid: true, // the box stays open: name them one after another
      onDisputed: (typed, allowed) {
        if (allowed) c.submitDisputed(typed);
        setState(() => _pickerKey++);
      },
    );
  }
}

/// The whole Bidding War screen under the scores, from a plain snapshot —
/// the host and joined phones draw exactly the same thing. [controls] is the
/// bid / challenge / pass panel, [answerBox] the rapid-fire answer box (or
/// "on their phone"), [finish] the host's "Finish round" button.
class BidLayout extends StatelessWidget {
  const BidLayout({
    super.key,
    required this.data,
    required this.controls,
    required this.answerBox,
    this.multiplier = 1,
    this.commentary,
    this.finish,
  });
  final Map<String, Object?> data;
  final Widget controls;
  final Widget answerBox;
  final int multiplier;
  final Widget? commentary;
  final Widget? finish;

  List<Object?> _list(String k) => (data[k] as List?) ?? const [];
  Map<String, Object?> _map(Object? v) => v is Map ? v.cast<String, Object?>() : const {};
  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  Widget _teamChip(int team, {double size = 20}) {
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
          Text('BIDDING WAR', style: AppText.label(16, color: Palette.yellow)),
          const Spacer(),
          if (multiplier > 1) Text('x$multiplier POINTS', style: AppText.label(15, color: Palette.gold)),
        ]),
      ),
      _CategoryCard(prompt: '${data['prompt'] ?? ''}', compact: phase == 'answering'),
      if (commentary != null) commentary!,
      Expanded(
        child: switch (phase) {
          'bidding' => _bidding(),
          'countdown' => _countdown(),
          'answering' => _answering(),
          _ => _result(),
        },
      ),
    ]);
  }

  Widget _bidding() {
    final holder = (data['holder'] as num?)?.toInt();
    final out = _list('out');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      // Current bid
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          if (holder == null)
            Text('NO BIDS YET', style: AppText.headline(28, color: Palette.muted))
          else ...[
            _teamChip(holder, size: 18),
            const SizedBox(height: 4),
            Text('CLAIM THEY CAN NAME', style: AppText.label(15)),
            Text('${data['bid']}', style: AppText.headline(72, color: Palette.yellow)),
          ],
          Text('${data['max']} answers exist', style: AppText.label(13)),
          const SizedBox(height: 2),
          Text('Challenged? ${data['seconds']} seconds to name that many answers',
              style: AppText.label(13, color: Palette.yellow)),
        ]),
      ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _teamChip(_int(data['team']), size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(holder == null ? 'OPENING BID' : 'WHAT DO YOU DO?', style: AppText.headline(26)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      controls,
      if (out.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Out: ${out.join(', ')}', textAlign: TextAlign.center, style: AppText.label(13)),
        ),
    ]);
  }

  Widget _countdown() => Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _teamChip(_int(data['holder']), size: 34),
            const SizedBox(height: 6),
            Text('HAVE BEEN CHALLENGED!', style: AppText.headline(34, color: Palette.danger)),
            const SizedBox(height: 10),
            Text('NAME ${data['bid']} IN ${data['seconds']} SECONDS', style: AppText.headline(30)),
            const SizedBox(height: 10),
            Text('${data['count']}', style: AppText.headline(120, color: Palette.yellow)),
          ]),
        ),
      );

  Widget _answering() => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        Row(children: [
          _teamChip(_int(data['holder']), size: 18),
          const Spacer(),
          Text('${data['correct']} / ${data['bid']}', style: AppText.headline(44, color: Palette.yellow)),
        ]),
        const SizedBox(height: 6),
        answerBox,
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in _list('named').reversed)
            Chip(
              avatar: const Icon(Icons.check_circle_rounded, color: Palette.green, size: 18),
              label: Text('$n', style: const TextStyle(fontWeight: FontWeight.w700)),
              backgroundColor: Palette.card,
            ),
        ]),
      ]);

  Widget _result() {
    final done = data['done'] == true;
    final full = _list('full');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Text(done ? 'BID COMPLETED!' : 'BLUFF CALLED!', textAlign: TextAlign.center,
          style: AppText.headline(40, color: done ? Palette.green : Palette.danger)),
      Text('${data['correct']} of ${data['bid']} named', textAlign: TextAlign.center, style: AppText.label(16, color: Palette.text)),
      const SizedBox(height: 10),
      Center(child: _teamChip(_int(data['winner']), size: 26)),
      Text('+${data['points']}', textAlign: TextAlign.center, style: AppText.headline(56, color: Palette.yellow)),
      const SizedBox(height: 8),
      Text('THE FULL LIST (${full.length})', style: AppText.label(13)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final n in full) Chip(label: Text('$n'), backgroundColor: Palette.card),
      ]),
      if (finish != null) ...[const SizedBox(height: 16), finish!],
    ]);
  }
}

/// Raise / challenge / pass, for the team whose turn it is — on the host,
/// or on their captain's phone.
class BidControls extends StatefulWidget {
  const BidControls({super.key, required this.data, required this.onRaise, required this.onChallenge, required this.onPass});
  final Map<String, Object?> data;
  final void Function(int to) onRaise;
  final VoidCallback onChallenge;
  final VoidCallback onPass;

  @override
  State<BidControls> createState() => _BidControlsState();
}

class _BidControlsState extends State<BidControls> {
  int? _pending;
  String _for = '';

  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final minRaise = _int(d['min']);
    final maxBid = _int(d['max']);
    final team = _int(d['team']);
    final teams = (d['teams'] as List?) ?? const [];
    final colour = team < teams.length ? _int((teams[team] as Map)['color']) : 0;
    // A fresh suggestion each new bid or turn: 3 to open, else the minimum raise.
    final key = '${d['bid']}-$team';
    if (key != _for) {
      _for = key;
      _pending = d['holder'] == null ? min(3, maxBid) : min(minRaise, maxBid);
    }
    final pending = (_pending ?? minRaise).clamp(minRaise, max(minRaise, maxBid)).toInt();
    return Column(children: [
      if (d['canRaise'] == true) ...[
        Row(children: [
          _StepButton(icon: Icons.remove, onTap: pending > minRaise ? () => setState(() => _pending = pending - 1) : null),
          Expanded(
            child: Column(children: [
              Text('$pending', textAlign: TextAlign.center, style: AppText.headline(56)),
              Text('ANSWERS', style: AppText.label(13)),
            ]),
          ),
          _StepButton(icon: Icons.add, onTap: pending < maxBid ? () => setState(() => _pending = pending + 1) : null),
        ]),
        const SizedBox(height: 10),
        BigButton(
          label: d['holder'] == null ? 'We can name $pending' : 'Raise to $pending',
          icon: Icons.trending_up_rounded,
          color: Palette.team(colour),
          textColor: Palette.onTeam(colour),
          onPressed: () => widget.onRaise(pending),
        ),
      ],
      if (d['canChallenge'] == true) ...[
        const SizedBox(height: 10),
        BigButton(
          label: 'Challenge — prove it!',
          icon: Icons.gavel_rounded,
          color: Palette.danger,
          textColor: Colors.white,
          onPressed: widget.onChallenge,
        ),
      ],
      if (d['canPass'] == true) ...[
        const SizedBox(height: 6),
        Center(
          child: TextButton(onPressed: widget.onPass, child: Text('DROP OUT — LET THE NEXT TEAM DECIDE', style: AppText.label(15))),
        ),
      ],
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
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 8 : 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.yellow, width: 2),
        ),
        child: Text(
          prompt.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppText.headline(compact ? 20 : 30),
        ),
      );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: onTap == null ? Palette.card : Palette.cardHigh,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Icon(icon, size: 36, color: onTap == null ? Palette.muted : Palette.yellow),
          ),
        ),
      );
}
