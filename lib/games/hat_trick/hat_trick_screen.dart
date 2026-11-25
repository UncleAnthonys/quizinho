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

/// Each club's colour on the card; an answer's dots light up in it.
const hatTrickColours = [Color(0xFFFFCC29), Color(0xFF4C8BFF), Color(0xFFFF6FD8)];

/// The three clubs in a triangle, each in its own colour, and under them every
/// answer so far: who, a dot per club (lit in its colour if he played there),
/// and the points. [compact] (the answer box is up, or table mode): the clubs
/// in one row.
class HatTrickCard extends StatelessWidget {
  const HatTrickCard({super.key, required this.clubs, this.picks = const [], this.compact = false});
  final List<String> clubs;
  final List<HatTrickPickView> picks;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tiles = [for (final (i, c) in clubs.indexed) _ClubTile(name: c, colour: hatTrickColours[i], compact: compact)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 8 : 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (compact)
            Row(children: [
              for (final (i, t) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: t),
              ],
            ])
          else
            CustomPaint(
              painter: _TrianglePainter(),
              child: Column(children: [
                Row(children: [const Spacer(), Expanded(flex: 4, child: tiles[0]), const Spacer()]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: tiles[1]),
                  const SizedBox(width: 44),
                  Expanded(child: tiles[2]),
                ]),
              ]),
            ),
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

/// A club on the card: its name on a dark tile edged in its colour.
class _ClubTile extends StatelessWidget {
  const _ClubTile({required this.name, required this.colour, required this.compact});
  final String name;
  final Color colour;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        height: compact ? 46 : 68,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.pitchDeep,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colour, width: 2.5),
          boxShadow: [BoxShadow(color: colour.withValues(alpha: 0.35), blurRadius: 14)],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            // Long names on two lines ("MANCHESTER / CITY") rather than tiny.
            name.toUpperCase().replaceFirst(' ', name.length > 12 ? '\n' : ' '),
            textAlign: TextAlign.center,
            style: AppText.headline(compact ? 20 : 28, color: Palette.text).copyWith(height: 1.0),
          ),
        ),
      );
}

/// The lines joining the three clubs, and a ball in the middle.
class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final top = Offset(size.width / 2, 34);
    final left = Offset(size.width * 0.25, size.height - 34);
    final right = Offset(size.width * 0.75, size.height - 34);
    final line = Paint()
      ..color = Palette.line
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..moveTo(top.dx, top.dy)..lineTo(left.dx, left.dy)..lineTo(right.dx, right.dy)..close(), line);
    final centre = Offset(size.width / 2, (top.dy + left.dy * 2) / 3 + 6);
    canvas.drawCircle(centre, 13, Paint()..color = Palette.text);
    canvas.drawCircle(centre, 13, Paint()..color = Palette.pitchDeep..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawCircle(centre, 4.5, Paint()..color = Palette.pitchDeep);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => false;
}

/// A dot per club: lit in the club's colour if the player was there.
class _Dot extends StatelessWidget {
  const _Dot({required this.colour, required this.lit, required this.size});
  final Color colour;
  final bool lit;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        margin: const EdgeInsets.only(left: 5),
        decoration: BoxDecoration(
          color: lit ? colour : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: lit ? colour : Palette.muted.withValues(alpha: 0.5), width: 2),
          boxShadow: lit ? [BoxShadow(color: colour.withValues(alpha: 0.6), blurRadius: 8)] : null,
        ),
      );
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
          for (final (i, h) in pick.hits.indexed) _Dot(colour: hatTrickColours[i], lit: h, size: compact ? 14 : 18),
          SizedBox(
            width: compact ? 36 : 44,
            child: Text('+${pick.points}',
                textAlign: TextAlign.right,
                style: AppText.headline(compact ? 18 : 22, color: pick.points == 0 ? Palette.danger : Palette.yellow)),
          ),
        ]),
      );
}
