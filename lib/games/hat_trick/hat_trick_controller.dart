import 'dart:math';

import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../buzz_race_controller.dart';

/// One team's answer to a Hat-Trick set.
class HatTrickPick {
  const HatTrickPick({required this.player, required this.clubs, required this.points});
  final Player player;

  /// Which of the three clubs he played for.
  final List<bool> clubs;

  /// 0-3, and 4 for a hat-trick (3 + the bonus).
  final int points;
  int get hits => clubs.where((x) => x).length;
  bool get hatTrick => hits == 3;
}

/// Hat-Trick: three clubs; each team buzzes in once and names a player - a
/// point for each of the clubs he played for, a hat-trick (all three) is
/// worth 3 + a bonus point. The clock is long: lock in a 2-pointer, or hold
/// out for the hat-trick. A player named once is gone for the others.
class HatTrickController extends BuzzRaceController<HatTrickSet> {
  HatTrickController({
    required super.teamCount,
    required super.questions,
    int answerSeconds = 15,
    this.openSeconds = 45,
    this.minReopenSeconds = 10,
  }) : super(mode: GameModeId.hatTrick, answerSeconds: answerSeconds);

  /// The clock for the whole set: long enough to hold out for three.
  final double openSeconds;

  /// After a team's go, the others get at least this long.
  final double minReopenSeconds;

  static const int hatTrickBonus = 1;

  /// This set's answers so far, by team.
  final Map<int, HatTrickPick> picks = {};

  /// Named this set (gone for everyone else).
  final Set<String> _taken = {};

  /// A player already named this set was picked again: the answer box says
  /// so and the team picks again ([rejectSerial] changes each time).
  String? rejected;
  int rejectSerial = 0;

  @override
  void onQuestionStart() {
    picks.clear();
    _taken.clear();
    rejected = null;
    setTimer(openSeconds);
  }

  @override
  bool tickOpen(double dt) {
    secondsLeft -= dt;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      return true;
    }
    return false;
  }

  @override
  void onReopen() => setTimer(max(secondsLeft, minReopenSeconds));

  /// Played for at least one of the three, and not named yet - voice leans
  /// towards these.
  @override
  bool isCorrect(Player p) => current.hits(p.id) > 0 && !_taken.contains(p.id);

  @override
  (int, bool) pointsFor(Player p) {
    final hits = current.hits(p.id);
    return (hits + (hits == 3 ? hatTrickBonus : 0), hits == 3);
  }

  bool isTaken(String playerId) => _taken.contains(playerId);

  @override
  void submit(Player player) {
    final team = answeringTeam;
    if (phase != BuzzPhase.answering || team == null) return;
    if (_taken.contains(player.id)) {
      rejected = player.name;
      rejectSerial++;
      notifyListeners();
      return;
    }
    final (points, _) = pointsFor(player);
    final pick = HatTrickPick(player: player, clubs: current.clubsOf(player.id), points: points);
    picks[team] = pick;
    _taken.add(player.id);
    lastMiss = pick.hits == 0 ? player.name : null;
    if (pick.hits == 0) wrongSerial++;
    if (teamCount == 1) {
      final s = points / (3 + hatTrickBonus) * BuzzRaceController.soloPerQuestion;
      soloTotal += s;
      lastSolo = s.round();
    }
    endTurn(
      pick.hits == 0 ? GameEvent.wrong : (pick.hatTrick ? GameEvent.deepCut : GameEvent.correct),
      points: points,
    );
  }

  /// The best answer this set (for the reveal): most points.
  int get bestPoints => picks.values.fold(0, (a, p) => max(a, p.points));
}
