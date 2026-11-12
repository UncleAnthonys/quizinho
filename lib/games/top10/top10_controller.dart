import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/top10.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../buzz_race_controller.dart' show GameEvent;

enum Top10Answer { found, alreadyFound, wrong, ignored }

/// Top 10, played alone: name as many of the ten as you can. A name that
/// isn't on the list costs a life; three gone and the rest come out. Each
/// one found is worth 10 (out of 100).
class Top10Controller extends ChangeNotifier {
  Top10Controller({required this.list, this.lives = 3});

  final Top10List list;
  int lives;

  /// Places found, by index into [Top10List.entries], with the name given
  /// (a shared 10th place can be filled by any of its players).
  final Map<int, String> found = {};

  /// Wrong names, newest last ("✗ Gary Cahill").
  final List<String> misses = [];

  /// Gave up or out of lives: the rest are shown.
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

  Top10Answer submit(Player p) {
    if (finished) return Top10Answer.ignored;
    final i = list.indexOf(p.id);
    if (i != null && found.containsKey(i)) return Top10Answer.alreadyFound;
    if (i != null) {
      found[i] = p.name;
      lastFound = i;
      _emit(won ? GameEvent.complete : GameEvent.correct);
      if (won) finished = true;
      notifyListeners();
      return Top10Answer.found;
    }
    misses.add(p.name);
    lives--;
    lastFound = null;
    if (lives <= 0) {
      finished = true;
      _emit(GameEvent.nobodyGotIt);
    } else {
      _emit(GameEvent.wrong);
    }
    notifyListeners();
    return Top10Answer.wrong;
  }

  /// "I'm out": the rest come out.
  void giveUp() {
    if (finished) return;
    finished = true;
    lastFound = null;
    _emit(GameEvent.reveal);
    notifyListeners();
  }

  int get score => found.length * 10;

  RoundResult result() => RoundResult(mode: GameModeId.top10, points: {0: found.length}, solo: score);
}
