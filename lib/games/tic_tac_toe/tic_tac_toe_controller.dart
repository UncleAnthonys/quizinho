import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../buzz_race_controller.dart' show GameEvent;

/// Three clubs across the top, three down the side. Square (r, c) needs a
/// player who played for both rows[r] and cols[c].
class TicTacToeGrid {
  const TicTacToeGrid({required this.rows, required this.cols, required this.answers});
  final List<Club> rows;
  final List<Club> cols;

  /// Valid player IDs per square, index = row * 3 + col. Never empty.
  final List<Set<String>> answers;

  String get id => [...rows, ...cols].map((c) => c.id).join('-');
}

/// Builds a grid where every square has at least one valid answer.
/// [minFame] keeps clubs recognisable (5 = only giants). Lowers itself if
/// nothing fits. Returns null only if the data can't support a grid at all.
///
/// [maxLevel] drops club pairs harder than that (level 4 = obscure leagues).
/// With [answerFame], every square must also have at least [minKnownAnswers]
/// well-known answers (fame 3+), so it's gettable rather than a trivia wall.
TicTacToeGrid? generateTicTacToeGrid(
  List<ClubConnection> connections, {
  required Random random,
  int minFame = 4,
  int maxLevel = 4,
  int minKnownAnswers = 0,
  int Function(String playerId)? answerFame,
  Set<String> avoid = const {},
  int attempts = 300,
}) {
  final clubs = <String, Club>{};
  final links = <String, Map<String, ClubConnection>>{};
  for (final c in connections) {
    if (c.answerIds.isEmpty || c.difficulty > maxLevel) continue;
    if (minKnownAnswers > 0 && answerFame != null) {
      if (c.answerIds.where((id) => answerFame(id) >= 3).length < minKnownAnswers) continue;
    }
    clubs[c.clubA.id] = c.clubA;
    clubs[c.clubB.id] = c.clubB;
    links.putIfAbsent(c.clubA.id, () => {})[c.clubB.id] = c;
    links.putIfAbsent(c.clubB.id, () => {})[c.clubA.id] = c;
  }

  for (var fame = minFame; fame >= 1; fame--) {
    final pool = [
      for (final id in links.keys)
        if (clubs[id]!.fame >= fame && links[id]!.length >= 3) id,
    ];
    if (pool.length < 6) continue;
    for (var i = 0; i < attempts; i++) {
      final rows = (List.of(pool)..shuffle(random)).take(3).toList();
      final common = pool.where((id) => !rows.contains(id) && rows.every((r) => links[r]!.containsKey(id))).toList();
      if (common.length < 3) continue;
      final cols = (common..shuffle(random)).take(3).toList();
      final grid = TicTacToeGrid(
        rows: [for (final r in rows) clubs[r]!],
        cols: [for (final c in cols) clubs[c]!],
        answers: [
          for (final r in rows)
            for (final c in cols) links[r]![c]!.answerIds,
        ],
      );
      if (!avoid.contains(grid.id)) return grid;
    }
  }
  return null;
}

enum TttPhase { choosing, answering, finished }

enum TttSubmit { claimed, missed, alreadyUsed, ignored }

/// Turn-based Tic-Tac-Toe for 2+ teams: pick a square, name a player for
/// both clubs to claim it. Three in a row wins; each player once per grid.
class TicTacToeController extends ChangeNotifier {
  TicTacToeController({
    required this.grid,
    required this.teamCount,
    int startTeam = 0,
    this.answerSeconds = 20,
    this.maxTurns = 18,
    this.stallLaps = 2,
  }) : currentTeam = startTeam % teamCount;

  final TicTacToeGrid grid;
  final int teamCount;
  final int answerSeconds;

  /// Stops a stalemate dragging on: after this many turns, most squares wins.
  final int maxTurns;

  /// Game also ends when every team has gone this many times in a row
  /// without claiming a square — nobody knows the rest, so move on.
  final int stallLaps;

  static const int lineBonus = 3;
  static const List<List<int>> lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
    [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
    [0, 4, 8], [2, 4, 6], // diagonals
  ];

  final List<int?> owner = List<int?>.filled(9, null);
  final List<String?> claimedWith = List<String?>.filled(9, null);
  final Set<String> usedPlayers = {};

  TttPhase phase = TttPhase.choosing;
  int currentTeam;
  int? selected;
  double secondsLeft = 0;
  int turns = 0;

  /// Turns in a row that claimed nothing (misses, timeouts and passes).
  int dryTurns = 0;

  /// Bumps every time a new team's turn starts.
  int turnSerial = 0;
  List<int>? winningLine;
  int? winner;

  GameEvent? lastEvent;
  int eventSerial = 0;

  bool canChoose(int square) => phase == TttPhase.choosing && owner[square] == null;
  double get fractionLeft => answerSeconds == 0 ? 0 : (secondsLeft / answerSeconds).clamp(0.0, 1.0);
  int squaresOf(int team) => owner.where((o) => o == team).length;

  void choose(int square) {
    if (!canChoose(square)) return;
    selected = square;
    phase = TttPhase.answering;
    secondsLeft = answerSeconds.toDouble();
    notifyListeners();
  }

  /// Turns left before a run of no claims ends the game.
  int get turnsUntilStall => stallLaps * teamCount - dryTurns;

  void advance(Duration elapsed) {
    if (phase != TttPhase.answering) return;
    secondsLeft -= elapsed.inMicroseconds / 1e6;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      _miss(timeout: true);
      return;
    }
    notifyListeners();
  }

  TttSubmit submit(Player p) {
    final sq = selected;
    if (phase != TttPhase.answering || sq == null) return TttSubmit.ignored;
    if (usedPlayers.contains(p.id)) return TttSubmit.alreadyUsed;
    if (grid.answers[sq].contains(p.id)) {
      usedPlayers.add(p.id);
      _claim(sq, p.name);
      return TttSubmit.claimed;
    }
    _miss();
    return TttSubmit.missed;
  }

  /// Answer not in our database; the room voted.
  void submitDisputed({required bool allowed}) {
    final sq = selected;
    if (phase != TttPhase.answering || sq == null) return;
    allowed ? _claim(sq, 'Room vote') : _miss();
  }

  /// Gives up the turn: from a picked square, or without picking one at all.
  /// Once a square is picked the team is committed to it — no switching.
  void pass() {
    if (phase == TttPhase.answering) {
      _miss();
    } else if (phase == TttPhase.choosing) {
      _emit(GameEvent.nobodyGotIt);
      dryTurns++;
      _nextTurn();
    }
  }

  RoundResult result() => RoundResult(
        mode: GameModeId.ticTacToe,
        points: {
          for (var t = 0; t < teamCount; t++) t: squaresOf(t) + (winner == t ? lineBonus : 0),
        },
      );

  void _claim(int sq, String name) {
    dryTurns = 0;
    owner[sq] = currentTeam;
    claimedWith[sq] = name;
    _emit(GameEvent.correct);
    for (final line in lines) {
      if (line.every((i) => owner[i] == currentTeam)) {
        winningLine = line;
        winner = currentTeam;
        _finish();
        return;
      }
    }
    if (owner.every((o) => o != null)) {
      _finish();
      return;
    }
    _nextTurn();
  }

  void _miss({bool timeout = false}) {
    _emit(timeout ? GameEvent.timeUp : GameEvent.wrong);
    dryTurns++;
    _nextTurn();
  }

  void _nextTurn() {
    turns++;
    selected = null;
    if (turns >= maxTurns || dryTurns >= stallLaps * teamCount) {
      _finish();
      return;
    }
    currentTeam = (currentTeam + 1) % teamCount;
    phase = TttPhase.choosing;
    turnSerial++;
    notifyListeners();
  }

  void _finish() {
    phase = TttPhase.finished;
    selected = null;
    _emit(GameEvent.complete);
    notifyListeners();
  }

  void _emit(GameEvent e) {
    lastEvent = e;
    eventSerial++;
  }

  /// Best squares count, for "most squares" when nobody makes a line.
  int get mostSquares => List.generate(teamCount, squaresOf).reduce(max);
}
