import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/teasers.dart';
import '../../domain/tournament.dart';
import '../buzz_race_controller.dart';

/// Plays the Half-Time Teaser. A team buzzes, then has [answerSeconds] to
/// name someone. Right: 5 at half-time, 3 between games. Wrong: that team has
/// had its guess. Once every team has guessed wrong, the answers come out.
///
/// At half-time there's a [halfTimeSeconds] clock; when it runs out the
/// teaser stays open (for 3) between games. Between games there's no clock.
/// The state lives in [Tournament.teaser], so it carries across games and
/// survives the app closing.
class TeaserController extends ChangeNotifier implements BuzzTarget {
  TeaserController({
    required this.tournament,
    required this.teaser,
    required this.halfTime,
    this.halfTimeSeconds = 90,
    this.answerSeconds = 15,
  }) {
    if (halfTime) _setTimer(halfTimeSeconds.toDouble());
    if (!state.isOpen) phase = BuzzPhase.resolved;
  }

  final Tournament tournament;
  final Teaser teaser;
  final bool halfTime;
  final int halfTimeSeconds;
  final int answerSeconds;

  TeaserState get state => tournament.teaser!;
  int get teamCount => tournament.teamCount;

  /// Points for getting it now.
  int get worth => halfTime && !clockDone ? 5 : 3;

  @override
  BuzzPhase phase = BuzzPhase.open;
  @override
  int? answeringTeam;
  @override
  BuzzOutcome? outcome;
  @override
  double secondsLeft = 0;
  @override
  double phaseSeconds = 1;
  (double, double) _paused = (0, 1);

  /// Half-time: the clock's run out. No more buzzing on this screen; it's
  /// still there to be had between games, for 3.
  bool clockDone = false;

  /// The half-time clock, held while someone answers.
  double get halfTimeLeft => phase == BuzzPhase.answering ? _paused.$1 : secondsLeft;

  /// The last wrong answer and who gave it — the host can overrule it.
  int? lastWrongTeam;
  String? lastMiss;

  /// An answer that fits on paper but we couldn't confirm: the host's call.
  Player? hostCall;

  GameEvent? lastEvent;
  int eventSerial = 0;

  void _emit(GameEvent e) {
    lastEvent = e;
    eventSerial++;
  }

  @override
  String get tag => 'T${state.lockedOut.length}';
  @override
  String get progress => '';
  @override
  String get modeName => 'teaser';

  Set<int> get lockedOut => state.lockedOut;

  @override
  bool canBuzz(int team) => phase == BuzzPhase.open && state.isOpen && !clockDone && !state.lockedOut.contains(team);

  bool isRightAnswer(Player p) => teaser.isAnswer(p.id) || teaser.unsure.contains(p.id);

  void _setTimer(double s) {
    secondsLeft = s;
    phaseSeconds = s <= 0 ? 1 : s;
  }

  void advance(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6;
    switch (phase) {
      case BuzzPhase.open:
        if (!halfTime || clockDone) return;
        secondsLeft -= dt;
        if (secondsLeft <= 0) {
          secondsLeft = 0;
          clockDone = true;
          _emit(GameEvent.timeUp);
        }
      case BuzzPhase.answering:
        if (hostCall != null) return;
        secondsLeft -= dt;
        if (secondsLeft <= 0) {
          secondsLeft = 0;
          lastMiss = 'Time ran out';
          _wrong(timeout: true);
          return;
        }
      case BuzzPhase.resolved:
      case BuzzPhase.finished:
        return;
    }
    notifyListeners();
  }

  @override
  void buzz(int team) {
    if (!canBuzz(team)) return;
    _paused = (secondsLeft, phaseSeconds);
    answeringTeam = team;
    lastWrongTeam = null;
    lastMiss = null;
    phase = BuzzPhase.answering;
    _setTimer(answerSeconds.toDouble());
    _emit(GameEvent.buzz);
    notifyListeners();
  }

  @override
  void submit(Player player) {
    final team = answeringTeam;
    if (phase != BuzzPhase.answering || team == null || hostCall != null) return;
    if (teaser.isAnswer(player.id)) {
      _award(team, player.name, player);
    } else if (teaser.unsure.contains(player.id)) {
      hostCall = player;
      notifyListeners();
    } else {
      lastMiss = player.name;
      _wrong();
    }
  }

  /// The host's call on an answer we couldn't confirm.
  void decide({required bool counts}) {
    final p = hostCall;
    if (p == null || answeringTeam == null) return;
    hostCall = null;
    if (counts) {
      _award(answeringTeam!, p.name, p);
    } else {
      lastMiss = p.name;
      _wrong();
    }
  }

  /// A name that isn't in our database; the room voted.
  void submitDisputed({required bool allowed, String typed = ''}) {
    final team = answeringTeam;
    if (phase != BuzzPhase.answering || team == null) return;
    if (allowed) {
      _award(team, typed, null);
    } else {
      lastMiss = typed.isEmpty ? 'Not accepted' : typed;
      _wrong();
    }
  }

  @override
  void pass() {
    if (phase != BuzzPhase.answering) return;
    lastMiss = 'Passed';
    _wrong(timeout: true);
  }

  /// The last wrong answer was right after all (a gap in our data): the host
  /// overrules and it counts.
  bool get canOverrule =>
      lastWrongTeam != null &&
      lastMiss != null &&
      (phase == BuzzPhase.open || (phase == BuzzPhase.resolved && state.status == TeaserStatus.revealed));

  void overrule() {
    final team = lastWrongTeam;
    final answer = lastMiss;
    if (!canOverrule || team == null || answer == null) return;
    state.lockedOut.remove(team);
    if (state.status == TeaserStatus.revealed) state.status = TeaserStatus.open;
    _award(team, answer, null);
  }

  /// Full time with nobody having it: out come the answers.
  void reveal() {
    if (!state.isOpen) return;
    state.status = TeaserStatus.revealed;
    phase = BuzzPhase.resolved;
    answeringTeam = null;
    hostCall = null;
    outcome = const BuzzOutcome();
    _emit(GameEvent.nobodyGotIt);
    notifyListeners();
  }

  void _award(int team, String answer, Player? player) {
    final pts = worth;
    tournament.awardTeaser(team, pts, answer);
    outcome = BuzzOutcome(team: team, player: player, points: pts);
    phase = BuzzPhase.resolved;
    answeringTeam = null;
    lastWrongTeam = null;
    _emit(GameEvent.correct);
    notifyListeners();
  }

  void _wrong({bool timeout = false}) {
    final team = answeringTeam;
    if (team != null) {
      state.lockedOut.add(team);
      lastWrongTeam = timeout ? null : team;
    }
    answeringTeam = null;
    hostCall = null;
    if (state.lockedOut.length >= teamCount) {
      state.status = TeaserStatus.revealed;
      phase = BuzzPhase.resolved;
      outcome = const BuzzOutcome();
      _emit(GameEvent.nobodyGotIt);
      notifyListeners();
      return;
    }
    phase = BuzzPhase.open;
    secondsLeft = _paused.$1;
    phaseSeconds = _paused.$2;
    _emit(timeout ? GameEvent.timeUp : GameEvent.wrong);
    notifyListeners();
  }
}
