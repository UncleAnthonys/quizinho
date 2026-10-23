import 'dart:math';

import '../../data/models.dart';
import '../../domain/game_mode.dart';
import '../buzz_race_controller.dart';

/// Career Path: clubs are revealed one by one; buzz early for more points.
class CareerPathController extends BuzzRaceController<CareerPath> {
  CareerPathController({
    required super.teamCount,
    required super.questions,
    int answerSeconds = 15,
    this.revealSeconds = 6,
    this.finalSeconds = 12,
  }) : super(mode: GameModeId.careerPath, answerSeconds: answerSeconds);

  final double revealSeconds;

  /// After the last club is shown, how long teams get before it's a wash.
  final double finalSeconds;

  static const int maxPoints = 5;

  int revealed = 1;

  int get clueCount => current.spells.length;
  bool get allRevealed => revealed >= clueCount;

  /// Points on offer if someone answers correctly right now.
  int get pointsAvailable => max(1, maxPoints - (revealed - 1));

  @override
  void onQuestionStart() {
    revealed = 1;
    setTimer(clueCount > 1 ? revealSeconds : finalSeconds);
  }

  @override
  bool tickOpen(double dt) {
    secondsLeft -= dt;
    if (secondsLeft > 0) return false;
    if (allRevealed) {
      secondsLeft = 0;
      return true;
    }
    revealed++;
    emit(GameEvent.reveal);
    setTimer(allRevealed ? finalSeconds : revealSeconds);
    return false;
  }

  @override
  void onReopen() {
    // Keep the reveal clock where it was, but never less than 3 seconds.
    if (secondsLeft < 3) setTimer(3);
  }

  @override
  bool isCorrect(Player p) => p.id == current.player.id;

  @override
  (int, bool) pointsFor(Player p) => (pointsAvailable, false);
}
