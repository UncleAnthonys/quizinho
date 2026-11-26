import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/football_repository.dart' show ChallengeSource;
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
    'They’ve only gone and found the hat-trick!',
    'Match ball for that one!',
    'All three clubs - take a bow!',
    'Get the match ball signed!',
    'That’s a hat-trick - somebody’s done their homework.',
    'Someone’s been playing too much Football Manager.',
    'Hat-trick! Frame it.',
    'The anorak strikes again.',
    'Someone’s been on Transfermarkt.',
    'Three out of three. Different gravy.',
  ];
  static const _twoLines = [
    'Two out of three ain’t bad.',
    'Two clubs - a decent shout.',
    'Two from three. Solid, not spectacular.',
    'Played the safe one there.',
    'Bottled the hat-trick? Two’ll do.',
    'Two - but the hat-trick was right there!',
    'Banked the two. Sensible. Boring, but sensible.',
  ];
  static const _oneLines = [
    'One club. It’s a start.',
    'Just the one - better than nothing.',
    'Scraped a point there.',
    'That’s a squad player answer.',
    'Points on the board… just about.',
    'A tap-in’s still a goal.',
    'The bare minimum. Literally.',
  ];
  static const _zeroLines = [
    'Never played for any of them!',
    'Not even one of the three!',
    'Did you even read the clubs?',
    'Zero. Nil. Nothing.',
    'He’s never been near any of them.',
    'You’ve just named a random footballer, haven’t you?',
    'Confidently wrong!',
    'Not even in the same postcode.',
  ];

  /// Buzzed, then the answer clock ran out.
  static const _timeoutLines = [
    'Froze on the line!',
    'Too long on the ball!',
    'The clock’s beaten you.',
    'Held out for the hat-trick… and got nothing.',
    'Greedy! Should’ve banked the two.',
    'That’s what happens when you wait for the perfect pass.',
    'Brain buffering…',
    'The transfer window’s slammed shut!',
  ];

  /// The set's clock ran out with nobody buzzing.
  static const _nobodyLines = [
    'Nobody fancied that one?',
    'Tumbleweed.',
    'Not a single shout - shocking.',
  ];

  /// A random line - never the same one twice in a row.
  String _pick(List<String> lines) {
    var line = lines[_rng.nextInt(lines.length)];
    if (line == _lastLine && lines.length > 1) {
      line = lines[(lines.indexOf(line) + 1 + _rng.nextInt(lines.length - 1)) % lines.length];
    }
    return _lastLine = line;
  }

  String? _lastLine;

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
      final q = await _deal(source, t);
      if (q == null) break;
      t.markUsed(_mode, q.id);
      source.history.add('hattrick', q.id);
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
            GameEvent.correct => _pick(_oneLines),
            GameEvent.wrong => _pick(_zeroLines),
            // A team's answer clock ran out (others still to go, or the last).
            GameEvent.timeUp when c.phase != BuzzPhase.resolved => _pick(_timeoutLines),
            GameEvent.nobodyGotIt when c.lastMiss == 'Time ran out' => _pick(_timeoutLines),
            // The set's clock ran out before anyone buzzed.
            GameEvent.timeUp when c.picks.isEmpty && c.lockedOut.isEmpty => _pick(_nobodyLines),
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
          // Named already: the phones' answer boxes turn them away too.
          'taken': [for (final p in c.picks.values) p.player.id],
          // The set's over: the phones list the 2-club players too, like here.
          if (c.phase == BuzzPhase.resolved) 'twos': [for (final p in _twos(c)) p.name],
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

  /// How many fresh sets to look at before dealing one.
  static const _candidates = 8;

  /// How far back (sets this phone has had) a shared club still counts.
  static const _memory = 30;

  /// The next set: of a few fresh ones, the least like what's been played
  /// lately - so Chelsea, City or the same pair of clubs don't keep coming
  /// round, without dropping any sets. Set ids are the three club ids. Never
  /// a club that's already been in this match (back-to-back Juventus +
  /// Forest sets were the same question).
  Future<HatTrickSet?> _deal(ChallengeSource source, Tournament t) async {
    final used = t.usedIds(_mode);
    final inMatch = {for (final id in used) ...id.split('|')};
    final history = source.history.order('hattrick');
    final recent = [
      for (final id in history.reversed.take(_memory)) id.split('|').toSet(),
    ];
    double penalty(HatTrickSet s) {
      var p = 0.0;
      for (final (age, clubs) in recent.indexed) {
        final shared = s.clubs.where((c) => clubs.contains(c.id)).length;
        if (shared == 0) continue;
        p += (shared >= 2 ? 10 : 1) * (1 - age / _memory);
      }
      return p;
    }

    final seen = <String>{};
    HatTrickSet? best, any;
    var bestScore = double.infinity;
    for (var tries = 0; tries < _candidates * 4 && seen.length < _candidates; tries++) {
      final s = await source.hatTrick(t.config.difficulty, {...used, ...seen}, eras: t.config.eraMask, record: false);
      if (s == null) break;
      seen.add(s.id);
      any ??= s;
      if (s.clubs.any((c) => inMatch.contains(c.id))) continue;
      final score = penalty(s);
      if (score < bestScore) {
        best = s;
        bestScore = score;
        if (score == 0) break; // nothing in common with anything recent
      }
    }
    // Only sets with a club from this match left: better that than none.
    return best ?? any;
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
      canPick: (p) {
        if (!c.isTaken(p.id)) return true;
        nudgeAnswer('${p.name} has gone - name someone else');
        return false;
      },
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
        ] else if (c.picks.values.any((p) => p.hatTrick)) ...[
          // Who got it, big: it's the moment of the game.
          Text('HAT-TRICK!', style: AppText.headline(56, color: Palette.gold)),
          for (final e in c.picks.entries)
            if (e.value.hatTrick)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TeamChip(name: t.teamName(e.key), colorIndex: t.config.teams[e.key].colorIndex),
                  const SizedBox(width: 8),
                  Flexible(child: Text(e.value.player.name, style: AppText.headline(26))),
                ]),
              ),
        ] else
          Text('NO HAT-TRICK THIS TIME', style: AppText.headline(30, color: Palette.yellow)),
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

/// What to do, the three clubs side by side, and under them every answer so
/// far: who, which of the clubs he played for, and the points. [compact]
/// (the answer box is up, or table mode): smaller, no instructions. [compact] (the answer box is up, or table mode): the clubs
/// in one row.
class HatTrickCard extends StatelessWidget {
  const HatTrickCard({super.key, required this.clubs, this.picks = const [], this.compact = false});
  final List<String> clubs;
  final List<HatTrickPickView> picks;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tiles = [for (final c in clubs) _ClubTile(name: c, compact: compact)];
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
          if (!compact) ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('1 POINT FOR EACH CLUB HE PLAYED FOR',
                  style: AppText.headline(20, color: Palette.yellow)),
            ),
            Text('All three = HAT-TRICK, 4 points', style: AppText.label(13, color: Palette.text)),
            const SizedBox(height: 10),
          ],
          Row(children: [
            for (final (i, t) in tiles.indexed) ...[
              if (i > 0) SizedBox(width: compact ? 6 : 8),
              Expanded(child: t),
            ],
          ]),
          if (picks.isNotEmpty) ...[
            SizedBox(height: compact ? 6 : 10),
            const Divider(color: Palette.line, height: 1),
            SizedBox(height: compact ? 4 : 8),
            for (final p in picks) _PickRow(pick: p, clubs: clubs, compact: compact),
          ],
        ]),
      ),
    );
  }
}

/// A club on the card: its name on a dark tile edged in yellow.
class _ClubTile extends StatelessWidget {
  const _ClubTile({required this.name, required this.compact});
  final String name;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        height: compact ? 46 : 84,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.pitchDeep,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.yellow, width: 2.5),
          boxShadow: [BoxShadow(color: Palette.yellow.withValues(alpha: 0.25), blurRadius: 12)],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            // Long names on two lines ("MANCHESTER / CITY") rather than tiny.
            name.toUpperCase().replaceFirst(' ', name.length > 12 ? '\n' : ' '),
            textAlign: TextAlign.center,
            style: AppText.headline(compact ? 20 : 26, color: Palette.text).copyWith(height: 1.0),
          ),
        ),
      );
}

/// One answer: the team, the player, which of the clubs he played for (in
/// words), and the points.
class _PickRow extends StatelessWidget {
  const _PickRow({required this.pick, required this.clubs, required this.compact});
  final HatTrickPickView pick;
  final List<String> clubs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final played = [for (final (i, h) in pick.hits.indexed) if (h && i < clubs.length) clubs[i]];
    if (played.length == 3) return _hatTrickRow();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        if (pick.team.isNotEmpty) ...[
          TeamChip(name: pick.team, colorIndex: pick.colorIndex, size: compact ? 12 : 14),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(pick.player,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.headline(compact ? 18 : 22)),
            Text(
              played.isEmpty
                  ? 'None of them'
                  : played.length == 3
                      ? 'All three - HAT-TRICK!'
                      : played.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(compact ? 11 : 13,
                  color: played.isEmpty ? Palette.danger : (played.length == 3 ? Palette.gold : Palette.green)),
            ),
          ]),
        ),
        Text('+${pick.points}',
            style: AppText.headline(compact ? 20 : 26, color: pick.points == 0 ? Palette.danger : Palette.yellow)),
      ]),
    );
  }

  /// All three: the row turns gold - it can't be missed.
  Widget _hatTrickRow() => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 4 : 8),
        decoration: BoxDecoration(
          color: Palette.gold,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Palette.gold.withValues(alpha: 0.5), blurRadius: 16)],
        ),
        child: Row(children: [
          if (pick.team.isNotEmpty) ...[
            TeamChip(name: pick.team, colorIndex: pick.colorIndex, size: compact ? 12 : 14),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(pick.player,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.headline(compact ? 18 : 22, color: Palette.pitchDeep)),
              Row(children: [
                Icon(Icons.sports_soccer, size: compact ? 13 : 16, color: Palette.pitchDeep),
                const SizedBox(width: 4),
                Text('HAT-TRICK!', style: AppText.headline(compact ? 14 : 18, color: Palette.pitchDeep)),
              ]),
            ]),
          ),
          Text('+${pick.points}', style: AppText.headline(compact ? 22 : 30, color: Palette.pitchDeep)),
        ]),
      );
}
