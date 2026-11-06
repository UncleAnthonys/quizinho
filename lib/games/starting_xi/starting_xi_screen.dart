import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../multiplayer/turn_bridge.dart';
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

  /// Named player for the current turn (null when teams have no names).
  String? _turnPlayer;
  bool _turnAssigned = false;

  void _assignTurnPlayer(StartingXiController c) {
    if (c.phase != BombPhase.handover) {
      _turnAssigned = false;
      return;
    }
    if (_turnAssigned) return;
    _turnAssigned = true;
    _turnPlayer = widget.round.tournament.nextTurnPlayer(c.currentTeam);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = widget.round.tournament;
    final m = await services.challenges.match(t.config.difficulty, t.usedIds(_mode), eras: t.config.eraMask, genders: t.config.genderMask);
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
    _assignTurnPlayer(c);
    c.addListener(() => _onChange(c));
    if (services.room case final room?) _phones = TurnBridge(room, t)..start();
    setState(() => _c = c);
    _syncPhones(c);
    startClock(c.advance);
  }

  /// Each player's turn on their own phone, when they've joined.
  TurnBridge? _phones;

  void _syncPhones(StartingXiController c) {
    final p = _phones;
    if (p == null) return;
    final t = widget.round.tournament;
    final m = c.match;
    final key = '${t.rounds.length}-xi-$_turn';
    final extra = [for (var i = 0; i < t.teamCount; i++) _extra(c, i)];
    switch (c.phase) {
      case BombPhase.handover:
      case BombPhase.ticking:
        // On their own phone the bomb passes straight on — no "tap to start"
        // to buy thinking time. Same on the host phone when it's just one
        // person's (everyone else has joined): nobody's passing it round.
        if (c.phase == BombPhase.handover && (p.phoneFor(c.currentTeam, name: _turnPlayer) != null || _hostIsOnePlayers)) {
          scheduleMicrotask(c.startTurn);
        }
        final ticking = c.phase == BombPhase.ticking;
        p.show(
          key: ticking ? key : '$key-go',
          team: c.currentTeam,
          name: _turnPlayer,
          stage: ticking ? TurnStage.answer : TurnStage.ready,
          title: 'STARTING XI BOMB · ${c.turnSeconds}s',
          headline: 'NAME ${m.targetTeam.toUpperCase()}’S XI',
          sub: '${m.home} v ${m.away} · ${m.score} · ${m.year}',
          game: 'xi',
          board: _view(c),
          extra: extra,
          left: ticking ? c.secondsLeft : null,
          total: ticking ? c.turnSeconds.toDouble() : null,
          index: services.repo.players,
          answers: {for (final s in m.lineup) if (!c.namedBy.containsKey(s.playerId)) s.playerId},
          hint: 'Name a starter…',
          onPick: (pl) => _submit(c, pl),
          onPass: c.pass,
          onReady: c.startTurn,
        );
      case BombPhase.exploded:
        p.idle('BOOM!', game: 'xi', board: _view(c), extra: extra);
      case BombPhase.finished:
        p.idle('Starting XI Bomb', game: 'xi', board: _view(c), extra: extra);
    }
  }

  void _onChange(StartingXiController c) {
    _assignTurnPlayer(c);
    _syncPhones(c);
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
    _phones?.dispose();
    _c?.dispose();
    super.dispose();
  }

  void _submit(StartingXiController c, Player p) {
    final team = c.currentTeam;
    final who = _turnPlayer;
    final r = c.submit(p);
    if (r == SubmitResult.correct && who != null) {
      widget.round.tournament.creditPlayer(team, who, widget.round.multiplier);
    }
    if (r == SubmitResult.alreadyNamed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${p.name} is already on the board — someone else!'),
          duration: const Duration(milliseconds: 1400),
        ));
    }
    _turn++; // fresh answer box (and mic) every time
    _syncPhones(c);
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<bool>(valueListenable: answerTyping, builder: (context, typing, _) => _build(typing));

  /// [typingNow]: an answer is being typed — keyboard up, so the pitch gives way.
  Widget _build(bool typingNow) {
    final t = widget.round.tournament;
    if (_empty) {
      return OutOfChallenges(
        mode: _mode,
        onContinue: () => widget.round.onComplete(RoundResult.empty(_mode, t.teamCount)),
      );
    }
    final c = _c;
    if (c == null) return const LoadingRound();
    final typing = typingNow && c.phase == BombPhase.ticking;
    final colour = t.config.teams[c.currentTeam].colorIndex;
    return XiLayout(
      data: _view(c),
      typing: typing,
      left: c.secondsLeft,
      passing: !_hostIsOnePlayers,
      multiplier: widget.round.multiplier,
      scores: Scoreboard(
        tournament: t,
        highlightTeam: c.phase == BombPhase.finished ? null : c.currentTeam,
        extra: (i) => _extra(c, i),
      ),
      commentary: CommentaryBanner(text: commentaryText),
      onStart: c.startTurn,
      onContinue: c.continueAfterExplosion,
      answerBox: _phones?.remote != null
          ? OnTheirPhone(
              name: _turnPlayer ?? t.teamName(c.currentTeam),
              onSkip: () => setState(() => _phones!.playHere()),
            )
          : PlayerPicker(
              key: ValueKey('xi-$_turn'),
              index: services.repo.players,
              voice: services.voice,
              accent: Palette.team(colour),
              hint: 'Name a starter…',
              onPick: (p) => _submit(c, p),
              isAnswer: (p) => !c.namedBy.containsKey(p.id) && c.match.lineup.any((s) => s.playerId == p.id),
              onPass: c.pass,
            ),
      finish: BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
    );
  }

  /// Everyone but one player has joined on their own phone, so the host
  /// phone is that one player's and is never passed round.
  bool get _hostIsOnePlayers {
    final room = _phones?.room;
    if (room == null) return false;
    final t = widget.round.tournament;
    var notJoined = 0;
    for (var i = 0; i < t.teamCount; i++) {
      final names = t.config.teams[i].players;
      if (names.isEmpty) return false; // team turns without names: unknown
      for (final n in names) {
        if (room.memberFor(i, n) == null) notJoined++;
      }
    }
    return notJoined <= 1;
  }

  String _extra(StartingXiController c, int i) =>
      c.livesLeft[i]! > 0 ? '${'♥' * c.livesLeft[i]!}  ${c.correctByTeam[i]} named' : 'OUT';

  /// Everything both the host and joined phones draw.
  Map<String, Object?> _view(StartingXiController c) {
    final t = widget.round.tournament;
    final m = c.match;
    final lost = c.lastExploded ?? c.currentTeam;
    return {
      'phase': c.phase.name,
      'target': m.targetTeam,
      'match': '${m.home} v ${m.away} · ${m.score} · ${m.year}',
      'title': m.title,
      'lineup': [for (final s in m.lineup) {'p': s.position, 'n': s.playerName, 'i': s.playerId}],
      'named': {for (final e in c.namedBy.entries) e.key: e.value},
      'colours': [for (final team in t.config.teams) team.colorIndex],
      'team': c.currentTeam,
      'teamName': t.teamName(c.currentTeam),
      if (_turnPlayer != null) 'who': _turnPlayer,
      'seconds': c.turnSeconds,
      'lost': t.teamName(lost),
      'out': c.livesLeft[lost]! <= 0,
      'complete': c.isComplete,
      'bonus': [for (final b in c.bonusTeams) {'name': t.teamName(b), 'color': t.config.teams[b].colorIndex}],
      'bonusPts': StartingXiController.winPoints * widget.round.multiplier,
    };
  }
}

/// The whole Starting XI Bomb screen, from a plain snapshot — the host and
/// joined phones draw exactly the same thing. [answerBox] is the answer box
/// (or "on their phone"); [onStart] / [onContinue] / [finish] are the host's
/// taps (left out on a phone that's only watching).
class XiLayout extends StatelessWidget {
  const XiLayout({
    super.key,
    required this.data,
    required this.scores,
    required this.answerBox,
    required this.left,
    this.multiplier = 1,
    this.typing = false,
    this.commentary,
    this.onStart,
    this.onContinue,
    this.finish,
    this.startLabel,
    this.passing = true,
  });

  /// The host phone is being passed round ("PASS TO …"); otherwise "UP NEXT".
  final bool passing;
  final Map<String, Object?> data;
  final Widget scores;
  final Widget answerBox;

  /// Seconds left on the bomb.
  final double left;
  final int multiplier;
  final bool typing;
  final Widget? commentary;
  final VoidCallback? onStart;
  final VoidCallback? onContinue;
  final Widget? finish;

  /// Overrides the handover card's bottom line.
  final String? startLabel;

  List<Object?> _list(String k) => (data[k] as List?) ?? const [];
  int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final phase = '${data['phase']}';
    final finished = phase == 'finished';
    final exploded = phase == 'exploded';
    final lineup = [
      for (final (i, s) in _list('lineup').indexed)
        if (s is Map) LineupSlot(index: i, playerId: '${s['i']}', playerName: '${s['n']}', position: '${s['p']}'),
    ];
    final named = {for (final e in ((data['named'] as Map?) ?? const {}).entries) '${e.key}': _int(e.value)};
    final colours = [for (final c in _list('colours')) _int(c)];
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        foregroundDecoration: BoxDecoration(color: exploded ? Palette.danger.withValues(alpha: 0.18) : Colors.transparent),
        child: PitchBackground(
          child: SafeArea(
            child: Column(children: [
              typing ? const SizedBox.shrink() : scores,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(children: [
                  Row(children: [
                    Text('STARTING XI BOMB', style: AppText.label(15, color: Palette.yellow)),
                    const Spacer(),
                    if (multiplier > 1) Text('x$multiplier POINTS', style: AppText.label(15, color: Palette.gold)),
                  ]),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('NAME ${'${data['target'] ?? ''}'.toUpperCase()}’S XI', style: AppText.headline(30)),
                  ),
                  Text('${data['match'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, fontSize: 13)),
                  Text('${data['title'] ?? ''}', style: AppText.label(13)),
                ]),
              ),
              if (commentary != null) commentary!,
              // Keyboard up: swap the pitch for a one-line list of who's been named.
              if (typing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    named.isEmpty
                        ? 'Nobody named yet'
                        : 'Named: ${[for (final s in lineup) if (named.containsKey(s.playerId)) s.playerName.split(' ').last].join(', ')}',
                    style: AppText.label(14, color: Palette.text),
                  ),
                )
              else
                Flexible(flex: 5, child: _Formation(lineup: lineup, named: named, revealAll: finished, colours: colours)),
              Flexible(flex: 6, child: _bottom(phase, colours)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bottom(String phase, List<int> colours) {
    final team = _int(data['team']);
    final colour = team < colours.length ? colours[team] : 0;
    final who = '${data['who'] ?? data['teamName'] ?? ''}';
    final seconds = _int(data['seconds']);
    final fraction = seconds == 0 ? 0.0 : (left / seconds).clamp(0.0, 1.0);
    if (phase == 'handover') {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: onStart,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Palette.team(colour), borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.phone_iphone, size: 44, color: Palette.onTeam(colour)),
              const SizedBox(height: 6),
              Text(passing ? 'PASS TO' : 'UP NEXT', style: AppText.label(18, color: Palette.onTeam(colour))),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(who.toUpperCase(), style: AppText.headline(54, color: Palette.onTeam(colour))),
              ),
              if (data['who'] != null)
                Text('${data['teamName'] ?? ''}'.toUpperCase(), style: AppText.label(18, color: Palette.onTeam(colour))),
              const SizedBox(height: 6),
              Text(startLabel ?? 'TAP WHEN READY — ${seconds}s ON THE CLOCK',
                  style: AppText.label(15, color: Palette.onTeam(colour))),
            ]),
          ),
        ),
      );
    }
    if (phase == 'ticking') {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(children: [
          Row(children: [
            _Bomb(fraction: fraction),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TeamChip(name: who, colorIndex: colour),
                const SizedBox(height: 6),
                TimerBar(fraction: fraction, seconds: left),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          answerBox,
        ]),
      );
    }
    if (phase == 'exploded') {
      final lost = '${data['lost'] ?? ''}'.toUpperCase();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Shake(child: Text('BOOM!', style: AppText.headline(80, color: Palette.danger))),
          Text(data['out'] == true ? '$lost ARE OUT' : '$lost LOSE A LIFE',
              textAlign: TextAlign.center, style: AppText.headline(30)),
          if (onContinue != null) ...[
            const SizedBox(height: 20),
            BigButton(label: 'Continue', icon: Icons.arrow_forward, onPressed: onContinue),
          ],
        ]),
      );
    }
    final bonus = [for (final b in _list('bonus')) if (b is Map) b];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Text(data['complete'] == true ? 'FULL XI NAMED!' : 'LAST TEAM STANDING', style: AppText.headline(34, color: Palette.yellow)),
        const SizedBox(height: 8),
        if (bonus.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final b in bonus) TeamChip(name: '${b['name']}', colorIndex: _int(b['color'])),
          ]),
        if (bonus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('+${data['bonusPts']}', style: AppText.label(15, color: Palette.gold)),
          ),
        if (finish != null) ...[const SizedBox(height: 16), finish!],
      ]),
    );
  }
}

class _Formation extends StatelessWidget {
  const _Formation({required this.lineup, required this.named, required this.revealAll, required this.colours});
  final List<LineupSlot> lineup;
  final Map<String, int> named;
  final bool revealAll;

  /// Colour index per team.
  final List<int> colours;

  @override
  Widget build(BuildContext context) {
    final lines = <int, List<LineupSlot>>{};
    for (final s in lineup) {
      lines.putIfAbsent(s.line, () => []).add(s);
    }
    // As seen from the stand with the team attacking up the screen: left-sided
    // players (LB, LM, LW) on the left, right-sided on the right.
    int side(LineupSlot s) => s.position.startsWith('L') ? 0 : (s.position.startsWith('R') ? 2 : 1);
    for (final k in lines.keys) {
      final l = lines[k]!;
      lines[k] = [for (final want in const [0, 1, 2]) ...l.where((s) => side(s) == want)];
    }
    final order = lines.keys.toList()..sort((a, b) => b.compareTo(a)); // attack at the top
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final line in order)
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final s in lines[line]!) Expanded(child: _Slot(slot: s, team: named[s.playerId], revealAll: revealAll, colours: colours)),
          ]),
      ]),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.slot, required this.team, required this.revealAll, required this.colours});
  final LineupSlot slot;
  final int? team;
  final bool revealAll;
  final List<int> colours;

  @override
  Widget build(BuildContext context) {
    final shown = team != null || revealAll;
    final colourIndex = team == null || team! >= colours.length ? null : colours[team!];
    final colour = colourIndex == null ? null : Palette.team(colourIndex);
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
              style: AppText.headline(17, color: shown && colourIndex != null ? Palette.onTeam(colourIndex) : Palette.text),
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
