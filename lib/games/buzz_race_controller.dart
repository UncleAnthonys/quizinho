import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../domain/game_mode.dart';
import '../domain/tournament.dart';

enum BuzzPhase { open, answering, resolved, finished }

/// Things the UI reacts to with sound, haptics and commentary.
enum GameEvent { buzz, correct, steal, deepCut, wrong, timeUp, nobodyGotIt, reveal, explode, eliminated, complete }

class BuzzOutcome {
  const BuzzOutcome({this.team, this.player, this.points = 0, this.bonus = false, this.disputed = false});
  final int? team;
  final Player? player;
  final int points;
  final bool bonus;

  /// Accepted by a room vote rather than by the database.
  final bool disputed;
  bool get scored => team != null && points > 0;
}

/// Shared rules for buzzer games: first to buzz answers, a wrong answer locks
/// that team out and lets the others steal, the question ends when someone
/// scores, everyone is locked out, or time runs out.
///
/// Time is driven externally through [advance] so tests are deterministic.
abstract class BuzzRaceController<Q> extends ChangeNotifier {
  BuzzRaceController({
    required this.mode,
    required this.teamCount,
    required this.questions,
    required this.answerSeconds,
  }) : assert(questions.isNotEmpty) {
    roundPoints.addAll({for (var i = 0; i < teamCount; i++) i: 0});
    startQuestion();
  }

  final GameModeId mode;
  final int teamCount;
  final List<Q> questions;
  final int answerSeconds;

  final Map<int, int> roundPoints = {};
  int questionIndex = 0;
  BuzzPhase phase = BuzzPhase.open;
  int? answeringTeam;
  final Set<int> lockedOut = {};

  /// Countdown for the current phase (open or answering).
  double secondsLeft = 0;
  double phaseSeconds = 1;
  (double, double) _pausedOpen = (0, 1);
  BuzzOutcome? outcome;

  GameEvent? lastEvent;
  int eventSerial = 0;

  Q get current => questions[questionIndex];
  bool get isLastQuestion => questionIndex == questions.length - 1;
  bool canBuzz(int team) => phase == BuzzPhase.open && !lockedOut.contains(team);

  // ---- hooks for each game -------------------------------------------------

  /// Called whenever a new question begins. Must set the open timer.
  @protected
  void onQuestionStart();

  /// Ticks while nobody is answering. Return true if the question timed out.
  @protected
  bool tickOpen(double dt);

  /// Called after a wrong answer when other teams can still steal.
  @protected
  void onReopen();

  @protected
  bool isCorrect(Player p);

  /// Points for a correct answer right now, and whether it earned a bonus.
  @protected
  (int, bool) pointsFor(Player p);

  // ---- shared flow ---------------------------------------------------------

  @protected
  void startQuestion() {
    phase = BuzzPhase.open;
    answeringTeam = null;
    lockedOut.clear();
    outcome = null;
    onQuestionStart();
  }

  @protected
  void setTimer(double seconds) {
    secondsLeft = seconds;
    phaseSeconds = max(seconds, 0.001);
  }

  @protected
  void emit(GameEvent e) {
    lastEvent = e;
    eventSerial++;
  }

  void advance(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6;
    switch (phase) {
      case BuzzPhase.open:
        if (tickOpen(dt)) {
          _resolve(const BuzzOutcome(), GameEvent.timeUp);
          return;
        }
      case BuzzPhase.answering:
        secondsLeft -= dt;
        if (secondsLeft <= 0) {
          secondsLeft = 0;
          _wrong(timeout: true);
          return;
        }
      case BuzzPhase.resolved:
      case BuzzPhase.finished:
        return;
    }
    notifyListeners();
  }

  void buzz(int team) {
    if (!canBuzz(team)) return;
    _pausedOpen = (secondsLeft, phaseSeconds);
    answeringTeam = team;
    phase = BuzzPhase.answering;
    setTimer(answerSeconds.toDouble());
    emit(GameEvent.buzz);
    notifyListeners();
  }

  /// The answering team picked [player] from the list.
  void submit(Player player) {
    final team = answeringTeam;
    if (phase != BuzzPhase.answering || team == null) return;
    if (isCorrect(player)) {
      final (pts, bonus) = pointsFor(player);
      final isSteal = lockedOut.isNotEmpty;
      _award(BuzzOutcome(team: team, player: player, points: pts, bonus: bonus),
          bonus ? GameEvent.deepCut : (isSteal ? GameEvent.steal : GameEvent.correct));
    } else {
      _wrong();
    }
  }

  /// The team named someone the database doesn't know; the room voted.
  void submitDisputed({required bool allowed}) {
    final team = answeringTeam;
    if (phase != BuzzPhase.answering || team == null) return;
    if (allowed) {
      final (pts, _) = pointsFor(const Player(id: '_disputed', name: '', fame: 5));
      _award(BuzzOutcome(team: team, points: pts, disputed: true), GameEvent.correct);
    } else {
      _wrong();
    }
  }

  /// Answering team gives up — same as a wrong answer.
  void pass() {
    if (phase == BuzzPhase.answering) _wrong();
  }

  /// Skip a question nobody can get (no penalty).
  void giveUp() {
    if (phase == BuzzPhase.open || phase == BuzzPhase.answering) {
      _resolve(const BuzzOutcome(), GameEvent.nobodyGotIt);
    }
  }

  void next() {
    if (phase != BuzzPhase.resolved) return;
    if (isLastQuestion) {
      phase = BuzzPhase.finished;
    } else {
      questionIndex++;
      startQuestion();
    }
    notifyListeners();
  }

  RoundResult result({String headline = ''}) =>
      RoundResult(mode: mode, points: Map.of(roundPoints), headline: headline);

  void _award(BuzzOutcome o, GameEvent e) {
    roundPoints[o.team!] = (roundPoints[o.team!] ?? 0) + o.points;
    _resolve(o, e);
  }

  void _wrong({bool timeout = false}) {
    final team = answeringTeam;
    if (team != null) lockedOut.add(team);
    answeringTeam = null;
    if (lockedOut.length >= teamCount) {
      _resolve(const BuzzOutcome(), GameEvent.nobodyGotIt);
      return;
    }
    phase = BuzzPhase.open;
    // resume the open clock where it was paused at the buzz
    secondsLeft = _pausedOpen.$1;
    phaseSeconds = _pausedOpen.$2;
    onReopen();
    emit(timeout ? GameEvent.timeUp : GameEvent.wrong);
    notifyListeners();
  }

  void _resolve(BuzzOutcome o, GameEvent e) {
    outcome = o;
    phase = BuzzPhase.resolved;
    answeringTeam = null;
    emit(e);
    notifyListeners();
  }
}
