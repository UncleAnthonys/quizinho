import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/games/survival/survival_controller.dart';

const _right = Player(id: 'right', name: 'Right Answer', fame: 5);
const _wrong = Player(id: 'wrong', name: 'Wrong Answer', fame: 5);

SurvivalController _controller({List<Difficulty>? asked, int pool = 1000}) {
  var n = 0;
  return SurvivalController(load: (d, used) async {
    asked?.add(d);
    if (n >= pool) return null;
    n++;
    return SurvivalQuestion(
      kind: SurvivalKind.connection,
      id: 'q$n',
      heading: 'TEST',
      prompt: 'Question $n',
      answerIds: {'right'},
    );
  });
}

void main() {
  test('a right answer scores; three misses end the run', () async {
    final c = _controller();
    await c.start();
    c.submit(_right);
    expect(c.score, 1);
    expect(c.phase, SurvivalPhase.right);
    await c.next();
    for (var i = 0; i < 3; i++) {
      c.submit(_wrong);
      expect(c.phase, SurvivalPhase.wrong);
      await c.next();
    }
    expect(c.isOver, isTrue);
    expect(c.score, 1);
    expect(c.lives, 0);
  });

  test('running out of time costs a life', () async {
    final c = _controller();
    await c.start();
    c.advance(const Duration(seconds: 30));
    expect(c.phase, SurvivalPhase.wrong);
    expect(c.lastAnswer, isNull);
    expect(c.lives, 2);
  });

  test('gets harder as the score climbs, the same for everyone', () async {
    final asked = <Difficulty>[];
    final c = _controller(asked: asked);
    await c.start();
    for (var i = 0; i < 21; i++) {
      c.submit(_right);
      await c.next();
    }
    expect(asked.first, Difficulty.easy);
    expect(asked[5], Difficulty.medium);
    expect(asked[12], Difficulty.hard);
    expect(asked[20], Difficulty.expert);
  });

  test('answers after the question is over are ignored', () async {
    final c = _controller();
    await c.start();
    c.submit(_wrong);
    c.submit(_right);
    expect(c.score, 0);
    expect(c.lives, 2);
  });

  test('running out of questions ends the run without losing', () async {
    final c = _controller(pool: 2);
    await c.start();
    c.submit(_right);
    await c.next();
    c.submit(_right);
    await c.next();
    expect(c.isOver, isTrue);
    expect(c.score, 2);
  });
}
