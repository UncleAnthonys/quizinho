import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';

enum PtPhase { answering, reveal, finished }

enum PtEvent { scored, pointless, wrong, duplicate, timeUp }

/// One answer given in the round.
class PtAnswer {
  const PtAnswer({required this.team, required this.label, required this.score, this.valid = true, this.id});
  final int team;

  /// What was said ("Vladimír Šmicer", or "Time up").
  final String label;
  final int score;

  /// False for wrong answers, timeouts and give-ups (they score the max).
  final bool valid;
  final String? id;

  bool get pointless => valid && score == 0;
}

/// Pointless: the lower your score, the better. Teams take turns — A, B, A,
/// B — conferring before each answer. A right answer scores how many of 100
/// people would have said it (0 = pointless); wrong or out of time scores 100.
/// Lowest total takes the round.
class PointlessController extends ChangeNotifier {
  PointlessController({
    required this.category,
    required this.teamCount,
    this.startTeam = 0,
    this.answersPerTeam = 2,
    this.answerSeconds = 30,
    this.revealSeconds = 3.2,
  }) : assert(teamCount >= 2);

  final BiddingCategory category;
  final int teamCount;
  final int startTeam;
  final int answersPerTeam;
  final int answerSeconds;
  final double revealSeconds;

  static const int miss = 100;
  static const int roomVote = 50;
  static const int winPoints = 3;
  static const int pointlessBonus = 1;

  PtPhase phase = PtPhase.answering;
  int turn = 0;
  double secondsLeft = 0;
  final List<PtAnswer> answers = [];

  PtEvent? lastEvent;
  int eventSerial = 0;

  double _revealLeft = 0;

  int get totalTurns => teamCount * answersPerTeam;
  int get currentTeam => (startTeam + turn) % teamCount;
  double get fractionLeft => answerSeconds == 0 ? 0 : (secondsLeft / answerSeconds).clamp(0.0, 1.0);
  PtAnswer? get lastAnswer => answers.isEmpty ? null : answers.last;

  /// Which go this is for the current team (1-based).
  int get goNumber => turn ~/ teamCount + 1;

  int totalOf(int team) => answers.where((a) => a.team == team).fold(0, (sum, a) => sum + a.score);
  List<PtAnswer> answersOf(int team) => [for (final a in answers) if (a.team == team) a];

  void start() {
    phase = PtPhase.answering;
    secondsLeft = answerSeconds.toDouble();
    notifyListeners();
  }

  void advance(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6;
    if (phase == PtPhase.answering) {
      secondsLeft -= dt;
      if (secondsLeft <= 0) {
        secondsLeft = 0;
        _record(PtAnswer(team: currentTeam, label: 'Time up', score: miss, valid: false), PtEvent.timeUp);
        return;
      }
      notifyListeners();
    } else if (phase == PtPhase.reveal) {
      _revealLeft -= dt;
      if (_revealLeft <= 0) next();
    }
  }

  /// Player (or club) named. Saying one already given doesn't cost the turn.
  void submit(Player p) {
    if (phase != PtPhase.answering) return;
    if (answers.any((a) => a.id == p.id)) {
      _emit(PtEvent.duplicate);
      notifyListeners();
      return;
    }
    final score = category.answerIds.contains(p.id) ? (category.scores[p.id] ?? roomVote) : null;
    if (score == null) {
      _record(PtAnswer(team: currentTeam, label: p.name, score: miss, valid: false, id: p.id), PtEvent.wrong);
    } else {
      _record(PtAnswer(team: currentTeam, label: p.name, score: score, id: p.id),
          score == 0 ? PtEvent.pointless : PtEvent.scored);
    }
  }

  /// A right answer missing from our data, allowed by the room: middling score.
  void submitDisputed(String typed) {
    if (phase != PtPhase.answering) return;
    _record(PtAnswer(team: currentTeam, label: '$typed (room vote)', score: roomVote), PtEvent.scored);
  }

  /// Can't think of one: takes the full 100.
  void giveUp() {
    if (phase != PtPhase.answering) return;
    _record(PtAnswer(team: currentTeam, label: 'Gave up', score: miss, valid: false), PtEvent.wrong);
  }

  /// Skip the rest of the reveal.
  void next() {
    if (phase != PtPhase.reveal) return;
    turn++;
    if (turn >= totalTurns) {
      phase = PtPhase.finished;
    } else {
      phase = PtPhase.answering;
      secondsLeft = answerSeconds.toDouble();
    }
    notifyListeners();
  }

  /// Teams with the lowest total (all of them, if tied).
  Set<int> get winners {
    final totals = {for (var t = 0; t < teamCount; t++) t: totalOf(t)};
    final best = totals.values.reduce((a, b) => a < b ? a : b);
    return {for (final e in totals.entries) if (e.value == best) e.key};
  }

  RoundResult result() {
    final w = winners;
    return RoundResult(
      mode: GameModeId.pointless,
      points: {
        for (var t = 0; t < teamCount; t++)
          t: (w.contains(t) ? winPoints : 0) + answersOf(t).where((a) => a.pointless).length * pointlessBonus,
      },
    );
  }

  void _record(PtAnswer a, PtEvent e) {
    answers.add(a);
    phase = PtPhase.reveal;
    _revealLeft = revealSeconds;
    _emit(e);
    notifyListeners();
  }

  void _emit(PtEvent e) {
    lastEvent = e;
    eventSerial++;
  }
}
