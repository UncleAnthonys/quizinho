import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../buzz_race_controller.dart';

/// Club Connections: name a player who played for both clubs.
class ClubConnectionsController extends BuzzRaceController<ClubConnection> {
  ClubConnectionsController({
    required super.teamCount,
    required super.questions,
    int answerSeconds = 15,
    this.openSeconds = 30,
    this.stealSeconds = 12,
  }) : super(mode: GameModeId.clubConnections, answerSeconds: answerSeconds);

  final double openSeconds;
  final double stealSeconds;

  static const int basePoints = 2;

  /// A correct answer whose fame is ≤ this earns a deep-cut bonus point.
  static const int deepCutFame = 3;

  @override
  void onQuestionStart() => setTimer(openSeconds);

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
  void onReopen() {
    // Give the other teams a fair, fresh window to steal.
    setTimer(secondsLeft > stealSeconds ? secondsLeft : stealSeconds);
  }

  @override
  bool isCorrect(Player p) => current.answerIds.contains(p.id);

  /// Easy pairs: famous names everyone should get.
  @override
  bool get currentIsObvious => current.difficulty <= 1;

  @override
  (int, bool) pointsFor(Player p) {
    final bonus = p.fame <= deepCutFame;
    return (basePoints + (bonus ? 1 : 0), bonus);
  }
}
