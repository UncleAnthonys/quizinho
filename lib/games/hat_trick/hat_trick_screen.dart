import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../multiplayer/buzz_bridge.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import '../buzz_game_view.dart';
import '../buzz_race_controller.dart';
import '../game_screen_support.dart';
import 'hat_trick_controller.dart';

class HatTrickScreen extends StatefulWidget {
  const HatTrickScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<HatTrickScreen> createState() => _HatTrickScreenState();
}

class _HatTrickScreenState extends State<HatTrickScreen>
    with TickerProviderStateMixin<HatTrickScreen>, GameScreenSupport<HatTrickScreen> {
  static const _mode = GameModeId.hatTrick;
  HatTrickController? _c;
  bool _empty = false;
  bool _showAll = false;
  int _rejectSeen = 0;
  final _rng = Random();

  static const _hatTrickLines = [
    'HAT-TRICK! All three!',
    'He’s only gone and found the hat-trick!',
    'Match ball for that one!',
    'All three clubs - take a bow!',
  ];
  static const _twoLines = [
    'Two out of three ain’t bad.',
    'Two clubs - a decent shout.',
    'So close to the hat-trick!',
  ];
  static const _zeroLines = [
    'Never played for any of them!',
    'Not even one of the three!',
  ];

  String _pick(List<String> lines) => lines[_rng.nextInt(lines.length)];

  @override
  void initState() {
    super.initState();
    allowTableMode();
    _load();
  }

  Future<void> _load() async {
    final t = widget.round.tournament;
    final source = services.challenges;
    final qs = <HatTrickSet>[];
    for (var i = 0; i < t.config.questionsPerRound; i++) {
      final q = await source.hatTrick(t.config.difficulty, t.usedIds(_mode), eras: t.config.eraMask);
      if (q == null) break;
      t.markUsed(_mode, q.id);
      qs.add(q);
    }
    if (!mounted) return;
    if (qs.isEmpty) {
      setState(() => _empty = true);
      return;
    }
    final c = HatTrickController(teamCount: t.teamCount, questions: qs, answerSeconds: t.config.answerSeconds);
    c.addListener(() {
      if (c.rejectSerial != _rejectSeen) {
        _rejectSeen = c.rejectSerial;
        nudgeAnswer('${c.rejected} has gone - name someone else');
      }
      final e = c.lastEvent;
      final pick = c.picks.values.isEmpty ? null : _lastPick(c);
      handleEvent(c.eventSerial, e,
          miss: c.lastMiss,
          clock: c.secondsLeft,
          matchStart: t.rounds.isEmpty,
          line: switch (e) {
            GameEvent.deepCut => _pick(_hatTrickLines),
            GameEvent.correct when pick?.hits == 2 => _pick(_twoLines),
            GameEvent.wrong => _pick(_zeroLines),
            _ => null,
          });
      if (c.questionIndex != _lastQuestion) {
        _lastQuestion = c.questionIndex;
        _showAll = false;
      }
      if (mounted) setState(() {});
    });
    final room = roomFor(t);
    if (room != null) {
      final players = services.repo.players;
      _bridge = BuzzBridge(
        room: room,
        controller: c,
        tournament: t,
        players: players,
        title: 'HAT-TRICK',
        prompt: 'Name a player - a point for each club he played for',
        question: () => {
          'clubs': [for (final club in c.current.clubs) club.name],
          'picks': [
            for (final e in c.picks.entries)
              {
                'team': e.key,
                'player': e.value.player.name,
                'hits': [for (final h in e.value.clubs) h],
                'points': e.value.points * widget.round.multiplier,
              },
          ],
          'clock': c.lockedOut.isEmpty ? 'BUZZ IN' : 'YOUR GO',
        },
        // Voice on the phones leans towards players with two or three.
        answerIds: () => {
          for (final id in c.current.played.keys)
            if (c.current.hits(id) >= 2 && !c.isTaken(id)) id,
        },
        reveal: () => _heroes(c).map((p) => p.name).toList(),
        faceOff: () => null,
        paused: () => false,
        multiplier: widget.round.multiplier,
      )
        ..addListener(() {
          if (mounted) setState(() {});
        })
        ..start();
    }
    setState(() => _c = c);
    startClock(c.advance);
  }

  /// The answer that's just gone in (the team that most recently had a go).
  HatTrickPick? _lastPick(HatTrickController c) {
    final order = c.lockedOut.toList();
    for (final team in order.reversed) {
      if (c.picks[team] case final p?) return p;
    }
    return null;
  }

  List<Player> _heroes(HatTrickController c) {
    final players = services.repo.players;
    return [for (final id in c.current.heroes) if (players.byId(id) case final p?) p]
      ..sort((a, b) => b.fame.compareTo(a.fame));
  }

  List<Player> _twos(HatTrickController c) {
    final players = services.repo.players;
    return [for (final id in c.current.twos) if (players.byId(id) case final p?) p]
      ..sort((a, b) => b.fame.compareTo(a.fame));
  }

  BuzzBridge? _bridge;
  int _lastQuestion = 0;

  @override
  void dispose() {
    disposeGameSupport();
    _bridge?.dispose();
    _c?.dispose();
    super.dispose();
  }

  List<HatTrickPickView> _pickViews(HatTrickController c) {
    final t = widget.round.tournament;
    return [
      for (final e in c.picks.entries)
        HatTrickPickView(
          team: t.teamCount == 1 ? '' : t.teamName(e.key),
          colorIndex: t.config.teams[e.key].colorIndex,
          player: e.value.player.name,
          hits: e.value.clubs,
          points: e.value.points * widget.round.multiplier,
        ),
    ];
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
    final t = widget.round.tournament;
    final clubs = [for (final club in c.current.clubs) club.name];
    final heroes = _heroes(c);
    final twos = _twos(c);
    final picks = _pickViews(c);

    return BuzzGameView(
      round: widget.round,
      controller: c,
      commentary: commentaryText,
      timerLabel: c.lockedOut.isEmpty ? 'BUZZ IN' : 'YOUR GO',
      lockedLabel: 'ANSWERED',
      onFinished: () => widget.round.onComplete(c.result()),
      remoteAnswerer: _bridge?.remote?.name,
      phoneTeams: _bridge?.phoneTeams() ?? const {},
      question: (compact) => HatTrickCard(clubs: clubs, picks: picks, compact: compact),
      resolvedHeader: Column(children: [
        if (c.picks.isEmpty)
          Text(t.teamCount == 1 ? 'NO ANSWER' : 'NOBODY ANSWERED', style: AppText.headline(36, color: Palette.danger))
        else if (t.teamCount == 1) ...[
          Text('+${c.lastSolo}', style: AppText.headline(64, color: Palette.yellow)),
          if (c.picks[0]?.hatTrick ?? false) Text('HAT-TRICK!', style: AppText.headline(30, color: Palette.gold)),
        ] else
          Text(c.picks.values.any((p) => p.hatTrick) ? 'HAT-TRICK!' : 'ALL ANSWERS IN',
              style: AppText.headline(34, color: Palette.yellow)),
      ]),
      resolvedDetail: Column(children: [
        Text(
          heroes.length == 1 ? 'THE HAT-TRICK ANSWER' : 'THE ${heroes.length} HAT-TRICK ANSWERS',
          style: AppText.label(13, color: Palette.gold),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [for (final p in heroes) Chip(label: Text(p.name), backgroundColor: Palette.cardHigh)],
        ),
        if (twos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('${twos.length} PLAYED FOR TWO OF THEM', style: AppText.label(13)),
          const SizedBox(height: 6),
          if (_showAll || twos.length <= 8)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [for (final p in twos) Chip(label: Text(p.name), backgroundColor: Palette.card)],
            )
          else ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [for (final p in twos.take(8)) Chip(label: Text(p.name), backgroundColor: Palette.card)],
            ),
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text('SHOW ALL', style: AppText.label(15, color: Palette.yellow)),
            ),
          ],
        ],
      ]),
    );
  }
}

/// One team's answer, as the card shows it (the host and the phones alike).
class HatTrickPickView {
  const HatTrickPickView(
      {required this.team, required this.colorIndex, required this.player, required this.hits, required this.points});
  final String team;
  final int colorIndex;
  final String player;
  final List<bool> hits;
  final int points;
}

/// The three clubs, and under them every answer so far: who, which of the
/// three clubs (ticks), and the points.
class HatTrickCard extends StatelessWidget {
  const HatTrickCard({super.key, required this.clubs, this.picks = const [], this.compact = false});
  final List<String> clubs;
  final List<HatTrickPickView> picks;

  /// Table mode, or the answer box is up: smaller.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 26.0 : 38.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: compact ? 8 : 14, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, club) in clubs.indexed) ...[
            if (i > 0)
              Icon(Icons.add_rounded, color: Palette.yellow, size: compact ? 18 : 26),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _Number(i + 1, size: size * 0.55),
                const SizedBox(width: 8),
                Text(club.toUpperCase(), style: AppText.headline(size)),
              ]),
            ),
          ],
          if (picks.isNotEmpty) ...[
            SizedBox(height: compact ? 6 : 10),
            const Divider(color: Palette.line, height: 1),
            SizedBox(height: compact ? 4 : 8),
            for (final p in picks) _PickRow(pick: p, compact: compact),
          ],
        ]),
      ),
    );
  }
}

class _Number extends StatelessWidget {
  const _Number(this.n, {required this.size, this.lit});
  final int n;
  final double size;

  /// Null: just the number; true/false: a tick for one of the clubs.
  final bool? lit;

  @override
  Widget build(BuildContext context) {
    final colour = switch (lit) { true => Palette.green, false => Palette.card, null => Palette.yellow };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      child: Text('$n', style: AppText.headline(size * 0.62, color: lit == false ? Palette.muted : Palette.pitchDeep)),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.pick, required this.compact});
  final HatTrickPickView pick;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          if (pick.team.isNotEmpty) ...[
            TeamChip(name: pick.team, colorIndex: pick.colorIndex, size: compact ? 12 : 14),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(pick.player,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.headline(compact ? 18 : 22)),
          ),
          for (final (i, h) in pick.hits.indexed)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _Number(i + 1, size: compact ? 18 : 22, lit: h),
            ),
          SizedBox(
            width: compact ? 34 : 42,
            child: Text('+${pick.points}',
                textAlign: TextAlign.right,
                style: AppText.headline(compact ? 18 : 22, color: pick.points == 0 ? Palette.danger : Palette.yellow)),
          ),
        ]),
      );
}
