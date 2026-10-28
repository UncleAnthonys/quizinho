import 'package:flutter/foundation.dart';

import '../../data/models.dart';

/// The kinds of question Survival mixes together. Each needs ONE right answer.
enum SurvivalKind { connection, career, lineup, category }

/// One Survival question, whatever game it comes from.
class SurvivalQuestion {
  const SurvivalQuestion({
    required this.kind,
    required this.id,
    required this.heading,
    required this.prompt,
    required this.answerIds,
    this.lines = const [],
    this.difficulty = 1,
    this.showFlags = true,
    this.showPositions = true,
  });

  /// Off when the answer list's flags or positions would give it away.
  final bool showFlags;
  final bool showPositions;

  final SurvivalKind kind;

  /// Unique across kinds, so nothing repeats within a run.
  final String id;

  /// Small label above the question ("CLUB CONNECTIONS").
  final String heading;

  /// The question itself ("Name a player who played for both…").
  final String prompt;

  /// Extra lines shown under the prompt (a career's clubs, a match line).
  final List<String> lines;
  final Set<String> answerIds;
  final int difficulty;
}

enum SurvivalPhase { loading, asking, right, wrong, over }

/// Solo mode: answer questions from every game, one after another, getting
/// harder as you go. A wrong answer or running out of time costs a life;
/// three lives and you're out. Your score is how many you got right — the
/// same climb for everyone, so scores compare fairly.
///
/// Time is driven through [advance] so tests are deterministic.
class SurvivalController extends ChangeNotifier {
  SurvivalController({required this.load, this.lives = 3, this.questionSeconds = 25});

  /// Fetches the next question at a difficulty (null = nothing left).
  final Future<SurvivalQuestion?> Function(Difficulty difficulty, Set<String> used) load;
  final int questionSeconds;

  int lives;
  int score = 0;
  SurvivalPhase phase = SurvivalPhase.loading;
  SurvivalQuestion? current;
  double secondsLeft = 0;

  /// The answer given to the last question (null = ran out of time).
  Player? lastAnswer;
  final Set<String> _used = {};

  /// Bumped on every right/wrong so the screen plays a sound once.
  int eventSerial = 0;

  /// The climb: easy questions first, expert from 20 right answers.
  static Difficulty difficultyFor(int score) => score < 5
      ? Difficulty.easy
      : score < 12
          ? Difficulty.medium
          : score < 20
              ? Difficulty.hard
              : Difficulty.expert;

  Difficulty get difficulty => difficultyFor(score);
  double get fraction => questionSeconds == 0 ? 0 : secondsLeft / questionSeconds;
  bool get isOver => phase == SurvivalPhase.over;

  /// Loads the first question.
  Future<void> start() => _nextQuestion();

  Future<void> _nextQuestion() async {
    phase = SurvivalPhase.loading;
    lastAnswer = null;
    notifyListeners();
    final q = await load(difficulty, _used);
    if (q == null) {
      // Ran out of questions at every level — the run ends unbeaten.
      phase = SurvivalPhase.over;
      current = null;
      notifyListeners();
      return;
    }
    _used.add(q.id);
    current = q;
    secondsLeft = questionSeconds.toDouble();
    phase = SurvivalPhase.asking;
    notifyListeners();
  }

  void advance(Duration elapsed) {
    if (phase != SurvivalPhase.asking) return;
    secondsLeft -= elapsed.inMicroseconds / 1e6;
    if (secondsLeft <= 0) {
      secondsLeft = 0;
      _miss();
      return;
    }
    notifyListeners();
  }

  bool isRightAnswer(Player p) => current?.answerIds.contains(p.id) ?? false;

  void submit(Player p) {
    if (phase != SurvivalPhase.asking) return;
    lastAnswer = p;
    if (isRightAnswer(p)) {
      score++;
      phase = SurvivalPhase.right;
      eventSerial++;
      notifyListeners();
    } else {
      _miss();
    }
  }

  /// Giving up on a question costs a life, same as a wrong answer.
  void pass() {
    if (phase == SurvivalPhase.asking) _miss();
  }

  void _miss() {
    lives--;
    phase = SurvivalPhase.wrong;
    eventSerial++;
    notifyListeners();
  }

  /// After the result card: next question, or the end of the run.
  Future<void> next() async {
    if (phase != SurvivalPhase.right && phase != SurvivalPhase.wrong) return;
    if (lives <= 0) {
      phase = SurvivalPhase.over;
      notifyListeners();
      return;
    }
    await _nextQuestion();
  }
}
