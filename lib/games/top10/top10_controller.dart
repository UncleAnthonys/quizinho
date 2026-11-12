import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/top10.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../buzz_race_controller.dart' show GameEvent;

enum Top10Answer { found, alreadyFound, wrong, ignored }

/// Top 10: name the players on a record-book list.
///
/// Solo: name as many as you can; a name not on the list costs a life,
/// three gone and the rest come out; each one found is worth 10 (of 100).
///
/// Teams: one list, teams take turns naming one. Correct: 1 point, and the
/// turn moves on. Wrong, too slow or a pass costs that team a life (3 each);
/// a team with none sits out. It ends when all ten are found or every team
/// is out.
class Top10Controller extends ChangeNotifier {
  Top10Controller({
    required this.list,
    this.teamCount = 1,
    int startTeam = 0,
    this.lives = 3,
    this.answerSeconds = 20,
  }) : currentTeam = startTeam % teamCount {
    secondsLeft = _clock ? answerSeconds.toDouble() : 0;
  }

  final Top10List list;
  final int teamCount;
  final int lives;

  /// Per turn, teams only (solo has no clock).
  final int answerSeconds;

  bool get _solo => teamCount == 1;
  bool get _clock => !_solo && answerSeconds > 0;

  late final List<int> livesLeft = List<int>.filled(teamCount, lives);

  /// Solo's lives (the one team's).
  int get livesNow => livesLeft[0];

  int currentTeam;
  double secondsLeft = 0;

  /// Bumps each time the turn moves on (for joined phones).
  int turnSerial = 0;

  /// Places found, by index into [Top10List.entries], with the name given
  /// (a shared 10th place can be filled by any of its players) and who.
  final Map<int, String> found = {};
  final Map<int, int> foundBy = {};

  /// Wrong names, newest last ("✗ Gary Cahill").
  final List<String> misses = [];

  /// All found, everyone out, or (solo) given up: the rest are shown.
  bool finished = false;

  /// Index of the place just found (for a highlight), if any.
  int? lastFound;

  GameEvent? lastEvent;
  int eventSerial = 0;

  void _emit(GameEvent e) {
    lastEvent = e;
    eventSerial++;
  }

  bool get won => found.length == list.entries.length;
  double get fractionLeft => answerSeconds == 0 ? 0 : (secondsLeft / answerSeconds).clamp(0.0, 1.0);
  bool get clockRunning => _clock && !finished;

  void advance(Duration elapsed) {
    if (!clockRunning) return;
    secondsLeft -= elapsed.inMicroseconds / 1e6;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      misses.add('Time ran out');
      _loseLife(GameEvent.timeUp);
      return;
    }
    notifyListeners();
  }

  Top10Answer submit(Player p) {
    if (finished) return Top10Answer.ignored;
    final i = list.indexOf(p.id);
    if (i != null && found.containsKey(i)) return Top10Answer.alreadyFound;
    if (i != null) {
      found[i] = p.name;
      foundBy[i] = currentTeam;
      lastFound = i;
      if (won) {
        _emit(GameEvent.complete);
        finished = true;
        notifyListeners();
      } else {
        _emit(GameEvent.correct);
        _nextTurn();
      }
      return Top10Answer.found;
    }
    misses.add(p.name);
    _loseLife(GameEvent.wrong);
    return Top10Answer.wrong;
  }

  /// Teams: don't know one, so the turn goes (costs a life).
  void pass() {
    if (finished) return;
    misses.add('Passed');
    _loseLife(GameEvent.timeUp);
  }

  /// Solo: "I'm out", the rest come out.
  void giveUp() {
    if (finished) return;
    finished = true;
    lastFound = null;
    _emit(GameEvent.reveal);
    notifyListeners();
  }

  void _loseLife(GameEvent e) {
    livesLeft[currentTeam]--;
    lastFound = null;
    if (livesLeft.every((l) => l <= 0)) {
      finished = true;
      _emit(GameEvent.nobodyGotIt);
      notifyListeners();
      return;
    }
    _emit(e);
    _nextTurn();
  }

  void _nextTurn() {
    if (!_solo) {
      do {
        currentTeam = (currentTeam + 1) % teamCount;
      } while (livesLeft[currentTeam] <= 0);
      turnSerial++;
    }
    secondsLeft = _clock ? answerSeconds.toDouble() : 0;
    notifyListeners();
  }

  int foundByTeam(int team) => foundBy.values.where((t) => t == team).length;

  int get score => found.length * 10;

  RoundResult result() => RoundResult(
        mode: GameModeId.top10,
        points: {for (var t = 0; t < teamCount; t++) t: foundByTeam(t)},
        solo: _solo ? score : null,
      );
}
