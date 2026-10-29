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

  /// The bid the current team is about to make (stepper value).
  int _pending = 1;

  Tournament get _t => widget.round.tournament;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await services.challenges.bidding(_t.config.difficulty, _t.usedIds(_mode), eras: _t.config.eraMask, genders: _t.config.genderMask);
    if (!mounted) return;
    if (b == null) {
      setState(() => _empty = true);
      return;
    }
    _t.markUsed(_mode, b.id);
    final c = BiddingWarController(category: b, teamCount: _t.teamCount, startTeam: _t.standings.last);
    c.addListener(() => _onChange(c));
    setState(() {
      _c = c;
      _pending = min(3, b.maxBid);
    });
    startClock(c.advance);
  }

  void _onChange(BiddingWarController c) {
    if (c.eventSerial != _seen) {
      _seen = c.eventSerial;
      final s = services;
      switch (c.lastEvent) {
        case BidEvent.raised:
          s.sound.play(Sfx.reveal, volume: 0.7);
          s.haptic(HapticStrength.medium);
          _pending = min(c.minRaise, c.maxBid);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(children: [
                Text('BIDDING WAR', style: AppText.label(16, color: Palette.yellow)),
                const Spacer(),
                if (widget.round.multiplier > 1)
                  Text('x${widget.round.multiplier} POINTS', style: AppText.label(15, color: Palette.gold)),
              ]),
            ),
            _CategoryCard(prompt: c.category.prompt, compact: c.phase == BidPhase.answering),
            CommentaryBanner(text: commentaryText),
            Expanded(child: _body(c)),
          ]),
        ),
      ),
    );
  }

  Widget _body(BiddingWarController c) => switch (c.phase) {
        BidPhase.bidding => _bidding(c),
        BidPhase.countdown => _countdown(c),
        BidPhase.answering => _answering(c),
        BidPhase.finished => _result(c),
      };

  Widget _teamChip(int team, {double size = 20}) =>
      TeamChip(name: _t.teamName(team), colorIndex: _t.config.teams[team].colorIndex, size: size);

  Widget _bidding(BiddingWarController c) {
    final team = c.currentTeam;
    final colour = _t.config.teams[team].colorIndex;
    final pending = _pending.clamp(c.minRaise, max(c.minRaise, c.maxBid)).toInt();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      // Current bid
      Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          if (c.holder == null)
            Text('NO BIDS YET', style: AppText.headline(28, color: Palette.muted))
          else ...[
            _teamChip(c.holder!, size: 18),
            const SizedBox(height: 4),
            Text('CLAIM THEY CAN NAME', style: AppText.label(15)),
            Text('${c.currentBid}', style: AppText.headline(72, color: Palette.yellow)),
          ],
          Text('${c.maxBid} answers exist', style: AppText.label(13)),
          const SizedBox(height: 2),
          Text('Challenged? ${c.answerSeconds} seconds to name your bid',
              style: AppText.label(13, color: Palette.yellow)),
        ]),
      ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _teamChip(team, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(c.holder == null ? 'OPENING BID' : 'WHAT DO YOU DO?', style: AppText.headline(26)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (c.canRaise) ...[
        Row(children: [
          _StepButton(icon: Icons.remove, onTap: pending > c.minRaise ? () => setState(() => _pending = pending - 1) : null),
          Expanded(
            child: Column(children: [
              Text('$pending', textAlign: TextAlign.center, style: AppText.headline(56)),
              Text('ANSWERS', style: AppText.label(13)),
            ]),
          ),
          _StepButton(icon: Icons.add, onTap: pending < c.maxBid ? () => setState(() => _pending = pending + 1) : null),
        ]),
        const SizedBox(height: 10),
        BigButton(
          label: c.holder == null ? 'We can name $pending' : 'Raise to $pending',
          icon: Icons.trending_up_rounded,
          color: Palette.team(colour),
          textColor: Palette.onTeam(colour),
          onPressed: () => c.raise(pending),
        ),
      ],
      if (c.canChallenge) ...[
        const SizedBox(height: 10),
        BigButton(
          label: 'Challenge — prove it!',
          icon: Icons.gavel_rounded,
          color: Palette.danger,
          textColor: Colors.white,
          onPressed: c.challenge,
        ),
      ],
      if (c.canPass) ...[
        const SizedBox(height: 6),
        Center(
          child: TextButton(onPressed: c.pass, child: Text('PASS (DROP OUT OF BIDDING)', style: AppText.label(15))),
        ),
      ],
      if (_t.teamCount > 2 && c.active.length < _t.teamCount)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Out: ${[for (var i = 0; i < _t.teamCount; i++) if (!c.active.contains(i)) _t.teamName(i)].join(', ')}',
            textAlign: TextAlign.center,
            style: AppText.label(13),
          ),
        ),
    ]);
  }

  Widget _countdown(BiddingWarController c) => Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _teamChip(c.holder!, size: 34),
            const SizedBox(height: 6),
            Text('HAVE BEEN CHALLENGED!', style: AppText.headline(34, color: Palette.danger)),
            const SizedBox(height: 10),
            Text('NAME ${c.currentBid} IN ${c.answerSeconds} SECONDS', style: AppText.headline(30)),
            const SizedBox(height: 10),
            Text('${max(1, c.secondsLeft.ceil())}', style: AppText.headline(120, color: Palette.yellow)),
          ]),
        ),
      );

  Widget _answering(BiddingWarController c) {
    final colour = _t.config.teams[c.holder!].colorIndex;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Row(children: [
        _teamChip(c.holder!, size: 18),
        const Spacer(),
        Text('${c.correctCount} / ${c.currentBid}', style: AppText.headline(44, color: Palette.yellow)),
      ]),
      const SizedBox(height: 6),
      TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
      const SizedBox(height: 10),
      PlayerPicker(
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
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final n in c.named.reversed)
          Chip(
            avatar: const Icon(Icons.check_circle_rounded, color: Palette.green, size: 18),
            label: Text(n, style: const TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: Palette.card,
          ),
      ]),
    ]);
  }

  Widget _result(BiddingWarController c) {
    final done = c.completed == true;
    final winner = done ? c.holder! : c.challenger!;
    final players = services.repo.players;
    final missed = [
      for (final id in c.category.answerIds) if (players.byId(id) != null) players.byId(id)!,
    ]..sort((a, b) => b.fame.compareTo(a.fame));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      Text(done ? 'BID COMPLETED!' : 'BLUFF CALLED!', textAlign: TextAlign.center,
          style: AppText.headline(40, color: done ? Palette.green : Palette.danger)),
      Text('${c.correctCount} of ${c.currentBid} named', textAlign: TextAlign.center, style: AppText.label(16, color: Palette.text)),
      const SizedBox(height: 10),
      Center(child: _teamChip(winner, size: 26)),
      Text('+${BiddingWarController.points * widget.round.multiplier}', textAlign: TextAlign.center,
          style: AppText.headline(56, color: Palette.yellow)),
      const SizedBox(height: 8),
      Text('THE FULL LIST (${missed.length})', style: AppText.label(13)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in missed) Chip(label: Text(p.name), backgroundColor: Palette.card),
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
