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
    final inEras = await repo.allClubConnections(eras: _t.config.eraMask);
    TicTacToeGrid? make(List<ClubConnection> conns, {bool strict = true}) => generateTicTacToeGrid(conns,
        random: rnd,
        minFame: minFame,
        maxLevel: strict ? maxLevel : 4,
        minKnownAnswers: strict ? known : 0,
        answerFame: fame,
        avoid: used);
    // Not enough in the chosen eras at this difficulty — widen rather than stall.
    var grid = make(inEras);
    if (grid == null) {
      final all = await repo.allClubConnections();
      grid = make(all) ?? make(inEras, strict: false) ?? make(all, strict: false);
    }
    if (!mounted) return;
    if (grid == null) {
      setState(() => _empty = true);
      return;
    }
    _t.markUsed(_mode, grid.id);
    final c = TicTacToeController(
      grid: grid,
      teamCount: _t.teamCount,
      startTeam: _t.standings.last,
      answerSeconds: max(15, _t.config.answerSeconds),
    );
    c.addListener(() => _onChange(c));
    setState(() => _c = c);
    _onChange(c);
    startClock(c.advance);
  }

  void _onChange(TicTacToeController c) {
    if (c.turnSerial != _turnFor) {
      _turnFor = c.turnSerial;
      _turnPlayer = _t.nextTurnPlayer(c.currentTeam);
    }
    handleEvent(c.eventSerial, c.lastEvent);
    if (c.phase == TttPhase.answering) {
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
          content: Text('${p.name} has already been used on this grid — someone else!'),
          duration: const Duration(milliseconds: 1600),
        ));
    } else if (r == TttSubmit.claimed && who != null) {
      _t.creditPlayer(team, who, widget.round.multiplier);
    }
    _pickerKey++;
  }

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(children: [
                Text('TIC-TAC-TOE', style: AppText.label(15, color: Palette.yellow)),
                const Spacer(),
                if (widget.round.multiplier > 1)
                  Text('x${widget.round.multiplier} POINTS', style: AppText.label(15, color: Palette.gold)),
              ]),
            ),
            typing ? const SizedBox.shrink() : CommentaryBanner(text: commentaryText),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), children: [
                typing ? const SizedBox.shrink() : _turnBanner(c),
                typing ? const SizedBox.shrink() : const SizedBox(height: 8),
                typing ? const SizedBox.shrink() : _Board(controller: c, tournament: _t, onTap: c.choose),
                typing ? const SizedBox.shrink() : const SizedBox(height: 12),
                _bottom(c),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _turnBanner(TicTacToeController c) {
    if (c.phase == TttPhase.finished) {
      final w = c.winner;
      return Center(
        child: Text(
          w != null ? '${_t.teamName(w).toUpperCase()} GET THREE IN A ROW!' : 'NO LINE — SQUARES DECIDE IT',
          textAlign: TextAlign.center,
          style: AppText.headline(26, color: Palette.yellow),
        ),
      );
    }
    final team = c.currentTeam;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      TeamChip(name: _turnPlayer ?? _t.teamName(team), colorIndex: _t.config.teams[team].colorIndex, size: 20),
      const SizedBox(width: 10),
      Text(c.phase == TttPhase.choosing ? 'PICK A SQUARE' : 'NAME A PLAYER', style: AppText.headline(22)),
    ]);
  }

  Widget _bottom(TicTacToeController c) {
    if (c.phase == TttPhase.choosing) {
      final left = c.turnsUntilStall;
      return Column(children: [
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
          label: Text("DON'T KNOW ANY — PASS", style: AppText.label(15, color: Palette.text)),
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
          onPass: c.pass,
          onDisputed: (_, allowed) => c.submitDisputed(allowed: allowed),
        ),
      ]);
    }
    // finished
    final standings = List.generate(_t.teamCount, (i) => i)..sort((a, b) => c.squaresOf(b).compareTo(c.squaresOf(a)));
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

class _Board extends StatelessWidget {
  const _Board({required this.controller, required this.tournament, required this.onTap});
  final TicTacToeController controller;
  final Tournament tournament;
  final void Function(int square) onTap;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget clubLabel(Club club) => Container(
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
              club.name.toUpperCase().split(' ').join('\n'),
              textAlign: TextAlign.center,
              style: AppText.headline(17, weight: FontWeight.w800).copyWith(height: 1.05),
            ),
          ),
        );

    Widget square(int i) {
      final ownerTeam = c.owner[i];
      final selected = c.selected == i;
      final winning = c.winningLine?.contains(i) ?? false;
      final colour = ownerTeam == null ? null : tournament.config.teams[ownerTeam].colorIndex;
      return GestureDetector(
        onTap: c.canChoose(i) ? () => onTap(i) : null,
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
          child: ownerTeam == null
              ? Icon(selected ? Icons.mic_rounded : Icons.add_rounded,
                  color: c.canChoose(i) || selected ? Palette.yellow : Palette.muted, size: 30)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    (c.claimedWith[i] ?? '').split(' ').last.toUpperCase(),
                    style: AppText.headline(18, color: Palette.onTeam(colour!)),
                  ),
                ),
        ),
      );
    }

    Widget cell(Widget child) => Expanded(child: AspectRatio(aspectRatio: 1, child: Padding(padding: const EdgeInsets.all(3), child: child)));

    return Column(children: [
      Row(children: [
        cell(const SizedBox()),
        for (final club in c.grid.cols) cell(clubLabel(club)),
      ]),
      for (var r = 0; r < 3; r++)
        Row(children: [
          cell(clubLabel(c.grid.rows[r])),
          for (var col = 0; col < 3; col++) cell(square(r * 3 + col)),
        ]),
    ]);
  }
}
