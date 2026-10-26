import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/games/bidding_war/bidding_war_controller.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());
Player pl(String id) => Player(id: id, name: id.toUpperCase(), fame: 3);

BiddingCategory cat([int n = 6]) => BiddingCategory(
      id: 'test',
      prompt: 'Test',
      difficulty: 1,
      answerIds: {for (var i = 0; i < n; i++) 'p$i'},
    );

BiddingWarController two({int n = 6}) =>
    BiddingWarController(category: cat(n), teamCount: 2, answerSeconds: 60, countdownSeconds: 3);

void startAnswering(BiddingWarController c) => c.advance(secs(3.1));

void main() {
  group('bidding', () {
    test('opening team must bid — no challenge or pass before a bid', () {
      final c = two();
      expect(c.canChallenge, isFalse);
      expect(c.canPass, isFalse);
      c.challenge();
      expect(c.phase, BidPhase.bidding);
    });

    test('raises must go up and alternate turns', () {
      final c = two()..raise(2);
      expect((c.currentBid, c.holder, c.currentTeam), (2, 0, 1));
      c.raise(2); // not higher — ignored
      expect(c.currentBid, 2);
      c.raise(4); // can jump
      expect((c.currentBid, c.holder, c.currentTeam), (4, 1, 0));
    });

    test('cannot bid more answers than exist', () {
      final c = two(n: 6)..raise(7);
      expect(c.currentBid, 0);
    });

    test('bidding the maximum forces the next team to challenge', () {
      final c = two(n: 6)..raise(3);
      c.raise(6); // team 1 bids max
      expect(c.phase, BidPhase.countdown);
      expect((c.holder, c.challenger), (1, 0));
    });

    test('challenge puts the holder on the spot', () {
      final c = two()..raise(3);
      c.challenge();
      expect(c.phase, BidPhase.countdown);
      expect((c.holder, c.challenger), (0, 1));
    });
  });

  group('answering', () {
    BiddingWarController challenged({int bid = 3}) {
      final c = two()..raise(bid);
      c.challenge();
      startAnswering(c);
      return c;
    }

    test('countdown then the clock starts', () {
      final c = two()..raise(2);
      c.challenge();
      expect(c.phase, BidPhase.countdown);
      c.advance(secs(3.1));
      expect(c.phase, BidPhase.answering);
      expect(c.secondsLeft, 60);
    });

    test('correct answers count once; duplicates and wrong ones do not', () {
      final c = challenged();
      expect(c.submit(pl('p0')), BidSubmit.correct);
      expect(c.submit(pl('p0')), BidSubmit.duplicate);
      expect(c.submit(pl('nobody')), BidSubmit.wrong);
      expect(c.correctCount, 1);
      expect(c.phase, BidPhase.answering);
    });

    test('hitting the target ends it at once — bidder scores 3', () {
      final c = challenged(bid: 2)..submit(pl('p0'));
      c.submit(pl('p1'));
      expect(c.phase, BidPhase.finished);
      expect(c.completed, isTrue);
      expect(c.result().points, {0: 3, 1: 0});
    });

    test('time running out — challenger scores 3', () {
      final c = challenged()..submit(pl('p0'));
      c.advance(secs(60.1));
      expect(c.completed, isFalse);
      expect(c.result().points, {0: 0, 1: 3});
    });

    test('room-approved answers count, once each', () {
      final c = challenged(bid: 2)..submitDisputed('Obscure Guy');
      c.submitDisputed('obscure guy');
      expect(c.correctCount, 1);
      c.submit(pl('p3'));
      expect(c.completed, isTrue);
    });
  });

  group('three or more teams', () {
    BiddingWarController three() => BiddingWarController(category: cat(10), teamCount: 3);

    test('turns go round; passing drops a team out', () {
      final c = three()..raise(2); // A
      expect(c.currentTeam, 1);
      c.pass(); // B out
      expect(c.currentTeam, 2);
      c.raise(4); // C
      expect(c.currentTeam, 0); // skips B
    });

    test('last bidder standing is challenged by the last team to pass', () {
      final c = three()..raise(2); // A
      c.pass(); // B
      c.pass(); // C — only A left
      expect(c.phase, BidPhase.countdown);
      expect((c.holder, c.challenger), (0, 2));
    });

    test('a direct challenge works too, and only the challenger can win the points', () {
      final c = three()..raise(2); // A
      c.raise(3); // B
      c.challenge(); // C challenges B
      expect((c.holder, c.challenger), (1, 2));
      startAnswering(c);
      c.advance(secs(61));
      expect(c.result().points, {0: 0, 1: 0, 2: 3});
    });

    test('two teams can never pass', () {
      final c = two()..raise(1);
      expect(c.canPass, isFalse);
    });
  });

  group('category mix', () {
    test('kinds come up roughly 40 / 40 / 20', () {
      final r = Random(3);
      final counts = <BiddingKind, int>{};
      for (var i = 0; i < 10000; i++) {
        final k = BiddingKind.choose(BiddingKind.values.toSet(), r)!;
        counts[k] = (counts[k] ?? 0) + 1;
      }
      expect(counts[BiddingKind.curated]! / 10000, closeTo(0.4, 0.03));
      expect(counts[BiddingKind.pair]! / 10000, closeTo(0.4, 0.03));
      expect(counts[BiddingKind.nationality]! / 10000, closeTo(0.2, 0.03));
    });

    test('a kind with nothing left is never chosen', () {
      final r = Random(4);
      for (var i = 0; i < 200; i++) {
        expect(BiddingKind.choose({BiddingKind.pair, BiddingKind.nationality}, r), isNot(BiddingKind.curated));
      }
      expect(BiddingKind.choose({}, r), isNull);
    });

    test('kind is read from the id', () {
      expect(BiddingKind.ofId('stat:pl-100-goals'), BiddingKind.curated);
      expect(BiddingKind.ofId('nat:Q9616:BRA'), BiddingKind.nationality);
      expect(BiddingKind.ofId('pair:Q1|Q2'), BiddingKind.pair);
    });
  });

  test('bundled data has short hand-made categories, every answer real', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    final curated = repo.bidding.where((b) => b.kind == BiddingKind.curated).toList();
    expect(curated.length, greaterThanOrEqualTo(25));
    for (final b in curated) {
      // Short enough to get through in a minute.
      expect(b.answerIds.length, inInclusiveRange(5, 20), reason: b.id);
      final index = b.answersAreClubs ? repo.clubIndex : repo.players;
      for (final id in b.answerIds) {
        expect(index.byId(id), isNotNull, reason: '${b.id}: $id');
      }
    }
    final top10 = curated.firstWhere((b) => b.id == 'stat:top10-pl-scorers');
    expect(top10.answerIds, containsAll(['alan-shearer', 'harry-kane', 'mohamed-salah']));
    // Common spellings type in even where the data's name differs.
    expect(repo.players.matchTyped('Juan Mata').map((p) => p.id), contains('juan-mata-pata'));
  });

  test('club categories take clubs, nicknames included', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    final winners = repo.bidding.firstWhere((b) => b.id == 'clubs:pl-winning-clubs');
    expect(winners.answersAreClubs, isTrue);
    expect(winners.kind, BiddingKind.curated);
    expect(winners.answerIds.length, 7);
    final spurs = repo.clubIndex.matchTyped('Spurs').map((c) => c.name);
    expect(spurs, contains('Tottenham Hotspur'));
    final blackburn = repo.clubIndex.matchTyped('Blackburn Rovers').first;
    expect(winners.answerIds, contains(blackburn.id));
  });

  test('bundled data has playable Bidding War categories', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    final b = await repo.pickBiddingCategory(levels: {1});
    expect(b, isNotNull);
    expect(b!.answerIds.length, inInclusiveRange(5, 35));
    for (final id in b.answerIds) {
      expect(repo.players.byId(id), isNotNull);
    }
  });
}
