import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../buzz_race_controller.dart' show GameEvent;
import 'penalty_kick.dart';

enum ShootoutPhase {
  /// "Pass to…": the next taker gets ready (the clock waits).
  handover,

  /// The question's up and the clock's running.
  kicking,

  /// Scored or saved: the answer's shown.
  result,

  /// Someone's won it.
  finished,
}

/// A penalty shootout for a drawn match: the teams level at the top take
/// it in turns, five kicks each, then sudden death. It ends the moment one
/// team can't be caught.
class ShootoutController extends ChangeNotifier {
  ShootoutController({required this.teams, this.kickSeconds = 15, this.kicksEach = 5})
      : assert(teams.length >= 2),
        alive = [...teams],
        kicks = {for (final t in teams) t: <bool>[]};

  /// The teams in the shootout (tournament indices), in kicking order.
  final List<int> teams;
  final int kickSeconds;
  final int kicksEach;

  /// Still in it: in sudden death, a team that falls behind after a round is out.
  final List<int> alive;

  /// Each team's kicks so far: true = scored.
  final Map<int, List<bool>> kicks;

  ShootoutPhase phase = ShootoutPhase.handover;
  int _turn = 0;
  PenaltyKick? kick;
  double secondsLeft = 0;

  /// The last kick's taker and whether it went in.
  int? lastTeam;
  bool? lastScored;

  /// The winner, once [phase] is finished.
  int? winner;

  GameEvent? lastEvent;
  int eventSerial = 0;

  int get taker => alive[_turn % alive.length];

  /// The first kick of a round (each team in it then takes one).
  bool get roundStart => _turn % alive.length == 0;
  int goals(int team) => kicks[team]!.where((k) => k).length;
  bool get suddenDeath => kicks[taker]!.length >= kicksEach;

  /// Which kick this is for the taker (1-based), for "KICK 3 OF 5".
  int get kickNumber => kicks[taker]!.length + 1;

  double get fractionLeft => kickSeconds == 0 ? 0 : (secondsLeft / kickSeconds).clamp(0.0, 1.0);

  /// The taker's ready and [k] is their question: the clock starts.
  void start(PenaltyKick k) {
    if (phase != ShootoutPhase.handover) return;
    kick = k;
    secondsLeft = kickSeconds.toDouble();
    phase = ShootoutPhase.kicking;
    notifyListeners();
  }

  void advance(Duration elapsed) {
    if (phase != ShootoutPhase.kicking) return;
    secondsLeft -= elapsed.inMicroseconds / 1e6;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      _take(false, timeUp: true);
      return;
    }
    notifyListeners();
  }

  /// An answer: a player (or club) id. Right = scored.
  void submit(String id) {
    if (phase != ShootoutPhase.kicking) return;
    _take(kick!.answers.contains(id));
  }

  /// Over/under: the button tapped.
  void choose(int option) {
    if (phase != ShootoutPhase.kicking || !kick!.tap) return;
    _take(option == kick!.correctOption);
  }

  /// No idea: a miss.
  void pass() {
    if (phase != ShootoutPhase.kicking) return;
    _take(false);
  }

  bool isRightAnswer(Player p) => kick?.answers.contains(p.id) ?? false;

  void _take(bool scored, {bool timeUp = false}) {
    final team = taker;
    kicks[team]!.add(scored);
    lastTeam = team;
    lastScored = scored;
    phase = ShootoutPhase.result;
    _emit(scored ? GameEvent.correct : (timeUp ? GameEvent.timeUp : GameEvent.wrong));
    notifyListeners();
  }

  /// After the result: the next taker, or the end.
  void next() {
    if (phase != ShootoutPhase.result) return;
    final endOfRound = _turn % alive.length == alive.length - 1;
    _turn++;
    final w = _decided(endOfRound: endOfRound);
    if (w != null) {
      winner = w;
      phase = ShootoutPhase.finished;
      _emit(GameEvent.complete);
    } else {
      kick = null;
      phase = ShootoutPhase.handover;
    }
    notifyListeners();
  }

  /// The winner if it's settled, else null. In the first five each: as soon
  /// as one team is ahead of everyone's best possible. After that, at the end
  /// of each round: whoever's ahead; the rest drop out, the level ones go on.
  int? _decided({required bool endOfRound}) {
    final inRegulation = kicks.values.any((k) => k.length < kicksEach);
    if (inRegulation) {
      for (final t in alive) {
        final caught = alive.any((o) => o != t && goals(o) + (kicksEach - kicks[o]!.length).clamp(0, kicksEach) >= goals(t));
        if (!caught) return t;
      }
      return null;
    }
    if (!endOfRound) return null;
    final best = alive.map(goals).reduce((a, b) => a > b ? a : b);
    final top = alive.where((t) => goals(t) == best).toList();
    if (top.length == 1) return top.single;
    // Sudden death: anyone behind is out; the rest go again.
    alive
      ..clear()
      ..addAll(top);
    _turn = 0;
    return null;
  }

  void _emit(GameEvent e) {
    lastEvent = e;
    eventSerial++;
  }
}
