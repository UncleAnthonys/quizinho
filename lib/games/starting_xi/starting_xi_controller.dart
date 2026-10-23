import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../buzz_race_controller.dart' show GameEvent;

enum BombPhase {
  /// "Pass the phone to Team B" — timer paused until they tap.
  handover,
  ticking,

  /// The bomb just went off; waiting for a tap to continue.
  exploded,
  finished,
}

enum SubmitResult { correct, wrong, alreadyNamed, ignored }

/// Starting XI Bomb: teams take turns naming a starter before the timer
/// runs out. Wrong or slow = lose a life. Ends when the XI is complete or
/// only one team survives.
class StartingXiController extends ChangeNotifier {
  StartingXiController({
    required this.match,
    required this.teamCount,
    this.turnSeconds = 20,
    int lives = 3,
    int startTeam = 0,
  })  : startingLives = lives,
        currentTeam = startTeam % teamCount {
    for (var t = 0; t < teamCount; t++) {
      livesLeft[t] = lives;
      correctByTeam[t] = 0;
    }
  }

  final HistoricMatch match;
  final int teamCount;
  final int turnSeconds;
  final int startingLives;

  static const int survivorBonus = 3;

  final Map<int, int> livesLeft = {};
  final Map<int, int> correctByTeam = {};

  /// player ID → team that named them
  final Map<String, int> namedBy = {};

  int currentTeam;
  BombPhase phase = BombPhase.handover;
  double secondsLeft = 0;

  /// Team that just lost a life (for the explosion screen).
  int? lastExploded;
  List<int> bonusTeams = const [];

  GameEvent? lastEvent;
  int eventSerial = 0;

  bool get isComplete => namedBy.length >= match.lineup.length;
  List<int> get aliveTeams => [for (var t = 0; t < teamCount; t++) if (livesLeft[t]! > 0) t];
  double get fractionLeft => turnSeconds == 0 ? 0 : (secondsLeft / turnSeconds).clamp(0.0, 1.0);

  void startTurn() {
    if (phase != BombPhase.handover) return;
    phase = BombPhase.ticking;
    secondsLeft = turnSeconds.toDouble();
    notifyListeners();
  }

  void advance(Duration elapsed) {
    if (phase != BombPhase.ticking) return;
    secondsLeft -= elapsed.inMicroseconds / 1e6;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      _explode();
      return;
    }
    notifyListeners();
  }

  SubmitResult submit(Player p) {
    if (phase != BombPhase.ticking) return SubmitResult.ignored;
    if (namedBy.containsKey(p.id)) return SubmitResult.alreadyNamed;
    final inXi = match.lineup.any((s) => s.playerId == p.id);
    if (!inXi) {
      _explode();
      return SubmitResult.wrong;
    }
    namedBy[p.id] = currentTeam;
    correctByTeam[currentTeam] = correctByTeam[currentTeam]! + 1;
    _emit(GameEvent.correct);
    if (isComplete) {
      _finish();
    } else {
      _advanceTeam();
      phase = BombPhase.handover;
      notifyListeners();
    }
    return SubmitResult.correct;
  }

  /// Team can't think of anyone — take the hit now rather than wait.
  void pass() {
    if (phase == BombPhase.ticking) _explode();
  }

  void continueAfterExplosion() {
    if (phase != BombPhase.exploded) return;
    if (aliveTeams.length <= 1) {
      _finish();
      return;
    }
    _advanceTeam();
    phase = BombPhase.handover;
    notifyListeners();
  }

  RoundResult result() {
    final pts = <int, int>{};
    for (var t = 0; t < teamCount; t++) {
      pts[t] = correctByTeam[t]! + (bonusTeams.contains(t) ? survivorBonus : 0);
    }
    return RoundResult(mode: GameModeId.startingXi, points: pts);
  }

  void _explode() {
    final team = currentTeam;
    livesLeft[team] = livesLeft[team]! - 1;
    lastExploded = team;
    phase = BombPhase.exploded;
    _emit(livesLeft[team]! <= 0 ? GameEvent.eliminated : GameEvent.explode);
    notifyListeners();
  }

  void _advanceTeam() {
    for (var step = 1; step <= teamCount; step++) {
      final t = (currentTeam + step) % teamCount;
      if (livesLeft[t]! > 0) {
        currentTeam = t;
        return;
      }
    }
  }

  void _finish() {
    phase = BombPhase.finished;
    final alive = aliveTeams;
    if (!isComplete && alive.length == 1) {
      bonusTeams = alive;
    } else {
      // XI completed (or everyone out): most players named wins the bonus.
      final best = correctByTeam.values.fold<int>(0, (a, b) => a > b ? a : b);
      bonusTeams = best == 0 ? const [] : [for (final e in correctByTeam.entries) if (e.value == best) e.key];
    }
    _emit(GameEvent.complete);
    notifyListeners();
  }

  void _emit(GameEvent e) {
    lastEvent = e;
    eventSerial++;
  }
}
