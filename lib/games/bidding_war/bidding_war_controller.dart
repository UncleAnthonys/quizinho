import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';

enum BidPhase { bidding, countdown, answering, finished }

enum BidEvent { raised, challenged, go, correct, duplicate, wrong, completed, failed }

enum BidSubmit { correct, duplicate, wrong, ignored }

/// Bidding War: teams bid how many answers they can name in a category; the
/// last bidder is challenged and must name that many before time runs out.
///
/// Two teams: raise or challenge. Three or more: bidding goes round in order
/// and a team may also pass (out of the bidding for this round). When only
/// the top bidder is left, they're challenged by the last team to pass.
/// Bidding the maximum possible answers forces an immediate challenge.
class BiddingWarController extends ChangeNotifier {
  BiddingWarController({
    required this.category,
    required this.teamCount,
    int startTeam = 0,
    this.answerSeconds = 60,
    this.countdownSeconds = 3,
  })  : assert(teamCount >= 2),
        currentTeam = startTeam % teamCount,
        active = {for (var t = 0; t < teamCount; t++) t};

  final BiddingCategory category;
  final int teamCount;
  final int answerSeconds;
  final int countdownSeconds;

  static const int points = 3;

  BidPhase phase = BidPhase.bidding;
  int currentBid = 0;

  /// Team holding the highest bid (null before the opening bid).
  int? holder;

  /// Team whose turn it is to act.
  int currentTeam;

  /// Teams still in the bidding (never loses the holder).
  final Set<int> active;

  /// Team that challenged — earns the points if the bidder fails.
  int? challenger;

  double secondsLeft = 0;

  /// Accepted answers in order: player names (or "Room vote" entries).
  final List<String> named = [];
  final Set<String> _namedIds = {};

  bool? completed;

  BidEvent? lastEvent;
  int eventSerial = 0;

  int get maxBid => category.maxBid;
  int get minRaise => currentBid + 1;
  int get correctCount => named.length;
  bool get canRaise => phase == BidPhase.bidding && minRaise <= maxBid;
  bool get canChallenge => phase == BidPhase.bidding && holder != null && currentTeam != holder;
  bool get canPass => phase == BidPhase.bidding && teamCount > 2 && holder != null && currentTeam != holder;
  double get fractionLeft => answerSeconds == 0 ? 0 : (secondsLeft / answerSeconds).clamp(0.0, 1.0);

  /// Bid [to] answers (must beat the current bid, max = answers that exist).
  void raise(int to) {
    if (!canRaise || to < minRaise || to > maxBid) return;
    currentBid = to;
    holder = currentTeam;
    _emit(BidEvent.raised);
    if (to >= maxBid) {
      // Nobody can go higher — the next team in line has to challenge.
      _startChallenge(_nextActive(after: currentTeam));
      return;
    }
    currentTeam = _nextActive(after: currentTeam);
    notifyListeners();
  }

  void challenge() {
    if (!canChallenge) return;
    _startChallenge(currentTeam);
  }

  /// 3+ teams only: drop out of this round's bidding.
  void pass() {
    if (!canPass) return;
    final passer = currentTeam;
    active.remove(passer);
    if (active.length == 1) {
      _startChallenge(passer); // only the top bidder left
      return;
    }
    currentTeam = _nextActive(after: passer);
    notifyListeners();
  }

  void advance(Duration elapsed) {
    final dt = elapsed.inMicroseconds / 1e6;
    if (phase == BidPhase.countdown) {
      secondsLeft -= dt;
      if (secondsLeft <= 0) {
        phase = BidPhase.answering;
        secondsLeft = answerSeconds.toDouble();
        _emit(BidEvent.go);
      }
      notifyListeners();
    } else if (phase == BidPhase.answering) {
      secondsLeft -= dt;
      if (secondsLeft <= 0) {
        secondsLeft = 0;
        _finish(false);
        return;
      }
      notifyListeners();
    }
  }

  BidSubmit submit(Player p) {
    if (phase != BidPhase.answering) return BidSubmit.ignored;
    if (_namedIds.contains(p.id)) {
      _emit(BidEvent.duplicate);
      notifyListeners();
      return BidSubmit.duplicate;
    }
    if (!category.answerIds.contains(p.id)) {
      _emit(BidEvent.wrong); // no penalty — the clock is the pressure
      notifyListeners();
      return BidSubmit.wrong;
    }
    _namedIds.add(p.id);
    named.add(p.name);
    _emit(BidEvent.correct);
    _checkDone();
    return BidSubmit.correct;
  }

  /// A right answer missing from our data, confirmed by the room.
  void submitDisputed(String typed) {
    if (phase != BidPhase.answering) return;
    final key = 'vote:${typed.trim().toLowerCase()}';
    if (!_namedIds.add(key)) return;
    named.add('$typed (room vote)');
    _emit(BidEvent.correct);
    _checkDone();
  }

  RoundResult result() {
    final pts = {for (var t = 0; t < teamCount; t++) t: 0};
    final winner = completed == true ? holder : challenger;
    if (winner != null) pts[winner] = points;
    return RoundResult(mode: GameModeId.biddingWar, points: pts);
  }

  void _checkDone() {
    if (correctCount >= currentBid) {
      _finish(true);
    } else {
      notifyListeners();
    }
  }

  void _startChallenge(int by) {
    challenger = by;
    phase = BidPhase.countdown;
    secondsLeft = countdownSeconds.toDouble();
    _emit(BidEvent.challenged);
    notifyListeners();
  }

  void _finish(bool done) {
    completed = done;
    phase = BidPhase.finished;
    _emit(done ? BidEvent.completed : BidEvent.failed);
    notifyListeners();
  }

  int _nextActive({required int after}) {
    for (var step = 1; step <= teamCount; step++) {
      final t = (after + step) % teamCount;
      if (active.contains(t)) return t;
    }
    return after;
  }

  void _emit(BidEvent e) {
    lastEvent = e;
    eventSerial++;
  }
}
