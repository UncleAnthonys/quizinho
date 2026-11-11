import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/data/question_history.dart';
import 'package:quizinho/data/teasers.dart';
import 'package:quizinho/domain/player_index.dart';
import 'package:quizinho/domain/tournament.dart';
import 'package:quizinho/games/buzz_race_controller.dart';
import 'package:quizinho/games/teaser/teaser_controller.dart';

const _owen = Player(id: 'michael-owen', name: 'Michael Owen', fame: 4);
const _beckham = Player(id: 'david-beckham', name: 'David Beckham', fame: 5);
const _hughes = Player(id: 'mark-hughes', name: 'Mark Hughes', fame: 3);

const _teaser = Teaser(
  question: 'Played under Sir Alex Ferguson, played in the Merseyside derby AND was a club teammate of Zinedine Zidane',
  family: 'mixed',
  level: 2,
  eras: 31,
  answerIds: ['michael-owen'],
  answerNames: ['Michael Owen'],
  unsure: {'mark-hughes'},
  herrings: {'david-beckham': 'Ferguson and Zidane yes, but never played for Liverpool or Everton'},
);

Tournament _match({int teams = 2}) {
  final t = Tournament(TournamentConfig(teams: [
    for (var i = 0; i < teams; i++) TeamSetup(name: 'Team $i', colorIndex: i),
  ]));
  t.teaser = TeaserState(_teaser.id)..halfTimeDone = true;
  return t;
}

void main() {
  group('Teaser controller', () {
    test('half-time: right answer is worth 5 and solves it', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: true);
      c.buzz(1);
      c.submit(_owen);
      expect(t.scores, [0, 5]);
      expect(t.teaser!.status, TeaserStatus.solved);
      expect(c.phase, BuzzPhase.resolved);
    });

    test('between games it is worth 3', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: false);
      c.buzz(0);
      c.submit(_owen);
      expect(t.scores, [3, 0]);
    });

    test('a wrong guess locks the team out; all wrong reveals it', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: false);
      c.buzz(0);
      c.submit(_beckham);
      expect(t.teaser!.lockedOut, {0});
      expect(c.canBuzz(0), isFalse);
      expect(c.phase, BuzzPhase.open);
      c.buzz(1);
      c.submit(_beckham);
      expect(t.teaser!.status, TeaserStatus.revealed);
      expect(c.phase, BuzzPhase.resolved);
      expect(t.scores, [0, 0]);
    });

    test('the host can overrule a wrong answer', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: false);
      c.buzz(0);
      c.submit(_beckham);
      expect(c.canOverrule, isTrue);
      c.overrule();
      expect(t.scores, [3, 0]);
      expect(t.teaser!.status, TeaserStatus.solved);
    });

    test('an unconfirmed answer is the host’s call', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: false);
      c.buzz(0);
      c.submit(_hughes);
      expect(c.hostCall, _hughes);
      c.decide(counts: false);
      expect(t.teaser!.lockedOut, {0});
    });

    test('the half-time clock running out leaves it open for 3', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: true, halfTimeSeconds: 2);
      c.advance(const Duration(seconds: 3));
      expect(c.clockDone, isTrue);
      expect(c.canBuzz(0), isFalse);
      expect(t.teaser!.isOpen, isTrue);
    });

    test('answer clock: too slow counts as a guess', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: false, answerSeconds: 5);
      c.buzz(0);
      c.advance(const Duration(seconds: 6));
      expect(t.teaser!.lockedOut, {0});
      expect(c.canOverrule, isFalse);
    });

    test('full time reveals it', () {
      final t = _match();
      final c = TeaserController(tournament: t, teaser: _teaser, halfTime: false);
      c.reveal();
      expect(t.teaser!.status, TeaserStatus.revealed);
    });
  });

  test('teaser state survives a save', () {
    final t = _match();
    t.teaser!.lockedOut.add(1);
    final back = Tournament.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, Object?>)!;
    expect(back.teaser!.id, _teaser.id);
    expect(back.teaser!.lockedOut, {1});
    expect(back.teaser!.halfTimeDone, isTrue);
  });

  test('half-time falls after half the rounds', () {
    final t = Tournament(TournamentConfig(teams: [TeamSetup(name: 'A', colorIndex: 0), TeamSetup(name: 'B', colorIndex: 1)]));
    expect(t.halfTimeAfter, 3);
    expect(t.wantsTeaser, isTrue);
  });

  group('Teaser picker', () {
    final bank = TeaserBank.parse(File('assets/db/teasers.json').readAsStringSync());
    final players = PlayerIndex([for (final t in bank.teasers) for (final (i, id) in t.answerIds.indexed) Player(id: id, name: t.answerNames[i], fame: 5)]);

    test('the bank loads', () {
      expect(bank.teasers.length, greaterThan(100));
    });

    test('no repeats until the level runs dry, and no derby twice in a row', () {
      final history = QuestionHistory();
      final picker = TeaserPicker(bank: bank, history: history, players: players, random: Random(1));
      final seen = <String>{};
      String? lastFamily;
      for (var i = 0; i < 40; i++) {
        final t = picker.pick(difficulty: Difficulty.medium)!;
        expect(seen.add(t.id), isTrue, reason: 'repeat at $i');
        expect(t.level <= 2, isTrue);
        if (lastFamily == 'derby') expect(t.family, isNot('derby'));
        lastFamily = t.family;
      }
    });

    test('different phones pick differently', () {
      final a = TeaserPicker(bank: bank, history: QuestionHistory(), players: players, random: Random(1));
      final b = TeaserPicker(bank: bank, history: QuestionHistory(), players: players, random: Random(2));
      final pa = [for (var i = 0; i < 5; i++) a.pick(difficulty: Difficulty.medium)!.id];
      final pb = [for (var i = 0; i < 5; i++) b.pick(difficulty: Difficulty.medium)!.id];
      expect(pa, isNot(pb));
    });
  });
}
