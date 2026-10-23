import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import '../buzz_game_view.dart' show LoadingRound, OutOfChallenges;
import '../game_screen_support.dart';
import 'starting_xi_controller.dart';

class StartingXiScreen extends StatefulWidget {
  const StartingXiScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<StartingXiScreen> createState() => _StartingXiScreenState();
}

class _StartingXiScreenState extends State<StartingXiScreen>
    with TickerProviderStateMixin<StartingXiScreen>, GameScreenSupport<StartingXiScreen> {
  static const _mode = GameModeId.startingXi;
  StartingXiController? _c;
  bool _empty = false;
  int _lastSecond = -1;
  int _turn = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = widget.round.tournament;
    final m = await services.challenges.match(t.config.difficulty, t.usedIds(_mode));
    if (!mounted) return;
    if (m == null) {
      setState(() => _empty = true);
      return;
    }
    t.markUsed(_mode, m.id);
    final c = StartingXiController(
      match: m,
      teamCount: t.teamCount,
      turnSeconds: t.config.bombSeconds,
      lives: t.config.bombLives,
      // trailing team starts, to keep it competitive
      startTeam: t.standings.last,
    );
    c.addListener(() => _onChange(c));
    setState(() => _c = c);
    startClock(c.advance);
  }

  void _onChange(StartingXiController c) {
    handleEvent(c.eventSerial, c.lastEvent);
    if (c.phase == BombPhase.ticking) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        if (sec <= 5) {
          services.sound.play(Sfx.tickFast);
        } else {
          services.sound.play(Sfx.tick, volume: 0.7);
        }
      }
    } else {
      _lastSecond = -1;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    disposeGameSupport();
    _c?.dispose();
    super.dispose();
  }

  void _submit(StartingXiController c, Player p) {
    final r = c.submit(p);
    if (r == SubmitResult.alreadyNamed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${p.name} is already on the board — someone else!'),
          duration: const Duration(milliseconds: 1400),
        ));
    } else {
      _turn++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.round.tournament;
    if (_empty) {
      return OutOfChallenges(
        mode: _mode,
        onContinue: () => widget.round.onComplete(RoundResult.empty(_mode, t.teamCount)),
      );
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    final m = c.match;
    final finished = c.phase == BombPhase.finished;
    final exploded = c.phase == BombPhase.exploded;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        foregroundDecoration: BoxDecoration(color: exploded ? Palette.danger.withValues(alpha: 0.18) : Colors.transparent),
        child: PitchBackground(
          child: SafeArea(
            child: Column(children: [
              Scoreboard(
                tournament: t,
                highlightTeam: finished ? null : c.currentTeam,
                extra: (i) => c.livesLeft[i]! > 0 ? '${'♥' * c.livesLeft[i]!}  ${c.correctByTeam[i]} named' : 'OUT',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(children: [
                  Row(children: [
                    Text('STARTING XI BOMB', style: AppText.label(15, color: Palette.lime)),
                    const Spacer(),
                    if (widget.round.multiplier > 1)
                      Text('x${widget.round.multiplier} POINTS', style: AppText.label(15, color: Palette.gold)),
                  ]),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('NAME ${m.targetTeam.toUpperCase()}’S XI', style: AppText.headline(30)),
                  ),
                  Text(
                    '${m.home} v ${m.away} · ${m.score} · ${m.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                  Text(m.title, style: AppText.label(13)),
                ]),
              ),
              CommentaryBanner(text: commentaryText),
              Flexible(flex: 5, child: _Formation(match: m, named: c.namedBy, revealAll: finished, tournament: t)),
              Flexible(flex: 6, child: _bottom(c, t)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bottom(StartingXiController c, Tournament t) {
    final team = c.currentTeam;
    final colour = t.config.teams[team].colorIndex;
    if (c.phase == BombPhase.handover) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: c.startTurn,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Palette.team(colour), borderRadius: BorderRadius.circular(24)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.phone_iphone, size: 44, color: Palette.onTeam(colour)),
                const SizedBox(height: 6),
                Text('PASS TO', style: AppText.label(18, color: Palette.onTeam(colour))),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(t.teamName(team).toUpperCase(), style: AppText.headline(54, color: Palette.onTeam(colour))),
                ),
                const SizedBox(height: 6),
                Text('TAP WHEN READY — ${c.turnSeconds}s ON THE CLOCK',
                    style: AppText.label(15, color: Palette.onTeam(colour))),
              ]),
            ),
          ),
        );
    }
    if (c.phase == BombPhase.ticking) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(children: [
            Row(children: [
              _Bomb(fraction: c.fractionLeft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TeamChip(name: t.teamName(team), colorIndex: colour),
                  const SizedBox(height: 6),
                  TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            PlayerPicker(
              key: ValueKey('xi-$_turn'),
              index: services.repo.players,
              accent: Palette.team(colour),
              hint: 'Name a starter…',
              onPick: (p) => _submit(c, p),
              onPass: c.pass,
            ),
          ]),
        );
    }
    if (c.phase == BombPhase.exploded) {
        final lost = c.lastExploded ?? team;
        final out = c.livesLeft[lost]! <= 0;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Shake(child: Text('BOOM!', style: AppText.headline(80, color: Palette.danger))),
            Text(
              out ? '${t.teamName(lost).toUpperCase()} ARE OUT' : '${t.teamName(lost).toUpperCase()} LOSE A LIFE',
              textAlign: TextAlign.center,
              style: AppText.headline(30),
            ),
            const SizedBox(height: 20),
            BigButton(label: 'Continue', icon: Icons.arrow_forward, onPressed: c.continueAfterExplosion),
          ]),
        );
    }
    {
        final bonus = c.bonusTeams;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(c.isComplete ? 'FULL XI NAMED!' : 'LAST TEAM STANDING', style: AppText.headline(34, color: Palette.lime)),
            const SizedBox(height: 8),
            if (bonus.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                for (final b in bonus) TeamChip(name: t.teamName(b), colorIndex: t.config.teams[b].colorIndex),
              ]),
            if (bonus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('+${StartingXiController.survivorBonus * widget.round.multiplier} BONUS',
                    style: AppText.label(15, color: Palette.gold)),
              ),
            const SizedBox(height: 16),
            BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
          ]),
        );
    }
  }
}

class _Formation extends StatelessWidget {
  const _Formation({required this.match, required this.named, required this.revealAll, required this.tournament});
  final HistoricMatch match;
  final Map<String, int> named;
  final bool revealAll;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final lines = <int, List<LineupSlot>>{};
    for (final s in match.lineup) {
      lines.putIfAbsent(s.line, () => []).add(s);
    }
    final order = lines.keys.toList()..sort((a, b) => b.compareTo(a)); // attack at the top
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final line in order)
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final s in lines[line]!) Expanded(child: _Slot(slot: s, team: named[s.playerId], revealAll: revealAll, tournament: tournament)),
          ]),
      ]),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.slot, required this.team, required this.revealAll, required this.tournament});
  final LineupSlot slot;
  final int? team;
  final bool revealAll;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final shown = team != null || revealAll;
    final colour = team == null ? null : Palette.team(tournament.config.teams[team!].colorIndex);
    final surname = slot.playerName.split(' ').last;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          color: shown ? (colour ?? Palette.card).withValues(alpha: team == null ? 0.6 : 0.9) : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: shown ? Colors.transparent : Palette.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(slot.position, style: AppText.label(10, color: shown && team != null ? Colors.black54 : Palette.muted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              shown ? surname.toUpperCase() : '?',
              style: AppText.headline(17, color: shown && team != null ? Palette.onTeam(tournament.config.teams[team!].colorIndex) : Palette.text),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A fuse that burns down with the timer.
class _Bomb extends StatelessWidget {
  const _Bomb({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final urgent = fraction < 0.3;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: urgent ? 250 : 600),
      key: ValueKey((fraction * 20).floor()),
      builder: (context, v, child) => Transform.scale(scale: 1 + (urgent ? 0.08 : 0.03) * sin(v * pi), child: child),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          border: Border.all(color: urgent ? Palette.danger : Palette.gold, width: 3),
        ),
        child: Icon(Icons.local_fire_department, color: urgent ? Palette.danger : Palette.gold, size: 36),
      ),
    );
  }
}

class _Shake extends StatelessWidget {
  const _Shake({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 600),
        builder: (context, v, c) => Transform.translate(offset: Offset(sin(v * 40) * 12 * v, 0), child: c),
        child: child,
      );
}
