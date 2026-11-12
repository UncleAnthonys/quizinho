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
import 'tic_tac_toe_controller.dart';

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen>
    with TickerProviderStateMixin<TicTacToeScreen>, GameScreenSupport<TicTacToeScreen> {
  static const _mode = GameModeId.ticTacToe;
  TicTacToeController? _c;
  bool _empty = false;
  String? _turnPlayer;
  int _turnFor = -1;
  int _pickerKey = 0;
  int _lastSecond = -1;

  Tournament get _t => widget.round.tournament;

  /// (club fame floor, hardest club-pair level, well-known answers per square)
  static (int, int, int) _settings(Difficulty d) => switch (d) {
        Difficulty.easy => (5, 1, 3),
        Difficulty.medium => (4, 2, 2),
        Difficulty.hard => (4, 3, 1),
        Difficulty.expert => (2, 4, 0),
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = services.repo;
    final used = _t.usedIds(_mode);
    final rnd = Random();
    final (minFame, maxLevel, known) = _settings(_t.config.difficulty);
    int fame(String id) => repo.players.byId(id)?.fame ?? 0;
    final genders = _t.config.genderMask;
    final inEras = await repo.allClubConnections(eras: _t.config.eraMask, genders: genders);
    // Grids this phone has played before come last.
    final history = services.challenges.history;
    final unseen = {...used, ...history.seen('ttt')};
    TicTacToeGrid? make(List<ClubConnection> conns, {bool strict = true, bool fresh = true}) =>
        generateTicTacToeGrid(conns,
            random: rnd,
            minFame: minFame,
            maxLevel: maxLevel, // never harder pairs than the chosen difficulty
            minKnownAnswers: strict ? known : 0,
            answerFame: fame,
            avoid: fresh ? unseen : used);
    // Not enough in the chosen eras at this difficulty — widen rather than stall.
    var grid = make(inEras);
    if (grid == null) {
      final all = await repo.allClubConnections(genders: genders);
      grid = make(all) ??
          make(inEras, fresh: false) ??
          make(all, fresh: false) ??
          make(inEras, strict: false) ??
          make(all, strict: false, fresh: false);
    }
    if (!mounted) return;
    if (grid == null) {
      setState(() => _empty = true);
      return;
    }
    _t.markUsed(_mode, grid.id);
    history.add('ttt', grid.id);
    final c = TicTacToeController(
      grid: grid,
      teamCount: _t.teamCount,
      startTeam: _t.standings.last,
      answerSeconds: max(15, _t.config.answerSeconds),
    );
    c.addListener(() => _onChange(c));
    if (roomFor(_t) case final room?) _phones = TurnBridge(room, _t)..start();
    setState(() => _c = c);
    _onChange(c);
    startClock(c.advance);
  }

  /// Each player's turn on their own phone, when they've joined.
  TurnBridge? _phones;

  void _syncPhones(TicTacToeController c) {
    final p = _phones;
    if (p == null) return;
    final extra = [for (var i = 0; i < _t.teamCount; i++) '${c.squaresOf(i)} ▢'];
    if (c.phase == TttPhase.finished) {
      p.idle(c.winner != null ? '${_t.teamName(c.winner!)} get three in a row!' : 'Squares decide it',
          game: 'ttt', board: _view(c), extra: extra);
      return;
    }
    final answering = c.phase == TttPhase.answering;
    final sq = c.selected;
    p.show(
      key: '${_t.rounds.length}-ttt-${c.turnSerial}${answering ? '-$_pickerKey' : ''}',
      team: c.currentTeam,
      name: _turnPlayer,
      stage: answering ? TurnStage.answer : TurnStage.choose,
      title: 'TIC-TAC-TOE',
      headline: answering && sq != null
          ? '${c.grid.rows[sq ~/ 3].name.toUpperCase()}  +  ${c.grid.cols[sq % 3].name.toUpperCase()}'
          : '',
      game: 'ttt',
      board: _view(c),
      extra: extra,
      left: c.clockRunning ? c.secondsLeft : null,
      total: c.clockRunning ? c.phaseSeconds.toDouble() : null,
      index: services.repo.players,
      answers: sq == null ? const {} : c.grid.answers[sq],
      onPick: (pl) => _submit(c, pl),
      onPass: c.pass,
      onChoose: c.choose,
    );
  }

  void _onChange(TicTacToeController c) {
    if (c.turnSerial != _turnFor) {
      _turnFor = c.turnSerial;
      _turnPlayer = _t.nextTurnPlayer(c.currentTeam);
    }
    _syncPhones(c);
    handleEvent(c.eventSerial, c.lastEvent);
    if (c.clockRunning) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        if (sec <= 5 && sec > 0) services.sound.play(Sfx.tickFast);
      }
    } else {
      _lastSecond = -1;
    }
    if (mounted) setState(() {});
  }

  void _submit(TicTacToeController c, Player p) {
    final team = c.currentTeam;
    final who = _turnPlayer;
    final r = c.submit(p);
    if (r == TttSubmit.alreadyUsed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${p.name} has already been used on this grid - someone else!'),
          duration: const Duration(milliseconds: 1600),
        ));
    } else if (r == TttSubmit.claimed && who != null) {
      _t.creditPlayer(team, who, widget.round.multiplier);
    }
    _pickerKey++;
    _syncPhones(c);
  }

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
    return ValueListenableBuilder<bool>(
      valueListenable: answerTyping,
      builder: (context, typing, _) => _scaffold(c, typing && c.phase == TttPhase.answering),
    );
  }

  /// [typing]: keyboard is up — hide the board, keep the two clubs + answer box.
  Widget _scaffold(TicTacToeController c, bool typing) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            typing
                ? const SizedBox.shrink()
                : Scoreboard(
                    tournament: _t,
                    highlightTeam: c.phase == TttPhase.finished ? null : c.currentTeam,
                    extra: (i) => '${c.squaresOf(i)} ▢',
                  ),
            typing ? const SizedBox.shrink() : CommentaryBanner(text: commentaryText),
            Expanded(
              child: TttLayout(
                data: _view(c),
                multiplier: widget.round.multiplier,
                typing: typing,
                onTap: c.choose,
                bottom: _bottom(c),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Everything both the host and joined phones draw.
  Map<String, Object?> _view(TicTacToeController c) =>
      {...TttBoard.snapshot(c, _t), 'who': _turnPlayer ?? _t.teamName(c.currentTeam)};

  Widget _bottom(TicTacToeController c) {
    if (_phones?.remote case final m?) {
      return OnTheirPhone(
        name: m.name,
        what: c.phase == TttPhase.choosing ? 'is picking a square' : 'is answering',
        onSkip: () => setState(() => _phones!.playHere()),
      );
    }
    if (c.phase == TttPhase.choosing) {
      final left = c.turnsUntilStall;
      return Column(children: [
        if (c.clockRunning) ...[
          TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
          const SizedBox(height: 8),
        ],
        const Text(
          'Tap an empty square, then name a player who played for both clubs.\n'
          'Once you pick a square you\'re locked in. Each player once per grid.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.muted, height: 1.4),
        ),
        if (c.dryTurns > 0) ...[
          const SizedBox(height: 8),
          Text(
            left == 1 ? 'NO SQUARE THIS TURN AND THE GAME ENDS' : '$left MORE TURNS WITHOUT A SQUARE ENDS THE GAME',
            textAlign: TextAlign.center,
            style: AppText.label(14, color: Palette.gold),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: c.pass,
          icon: const Icon(Icons.skip_next_rounded),
          label: Text("DON'T KNOW ANY - PASS", style: AppText.label(15, color: Palette.text)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Palette.text,
            side: const BorderSide(color: Palette.line),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ]);
    }
    if (c.phase == TttPhase.answering) {
      final sq = c.selected!;
      final colour = _t.config.teams[c.currentTeam].colorIndex;
      return Column(children: [
        Text(
          '${c.grid.rows[sq ~/ 3].name.toUpperCase()}  +  ${c.grid.cols[sq % 3].name.toUpperCase()}',
          textAlign: TextAlign.center,
          style: AppText.headline(20, color: Palette.yellow),
        ),
        const SizedBox(height: 6),
        TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
        const SizedBox(height: 8),
        PlayerPicker(
          key: ValueKey('ttt-$_pickerKey-${c.turnSerial}'),
          index: services.repo.players,
          voice: services.voice,
          accent: Palette.team(colour),
          onPick: (p) => _submit(c, p),
          isAnswer: (p) => c.selected != null && c.grid.answers[c.selected!].contains(p.id),
          onPass: c.pass,
          onDisputed: (_, allowed) => c.submitDisputed(allowed: allowed),
        ),
      ]);
    }
    // finished
    final standings = List.generate(_t.teamCount, (i) => i)..sort((a, b) => c.squaresOf(b).compareTo(c.squaresOf(a)));
    if (_t.teamCount == 1) {
      return Column(children: [
        SoloScore(score: c.result().solo ?? 0),
        const SizedBox(height: 12),
        BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
      ]);
    }
    return Column(children: [
      for (final t in standings)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            TeamChip(name: _t.teamName(t), colorIndex: _t.config.teams[t].colorIndex, size: 16),
            const Spacer(),
            Text(
              '${c.squaresOf(t)} squares${c.winner == t ? ' + ${TicTacToeController.lineBonus} line bonus' : ''}',
              style: AppText.headline(20),
            ),
          ]),
        ),
      const SizedBox(height: 12),
      BigButton(label: 'Finish round', icon: Icons.flag, onPressed: () => widget.round.onComplete(c.result())),
    ]);
  }
}

/// The whole Tic-Tac-Toe screen under the scores — title, whose turn, the
/// grid — with the host's or the phone's own [bottom] (answer box, buttons).
class TttLayout extends StatelessWidget {
  const TttLayout({
    super.key,
    required this.data,
    required this.bottom,
    this.multiplier = 1,
    this.typing = false,
    this.onTap,
  });
  final Map<String, Object?> data;
  final Widget bottom;
  final int multiplier;

  /// Keyboard up: the board gives way to the answer box.
  final bool typing;
  final void Function(int square)? onTap;

  @override
  Widget build(BuildContext context) {
    final phase = '${data['phase']}';
    final colours = [for (final c in (data['colours'] as List?) ?? const []) (c as num).toInt()];
    final team = (data['team'] as num?)?.toInt() ?? 0;
    final banner = phase == 'finished'
        ? Center(
            child: Text(
              data['winner'] != null ? '${'${data['winner']}'.toUpperCase()} GET THREE IN A ROW!' : 'NO LINE - SQUARES DECIDE IT',
              textAlign: TextAlign.center,
              style: AppText.headline(26, color: Palette.yellow),
            ),
          )
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TeamChip(name: '${data['who'] ?? ''}', colorIndex: team < colours.length ? colours[team] : 0, size: 20),
            const SizedBox(width: 10),
            Text(phase == 'choosing' ? 'PICK A SQUARE' : 'NAME A PLAYER', style: AppText.headline(22)),
          ]);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(children: [
          Text('TIC-TAC-TOE', style: AppText.label(15, color: Palette.yellow)),
          const Spacer(),
          if (multiplier > 1) Text('x$multiplier POINTS', style: AppText.label(15, color: Palette.gold)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), children: [
          typing ? const SizedBox.shrink() : banner,
          typing ? const SizedBox.shrink() : const SizedBox(height: 8),
          typing ? const SizedBox.shrink() : TttBoard(data: data, onTap: onTap),
          typing ? const SizedBox.shrink() : const SizedBox(height: 12),
          bottom,
        ]),
      ),
    ]);
  }
}

/// The grid, drawn from a plain snapshot ([snapshot]) so joined phones draw
/// exactly what the host does.
class TttBoard extends StatelessWidget {
  const TttBoard({super.key, required this.data, this.onTap});

  /// From [snapshot]: rows, cols (club names), owner/claimed per square,
  /// selected, line (winning squares), colours (per team), choosing.
  final Map<String, Object?> data;
  final void Function(int square)? onTap;

  static Map<String, Object?> snapshot(TicTacToeController c, Tournament t) => {
        'rows': [for (final r in c.grid.rows) r.name],
        'cols': [for (final k in c.grid.cols) k.name],
        'owner': [...c.owner],
        'claimed': [...c.claimedWith],
        if (c.selected != null) 'selected': c.selected,
        if (c.winningLine != null) 'line': c.winningLine,
        'colours': [for (final team in t.config.teams) team.colorIndex],
        'choosing': c.phase == TttPhase.choosing,
        'phase': c.phase.name,
        'team': c.currentTeam,
        if (c.winner != null) 'winner': t.teamName(c.winner!),
      };

  static List<T?> _list<T>(Object? v) => v is List ? [for (final x in v) x is T ? x : null] : const [];

  @override
  Widget build(BuildContext context) {
    final rows = [for (final r in _list<String>(data['rows'])) r ?? ''];
    final cols = [for (final k in _list<String>(data['cols'])) k ?? ''];
    final owner = [for (final o in _list<num>(data['owner'])) o?.toInt()];
    final claimed = _list<String>(data['claimed']);
    final colours = [for (final c in _list<num>(data['colours'])) c?.toInt() ?? 0];
    final line = [for (final i in _list<num>(data['line'])) i?.toInt()];
    final selectedSq = (data['selected'] as num?)?.toInt();
    final choosing = data['choosing'] == true;
    bool canChoose(int i) => choosing && i < owner.length && owner[i] == null;

    Widget clubLabel(String name) => Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Palette.line),
          ),
          // One word per line for multi-word names, then the whole label shrinks
          // to fit — words are never split ("MANCHESTE / R UNITED").
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name.toUpperCase().split(' ').join('\n'),
              textAlign: TextAlign.center,
              style: AppText.headline(17, weight: FontWeight.w800).copyWith(height: 1.05),
            ),
          ),
        );

    Widget square(int i) {
      final ownerTeam = i < owner.length ? owner[i] : null;
      final selected = selectedSq == i;
      final winning = line.contains(i);
      final colour = ownerTeam == null || ownerTeam >= colours.length ? null : colours[ownerTeam];
      final tap = onTap;
      return GestureDetector(
        onTap: canChoose(i) && tap != null ? () => tap(i) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colour != null ? Palette.team(colour) : Palette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: winning ? Palette.yellow : (selected ? Palette.yellow : Palette.line),
              width: winning || selected ? 4 : 1,
            ),
          ),
          child: colour == null
              ? Icon(selected ? Icons.mic_rounded : Icons.add_rounded,
                  color: (canChoose(i) && tap != null) || selected ? Palette.yellow : Palette.muted, size: 30)
              : Padding(
                  padding: const EdgeInsets.all(6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _ClaimName(i < claimed.length ? claimed[i] ?? '' : '', color: Palette.onTeam(colour)),
                  ),
                ),
        ),
      );
    }

    Widget cell(Widget child) => Expanded(child: AspectRatio(aspectRatio: 1, child: Padding(padding: const EdgeInsets.all(3), child: child)));

    return Column(children: [
      Row(children: [
        cell(const SizedBox()),
        for (final club in cols) cell(clubLabel(club)),
      ]),
      for (var r = 0; r < rows.length; r++)
        Row(children: [
          cell(clubLabel(rows[r])),
          for (var col = 0; col < cols.length; col++) cell(square(r * cols.length + col)),
        ]),
    ]);
  }
}

/// A claimed square's player: first name small, full surname big — so
/// "Mac Allister" and "Di María" aren't cut to "ALLISTER" and "MARÍA".
class _ClaimName extends StatelessWidget {
  const _ClaimName(this.name, {required this.color});
  final String name;
  final Color color;

  /// Words that belong to the surname that follows them.
  static const _particles = {
    'mac', 'mc', 'di', 'de', 'da', 'do', 'dos', 'das', 'del', 'della', 'van', 'von', 'der', 'den',
    'ter', 'ten', 'le', 'la', 'el', 'al', 'ben', 'bin', 'st', 'st.',
  };

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+'));
    var start = words.length - 1;
    while (start > 1 && _particles.contains(words[start - 1].toLowerCase())) {
      start--;
    }
    final first = words.length > 1 ? words.sublist(0, start).join(' ') : '';
    final surname = words.sublist(words.length > 1 ? start : 0).join(' ');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (first.isNotEmpty) Text(first.toUpperCase(), style: AppText.label(11, color: color)),
      Text(surname.toUpperCase(), style: AppText.headline(18, color: color)),
    ]);
  }
}
