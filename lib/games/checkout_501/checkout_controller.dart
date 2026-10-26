import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';

enum CoPhase { answering, reveal, finished }

/// What one "dart" did.
enum CoOutcome { scored, checkout, bust, overshoot, wrong, timeUp }

enum CoEvent { thrown, duplicate, noStats }

class CoThrow {
  const CoThrow({
    required this.team,
    required this.label,
    required this.outcome,
    this.apps,
    this.goals,
    this.before = 0,
    this.after = 0,
  });
  final int team;
  final String label;
  final CoOutcome outcome;
  final int? apps;
  final int? goals;
  final int before;
  final int after;

  int get value => (apps ?? 0) + (goals ?? 0);
}

/// Football 501 for teams. Everyone starts on 501. Teams take turns naming a
/// player; their league apps + goals for the club come off the score.
/// Over 180 is a bust (score stays). Finish between 0 and −10 to check out —
/// further below is a bust. A player named by anyone is gone for everyone.
/// When a team checks out, the rest of that lap still throws: everyone who
/// checks out on the same dart is compared, closest to zero wins.
/// If nobody checks out in [maxTurns] each, closest wins.
class CheckoutController extends ChangeNotifier {
  CheckoutController({
    required this.category,
    required this.teamCount,
    this.startTeam = 0,
    this.maxTurns = 10,
    this.answerSeconds = 30,
    this.revealSeconds = 3.0,
  }) : assert(teamCount >= 2);

  final CheckoutCategory category;
  final int teamCount;
  final int startTeam;
  final int maxTurns;
  final int answerSeconds;
  final double revealSeconds;

  static const int start = 501;
  static const int maxDart = 180;
  static const int checkoutWindow = 10; // 0 to −10 counts
  static const int winPoints = 3;

  late final List<int> remaining = List.filled(teamCount, start);
  final List<CoThrow> throws = [];
  final Set<String> used = {};

  CoPhase phase = CoPhase.answering;
  int turn = 0;
  double secondsLeft = 0;
  final Set<int> checkedOut = {};

  CoEvent? lastEvent;
  int eventSerial = 0;
  double _revealLeft = 0;

  int get currentTeam => (startTeam + turn) % teamCount;
  int get dartNumber => turn ~/ teamCount + 1;
  double get fractionLeft => answerSeconds == 0 ? 0 : (secondsLeft / answerSeconds).clamp(0.0, 1.0);
  CoThrow? get lastThrow => throws.isEmpty ? null : throws.last;
  List<CoThrow> throwsOf(int team) => [for (final t in throws) if (t.team == team) t];

  void begin() {
    phase = CoPhase.answering;
    secondsLeft = answerSeconds.toDouble();
    notifyListeners();
  }

  void advance(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6;
    if (phase == CoPhase.answering) {
      secondsLeft -= dt;
      if (secondsLeft <= 0) {
        secondsLeft = 0;
        _record(CoThrow(team: currentTeam, label: 'Time up', outcome: CoOutcome.timeUp,
            before: remaining[currentTeam], after: remaining[currentTeam]));
        return;
      }
      notifyListeners();
    } else if (phase == CoPhase.reveal) {
      _revealLeft -= dt;
      if (_revealLeft <= 0) next();
    }
  }

  void submit(Player p) {
    if (phase != CoPhase.answering) return;
    if (used.contains(p.id)) {
      _emit(CoEvent.duplicate); // already gone — pick another, no turn lost
      notifyListeners();
      return;
    }
    if (category.noStats.contains(p.id)) {
      _emit(CoEvent.noStats); // played there but no numbers — pick another
      notifyListeners();
      return;
    }
    final team = currentTeam;
    final before = remaining[team];
    final v = category.values[p.id];
    if (v == null) {
      _record(CoThrow(team: team, label: p.name, outcome: CoOutcome.wrong, before: before, after: before));
      return;
    }
    used.add(p.id);
    final (apps, goals) = v;
    final value = apps + goals;
    final after = before - value;
    final CoOutcome outcome;
    if (value > maxDart) {
      outcome = CoOutcome.bust;
    } else if (after < -checkoutWindow) {
      outcome = CoOutcome.overshoot;
    } else if (after <= 0) {
      outcome = CoOutcome.checkout;
    } else {
      outcome = CoOutcome.scored;
    }
    final counts = outcome == CoOutcome.scored || outcome == CoOutcome.checkout;
    if (counts) remaining[team] = after;
    if (outcome == CoOutcome.checkout) checkedOut.add(team);
    _record(CoThrow(
      team: team,
      label: p.name,
      outcome: outcome,
      apps: apps,
      goals: goals,
      before: before,
      after: counts ? after : before,
    ));
  }

  /// Can't think of one: the dart misses.
  void pass() {
    if (phase != CoPhase.answering) return;
    final b = remaining[currentTeam];
    _record(CoThrow(team: currentTeam, label: 'Passed', outcome: CoOutcome.wrong, before: b, after: b));
  }

  void next() {
    if (phase != CoPhase.reveal) return;
    turn++;
    // A checkout ends the game at the end of that lap, so every team gets
    // the same number of darts.
    final lapDone = turn % teamCount == 0;
    if ((checkedOut.isNotEmpty && lapDone) || turn >= maxTurns * teamCount) {
      phase = CoPhase.finished;
    } else {
      phase = CoPhase.answering;
      secondsLeft = answerSeconds.toDouble();
    }
    notifyListeners();
  }

  /// The team that checked out — or, if nobody did, the closest to zero.
  Set<int> get winners {
    if (checkedOut.isNotEmpty) {
      final best = checkedOut.map((t) => remaining[t]).reduce((a, b) => a > b ? a : b);
      return {for (final t in checkedOut) if (remaining[t] == best) t};
    }
    final best = remaining.reduce((a, b) => a < b ? a : b);
    return {for (var t = 0; t < teamCount; t++) if (remaining[t] == best) t};
  }

  RoundResult result() {
    final w = winners;
    return RoundResult(
      mode: GameModeId.checkout501,
      points: {for (var t = 0; t < teamCount; t++) t: w.contains(t) ? winPoints : 0},
    );
  }

  void _record(CoThrow t) {
    throws.add(t);
    phase = CoPhase.reveal;
    _revealLeft = revealSeconds;
    _emit(CoEvent.thrown);
    notifyListeners();
  }

  void _emit(CoEvent e) {
    lastEvent = e;
    eventSerial++;
  }
}
