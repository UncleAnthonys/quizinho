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

/// Where grid clubs come from. English (and Scottish) clubs are the heart of
/// it; then the big names from Spain, Italy, Germany and France; Dutch and
/// Portuguese giants now and then. Anywhere else (MLS, Japan, Brazil...) is
/// rare: one club a grid at most, and only on squares a well-known name answers
/// (Messi at Inter Miami, Iniesta at Vissel Kobe).
const _home = {'GBR'};
const _bigLeagues = {'ESP', 'ITA', 'GER', 'FRA', 'MCO'};
const _nextLeagues = {'NED', 'POR'};

bool _farAway(Club c) {
  if (isGridCategory(c)) return false;
  final k = c.country;
  return !_home.contains(k) && !_bigLeagues.contains(k) && !_nextLeagues.contains(k);
}

/// How often [c] is picked, relative to others. A lesser club from a big
/// league (Hellas Verona, Levante) comes up only now and then.
double gridWeight(Club c) {
  if (isGridCategory(c)) return _categoryWeight;
  final k = c.country;
  final big = c.fame >= 5;
  if (_home.contains(k)) return big ? 6 : (c.fame == 4 ? 2.5 : 0.5);
  if (_bigLeagues.contains(k)) return big ? 4 : 0.5;
  if (_nextLeagues.contains(k)) return big ? 2 : 0.2;
  return big ? 0.4 : 0.1;
}

/// Categories (nations, played with, managed by, trophies): every grid has
/// one, about half have two, never more ([_categoryKinds] decides which sort).
/// [_categoryWeight] only matters for the clubs-only fallback.
const double _categoryWeight = 0.12;
const int _maxCategories = 2;
const double _twoCategories = 0.5;

/// Which sort of category, by share. The kind is picked first, then one of
/// its categories: by count alone the 50 teammates would crowd out the 5
/// trophies and 20 managers.
const _categoryKinds = {'with': 0.35, 'nat': 0.25, 'mgr': 0.20, 'cup': 0.20};

/// "with" (Club teammate of), "nat", "mgr" (Managed by) or "cup" (trophy).
String _kindOf(String id) => id.split(':').first;

/// Every trophy: Champions League, FA Cup, World Cup, Europa League, Euros.
const allTrophies = {'cl', 'fac', 'wc', 'uel', 'euro'};

/// The trophies a difficulty uses, easiest to remember first. Euros winners
/// are few (Spain won three of the last five), so their squares have about
/// three answers; World Cup winners are a wider mix; Europa League squares
/// have plenty of answers, but squad players few remember winning it.
Set<String> trophiesFor(Difficulty d) => switch (d) {
      Difficulty.easy => const {'cl', 'fac'},
      Difficulty.medium => const {'cl', 'fac', 'wc'},
      Difficulty.hard => const {'cl', 'fac', 'wc', 'uel'},
      Difficulty.expert => allTrophies,
    };

/// Two categories that would mostly share their answers: a nation beside the
/// Euros or World Cup (Spain and Euros winners: Silva, Fàbregas, Torres in
/// both columns).
bool _clash(String a, String b) {
  bool international(String id) => _kindOf(id) == 'cup' && const {'euro', 'wc'}.contains(id.split(':')[1]);
  return (_kindOf(a) == 'nat' && international(b)) || (_kindOf(b) == 'nat' && international(a));
}

/// How hard to try around the categories chosen before choosing again. Some
/// fit fewer grids (the FA Cup pairs only with English clubs, and a grid has
/// two a side at most): trying harder keeps each trophy, manager and nation as
/// likely to appear as the shares say, not just as likely to be tried.
const int _triesPerChoice = 15;

/// English clubs on one side of the grid, at most (so 4 of the 6).
const int _maxEnglishASide = 2;

/// A grid that doesn't keep giving the same names. Two rules:
/// - a player can fit three or more squares only where each of those squares
///   has plenty of other answers ([variedMinAnswers]): Giuseppe Rossi was one
///   of five answers in all three Villarreal squares;
/// - no two squares share more than half the smaller one's answers
///   ("Manchester United" beside "Club teammate of Giggs").
bool gridIsVaried(TicTacToeGrid g) {
  final where = <String, List<int>>{};
  for (var i = 0; i < 9; i++) {
    for (final p in g.answers[i]) {
      where.putIfAbsent(p, () => []).add(i);
    }
  }
  for (final squares in where.values) {
    if (squares.length >= 3 && squares.any((i) => g.answers[i].length < variedMinAnswers)) return false;
  }
  for (var i = 0; i < 9; i++) {
    for (var j = i + 1; j < 9; j++) {
      final a = g.answers[i], b = g.answers[j];
      if (a.intersection(b).length * 2 > min(a.length, b.length)) return false;
    }
  }
  return true;
}

/// See [gridIsVaried].
const int variedMinAnswers = 10;

/// Builds a grid where every square has at least one valid answer.
/// [minFame] keeps clubs recognisable (5 = only giants); English clubs get one
/// step more (Charlton, Ipswich). Lowers itself if nothing fits. Returns null
/// only if the data can't support a grid at all.
///
/// [maxLevel] drops club pairs harder than that (level 4 = obscure leagues).
/// With [answerFame], every square must also have at least [minKnownAnswers]
/// well-known answers (fame 3+; 2+ between two English clubs, where a Kevin
/// Davies is known to the people playing if not the wider world), so it's
/// gettable rather than a trivia wall.
TicTacToeGrid? generateTicTacToeGrid(
  List<ClubConnection> connections, {
  required Random random,
  int minFame = 4,
  int maxLevel = 4,
  int minKnownAnswers = 0,
  int Function(String playerId)? answerFame,
  Set<String> avoid = const {},
  int attempts = 300,
  bool distinct = true,
  Set<String> trophies = allTrophies,
  Set<String> usedCategories = const {},
}) {
  final clubs = <String, Club>{};
  final links = <String, Map<String, ClubConnection>>{};
  for (final c in connections) {
    // Category squares all carry level 2 (it isn't worked out per square), so
    // the level would shut them out of Easy altogether; the well-known-answers
    // rule below is what keeps them fair there.
    final levelled = !isGridCategory(c.clubA) || minKnownAnswers == 0;
    if (c.answerIds.isEmpty || (levelled && c.difficulty > maxLevel)) continue;
    if (minKnownAnswers > 0 && answerFame != null) {
      final known = _home.contains(c.clubA.country) && _home.contains(c.clubB.country) ? 2 : 3;
      if (c.answerIds.where((id) => answerFame(id) >= known).length < minKnownAnswers) continue;
    }
    clubs[c.clubA.id] = c.clubA;
    clubs[c.clubB.id] = c.clubB;
    links.putIfAbsent(c.clubA.id, () => {})[c.clubB.id] = c;
    links.putIfAbsent(c.clubB.id, () => {})[c.clubA.id] = c;
  }

  /// [n] of [from], weighted by [gridWeight], no repeats.
  List<String>? pick(List<String> from, int n) {
    final left = List.of(from);
    final out = <String>[];
    for (var i = 0; i < n; i++) {
      if (left.isEmpty) return null;
      final total = left.fold<double>(0, (a, id) => a + gridWeight(clubs[id]!));
      var r = random.nextDouble() * total;
      var chosen = left.last;
      for (final id in left) {
        r -= gridWeight(clubs[id]!);
        if (r <= 0) {
          chosen = id;
          break;
        }
      }
      out.add(chosen);
      left.remove(chosen);
    }
    return out;
  }

  /// A far-away club's squares need a name people know.
  bool fair(String a, String b) {
    if (!_farAway(clubs[a]!) && !_farAway(clubs[b]!)) return true;
    if (answerFame == null) return true;
    return links[a]![b]!.answerIds.any((id) => answerFame(id) >= 4);
  }

  /// One category: its kind first (by [_categoryKinds], among the kinds
  /// [from] has), then one of that kind.
  String? category(List<String> from) {
    final byKind = <String, List<String>>{};
    for (final id in from) {
      byKind.putIfAbsent(_kindOf(id), () => []).add(id);
    }
    final kinds = [for (final k in _categoryKinds.keys) if (byKind.containsKey(k)) k];
    if (kinds.isEmpty) return null;
    // Fewer trophies to choose from, a smaller share for trophies (20% with
    // all five, 8% with two).
    double share(String k) => k == 'cup' ? _categoryKinds[k]! * trophies.length / allTrophies.length : _categoryKinds[k]!;
    var r = random.nextDouble() * kinds.fold<double>(0, (a, k) => a + share(k));
    var kind = kinds.last;
    for (final k in kinds) {
      r -= share(k);
      if (r <= 0) {
        kind = k;
        break;
      }
    }
    final of = byKind[kind]!;
    return of[random.nextInt(of.length)];
  }

  TicTacToeGrid? check(List<String> rows, List<String> cols) {
    if ([...rows, ...cols].where((id) => _farAway(clubs[id]!)).length > 1) return null;
    if ([...rows, ...cols].where((id) => isGridCategory(clubs[id]!)).length > _maxCategories) return null;
    // Never an all-English grid: two English clubs a side at most.
    int english(List<String> ids) => ids.where((id) => _home.contains(clubs[id]!.country)).length;
    if (english(rows) > _maxEnglishASide || english(cols) > _maxEnglishASide) return null;
    if (!rows.every((r) => cols.every((c) => fair(r, c)))) return null;
    final grid = TicTacToeGrid(
      rows: [for (final r in rows) clubs[r]!],
      cols: [for (final c in cols) clubs[c]!],
      answers: [
        for (final r in rows)
          for (final c in cols) links[r]![c]!.answerIds,
      ],
    );
    if (distinct && !gridIsVaried(grid)) return null;
    return avoid.contains(grid.id) ? null : grid;
  }

  List<String> poolAt(int fame) => [
        for (final id in links.keys)
          if (clubs[id]!.fame >= (_home.contains(clubs[id]!.country) ? fame - 1 : fame) && links[id]!.length >= 3) id,
      ];

  // First, with a category or two on one side (clubs on the other: categories
  // only link to clubs), sometimes as the rows, sometimes the columns.
  for (var fame = minFame; fame >= 1; fame--) {
    final pool = poolAt(fame);
    final cats = [
      for (final id in pool)
        if (isGridCategory(clubs[id]!) &&
            !usedCategories.contains(id) && // once a tournament ("Club teammate of Iniesta" twice)
            (_kindOf(id) != 'cup' || trophies.contains(id.split(':')[1])))
          id,
    ];
    final teams = [for (final id in pool) if (!isGridCategory(clubs[id]!)) id];
    if (cats.isEmpty || teams.length < 4) continue;
    for (var i = 0; i < attempts ~/ 5; i++) {
      final k = random.nextDouble() < _twoCategories ? 2 : 1;
      final side = <String>[];
      for (var j = 0; j < k; j++) {
        final c = category([
          for (final id in cats)
            if (side.every((s) => s != id && _kindOf(s) != _kindOf(id) && !_clash(s, id))) id,
        ]);
        if (c != null) side.add(c);
      }
      if (side.isEmpty) continue;
      // The rest of that side: clubs linked to the side's categories.
      final linked = teams.where((id) => side.every((c) => links[c]!.containsKey(id))).toList();
      for (var t = 0; t < _triesPerChoice; t++) {
        final more = pick(linked, 3 - side.length);
        if (more == null) break;
        final rows = [...side, ...more]..shuffle(random);
        final common = teams.where((id) => !rows.contains(id) && rows.every((r) => links[r]!.containsKey(id))).toList();
        if (common.length < 3) continue;
        final cols = pick(common, 3)!;
        final grid = random.nextBool() ? check(rows, cols) : check(cols, rows);
        if (grid != null) return grid;
      }
    }
  }

  // Nothing fair with a category (a narrow era choice, or data without any):
  // clubs only, as before.
  for (var fame = minFame; fame >= 1; fame--) {
    final pool = [for (final id in poolAt(fame)) if (!isGridCategory(clubs[id]!)) id];
    if (pool.length < 6) continue;
    for (var i = 0; i < attempts; i++) {
      final rows = pick(pool, 3)!;
      final common = pool.where((id) => !rows.contains(id) && rows.every((r) => links[r]!.containsKey(id))).toList();
      if (common.length < 3) continue;
      final grid = check(rows, pick(common, 3)!);
      if (grid != null) return grid;
    }
  }
  return null;
}

enum TttPhase { choosing, answering, finished }

enum TttSubmit { claimed, missed, alreadyUsed, ignored }

/// Turn-based Tic-Tac-Toe for 2+ teams: pick a square, name a player for
/// both clubs to claim it. Three in a row wins; each footballer once per grid.
class TicTacToeController extends ChangeNotifier {
  TicTacToeController({
    required this.grid,
    required this.teamCount,
    int startTeam = 0,
    this.answerSeconds = 20,
    this.chooseSeconds = 20,
    this.steals = 1,
    this.lives = 3,
    this.soloSeconds = 180,
  }) : currentTeam = startTeam % teamCount {
    if (_solo) secondsLeft = soloSeconds.toDouble();
    _startChoosing();
  }

  /// Solo (Pack the Box): one clock for the whole grid, Sporcle-style,
  /// instead of a clock per answer. Time left adds to the score.
  final int soloSeconds;

  final TicTacToeGrid grid;
  final int teamCount;
  final int answerSeconds;

  /// To pick a square, so nobody sits on their turn. Run out and the turn
  /// passes. Solo has no clock here.
  final int chooseSeconds;
  bool get _chooseClock => !_solo && chooseSeconds > 0;

  /// Steals each team gets a game: take a square the other side owns by
  /// naming a different player for it. A stolen square is locked. Not solo.
  final int steals;
  late final List<int> stealsLeft = List<int>.filled(teamCount, _solo ? 0 : steals);
  final List<bool> locked = List<bool>.filled(9, false);

  /// This turn's square is a steal.
  bool stealing = false;

  /// The last square claimed was taken off the other side (commentary).
  bool lastWasSteal = false;

  bool canSteal(int square) =>
      phase == TttPhase.choosing &&
      owner[square] != null &&
      owner[square] != currentTeam &&
      !locked[square] &&
      stealsLeft[currentTeam] > 0;

  /// Lives per team (and solo): a wrong answer, a time-out or a pass costs
  /// one. A team with none left sits out; when every team is out, it ends.
  final int lives;
  late final List<int> livesLeft = List<int>.filled(teamCount, lives);

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

  /// Bumps every time a new team's turn starts.
  int turnSerial = 0;
  List<int>? winningLine;
  int? winner;

  GameEvent? lastEvent;
  int eventSerial = 0;

  bool canChoose(int square) => phase == TttPhase.choosing && (owner[square] == null || canSteal(square));
  /// The clock running now: picking a square, or naming a player.
  int get phaseSeconds =>
      _solo ? soloSeconds : (phase == TttPhase.answering ? answerSeconds : (_chooseClock ? chooseSeconds : 0));
  bool get clockRunning =>
      _solo ? phase != TttPhase.finished : (phase == TttPhase.answering || (phase == TttPhase.choosing && _chooseClock));
  double get fractionLeft => phaseSeconds == 0 ? 0 : (secondsLeft / phaseSeconds).clamp(0.0, 1.0);
  int squaresOf(int team) => owner.where((o) => o == team).length;

  void choose(int square) {
    if (!canChoose(square)) return;
    stealing = owner[square] != null;
    selected = square;
    phase = TttPhase.answering;
    if (!_solo) secondsLeft = answerSeconds.toDouble();
    notifyListeners();
  }

  void advance(Duration elapsed) {
    if (!clockRunning) return;
    secondsLeft -= elapsed.inMicroseconds / 1e6;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      if (_solo) {
        // The grid's clock is up.
        _emit(GameEvent.timeUp);
        _finish();
        return;
      }
      if (phase == TttPhase.answering) {
        _miss(timeout: true);
      } else {
        // Too long picking: a life, and the turn goes.
        _emit(GameEvent.timeUp);
        livesLeft[currentTeam]--;
        _nextTurn();
      }
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
    missName = p.name;
    missSquare = sq;
    missSerial++;
    _miss();
    return TttSubmit.missed;
  }

  /// The last wrong name and its square: that square shakes red with the
  /// name crossed out, on every phone ([missSerial] changes each time).
  String? missName;
  int? missSquare;
  int missSerial = 0;

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
      livesLeft[currentTeam]--;
      _nextTurn();
    }
  }

  RoundResult result() => RoundResult(
        mode: GameModeId.ticTacToe,
        points: {
          for (var t = 0; t < teamCount; t++) t: squaresOf(t) + (winner == t ? lineBonus : 0),
        },
        solo: teamCount == 1 ? soloScore : null,
      );

  /// Pack the Box, out of 100: 7 a square (63), then for lives kept (up to
  /// 12) and time left (up to 25), both scaled by how much of the grid you
  /// filled. A full grid with no lives lost and no time used is 100; a full
  /// grid in a minute with a life lost is 63 + 8 + 17 = 88.
  int get soloScore {
    final filled = squaresOf(0) / 9;
    final lifeBonus = 4 * livesLeft[0].clamp(0, lives) * filled;
    final timeBonus = soloSeconds == 0 ? 0 : 25 * (secondsLeft / soloSeconds).clamp(0.0, 1.0) * filled;
    return (7 * squaresOf(0) + lifeBonus + timeBonus).round().clamp(0, 100);
  }

  bool get _solo => teamCount == 1;

  void _claim(int sq, String name) {
    lastWasSteal = stealing;
    if (stealing) {
      stealsLeft[currentTeam]--;
      locked[sq] = true;
    }
    owner[sq] = currentTeam;
    claimedWith[sq] = name;
    _emit(GameEvent.correct);
    // Solo fills the whole grid: a line means nothing there.
    for (final line in _solo ? const <List<int>>[] : lines) {
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
    // A steal that misses is used up.
    if (stealing) stealsLeft[currentTeam]--;
    _emit(timeout ? GameEvent.timeUp : GameEvent.wrong);
    livesLeft[currentTeam]--;
    _nextTurn();
  }

  void _nextTurn() {
    turns++;
    selected = null;
    stealing = false;
    if (livesLeft.every((l) => l <= 0)) {
      _finish();
      return;
    }
    // On to the next team with lives left (round again to this one if it's the last).
    do {
      currentTeam = (currentTeam + 1) % teamCount;
    } while (livesLeft[currentTeam] <= 0);
    phase = TttPhase.choosing;
    _startChoosing();
    turnSerial++;
    notifyListeners();
  }

  void _startChoosing() {
    if (_solo) return; // one clock for the whole grid
    secondsLeft = _chooseClock ? chooseSeconds.toDouble() : 0;
  }

  void _finish() {
    phase = TttPhase.finished;
    selected = null;
    stealing = false;
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
