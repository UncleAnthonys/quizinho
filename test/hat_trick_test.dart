import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/in_memory_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/games/buzz_race_controller.dart';
import 'package:quizinho/games/hat_trick/hat_trick_controller.dart';

const _milan = Club(id: 'milan', name: 'AC Milan', fame: 5);
const _city = Club(id: 'city', name: 'Manchester City', fame: 5);
const _chelsea = Club(id: 'chelsea', name: 'Chelsea', fame: 5);

const _weah = Player(id: 'weah', name: 'George Weah', fame: 5);
const _lampard = Player(id: 'lampard', name: 'Frank Lampard', fame: 5);
const _torres = Player(id: 'torres', name: 'Fernando Torres', fame: 5);
const _kane = Player(id: 'kane', name: 'Harry Kane', fame: 5);

const _set = HatTrickSet(
  id: 'milan|city|chelsea',
  clubs: [_milan, _city, _chelsea],
  // bits: 1 = Milan, 2 = City, 4 = Chelsea
  played: {'weah': 7, 'lampard': 6, 'torres': 5, 'mancini': 2},
  difficulty: 1,
);

void main() {
  test('a point per club, and a hat-trick is 3 + the bonus', () {
    final c = HatTrickController(teamCount: 3, questions: [_set]);
    c.buzz(0);
    c.submit(_lampard); // City + Chelsea
    expect(c.picks[0]!.points, 2);
    expect(c.phase, BuzzPhase.open, reason: 'the other teams still get a go');
    c.buzz(1);
    c.submit(_weah); // all three
    expect(c.picks[1]!.points, 4);
    expect(c.lastEvent, GameEvent.deepCut);
    c.buzz(2);
    c.submit(_kane); // none
    expect(c.picks[2]!.points, 0);
    expect(c.phase, BuzzPhase.resolved, reason: 'everyone has had their go');
    expect(c.roundPoints, {0: 2, 1: 4, 2: 0});
  });

  test('each team answers once', () {
    final c = HatTrickController(teamCount: 2, questions: [_set]);
    c.buzz(0);
    c.submit(_torres);
    expect(c.canBuzz(0), isFalse);
    expect(c.canBuzz(1), isTrue);
  });

  test('a player already named is gone: the team picks again', () {
    final c = HatTrickController(teamCount: 2, questions: [_set]);
    c.buzz(0);
    c.submit(_weah);
    c.buzz(1);
    c.submit(_weah);
    expect(c.rejected, 'George Weah');
    expect(c.phase, BuzzPhase.answering, reason: 'still their go');
    c.submit(_lampard);
    expect(c.picks[1]!.points, 2);
  });

  test('the clock running out ends the set; whoever answered keeps their points', () {
    final c = HatTrickController(teamCount: 2, questions: [_set], openSeconds: 10);
    c.buzz(0);
    c.submit(_torres);
    c.advance(const Duration(seconds: 30));
    expect(c.phase, BuzzPhase.resolved);
    expect(c.roundPoints, {0: 2, 1: 0});
  });

  test('after a go, the clock carries on from where it stopped at the buzz', () {
    final c = HatTrickController(teamCount: 2, questions: [_set], openSeconds: 45);
    c.advance(const Duration(seconds: 38)); // 7 left
    c.buzz(0);
    c.advance(const Duration(seconds: 12)); // answering (15 s to answer)
    expect(c.phase, BuzzPhase.answering);
    c.submit(_torres);
    expect(c.secondsLeft, closeTo(7, 0.01));
  });

  test('solo: a hat-trick is full marks for the set', () {
    final c = HatTrickController(teamCount: 1, questions: [_set]);
    c.submitSolo(_weah);
    expect(c.phase, BuzzPhase.resolved);
    expect(c.lastSolo, BuzzRaceController.soloPerQuestion.round());
  });

  test('web data: who played where comes from the club lists when a set is picked', () async {
    final repo = InMemoryFootballRepository(
      players: const [_weah, _lampard],
      hatTricks: const [
        HatTrickSet(id: 'milan|city|chelsea', clubs: [_milan, _city, _chelsea], played: {}, difficulty: 1),
      ],
      clubRosters: const {
        'milan': ['weah'],
        'city': ['weah', 'lampard'],
        'chelsea': ['weah', 'lampard'],
      },
    );
    final h = (await repo.pickHatTrick())!;
    expect(h.hits('weah'), 3);
    expect(h.hits('lampard'), 2);
    expect(h.clubsOf('lampard'), [false, true, true]);
    expect(h.heroes, ['weah']);
  });
}
