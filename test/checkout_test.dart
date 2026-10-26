import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/games/checkout_501/checkout_controller.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());
Player pl(String id) => Player(id: id, name: id, fame: 3);

/// Values: a=150, b=150, c=150, d=46, e=50, big=300, f=60.
CheckoutCategory cat() => const CheckoutCategory(
      id: 'test',
      prompt: 'Test',
      difficulty: 1,
      values: {
        'a': (100, 50),
        'b': (120, 30),
        'c': (140, 10),
        'd': (40, 6),
        'e': (45, 5),
        'big': (250, 50),
        'f': (50, 10),
      },
      noStats: {'ghost'},
    );

CheckoutController two() => CheckoutController(category: cat(), teamCount: 2, revealSeconds: 1)..begin();

void throwAndNext(CheckoutController c, String id) {
  c.submit(pl(id));
  c.next();
}

void main() {
  test('apps + goals come off 501, teams alternate', () {
    final c = two();
    throwAndNext(c, 'a');
    expect(c.remaining, [351, 501]);
    expect(c.currentTeam, 1);
    throwAndNext(c, 'b');
    expect(c.remaining, [351, 351]);
  });

  test('over 180 is a bust: score stays, turn passes, player still used', () {
    final c = two()..submit(pl('big'));
    expect(c.lastThrow!.outcome, CoOutcome.bust);
    expect(c.remaining[0], 501);
    c.next();
    expect(c.currentTeam, 1);
    c.submit(pl('big'));
    expect(c.lastEvent, CoEvent.duplicate);
  });

  test('a player named by one team is gone for the other (snatching)', () {
    final c = two();
    throwAndNext(c, 'a');
    c.submit(pl('a'));
    expect(c.lastEvent, CoEvent.duplicate);
    expect(c.phase, CoPhase.answering); // no turn lost
    expect(c.currentTeam, 1);
  });

  test('finishing between 0 and -10 checks out and wins', () {
    final c = two();
    // A: 501 -150 -150 -150 = 51; then 'e' (50) -> 1; then 'd' (46)... use f
    throwAndNext(c, 'a'); // A 351
    throwAndNext(c, 'f'); // B 441
    throwAndNext(c, 'b'); // A 201
    c.pass(); // B
    c.next();
    throwAndNext(c, 'c'); // A 51
    c.pass();
    c.next();
    c.submit(pl('e')); // A 51 - 50 = 1, still in
    expect(c.lastThrow!.outcome, CoOutcome.scored);
    c.next();
    c.pass();
    c.next();
    c.submit(pl('d')); // 1 - 46 = -45: below -10 → bust
    expect(c.lastThrow!.outcome, CoOutcome.overshoot);
    expect(c.remaining[0], 1);
  });

  test('landing in the window ends the round', () {
    final c = CheckoutController(
      category: const CheckoutCategory(id: 't', prompt: 'T', difficulty: 1, values: {
        'x': (150, 30), 'y': (150, 30), 'z': (100, 41), 'w': (5, 0),
      }),
      teamCount: 2,
    )..begin();
    throwAndNext(c, 'x'); // A 321
    c.pass(); // B
    c.next();
    throwAndNext(c, 'y'); // A 141
    c.pass();
    c.next();
    c.submit(pl('z')); // 141 - 141 = 0 → checkout
    expect(c.lastThrow!.outcome, CoOutcome.checkout);
    c.next();
    expect(c.phase, CoPhase.finished);
    expect(c.result().points, {0: 3, 1: 0});
  });

  test('wrong player, no-stats player and time up', () {
    final c = two()..submit(pl('ghost'));
    expect(c.lastEvent, CoEvent.noStats);
    expect(c.phase, CoPhase.answering);
    c.submit(pl('nobody'));
    expect(c.lastThrow!.outcome, CoOutcome.wrong);
    c.next();
    c.advance(secs(31));
    expect(c.lastThrow!.outcome, CoOutcome.timeUp);
  });

  test('no checkout after the turn limit: closest to zero wins', () {
    final c = CheckoutController(category: cat(), teamCount: 2, maxTurns: 1)..begin();
    throwAndNext(c, 'a'); // A 351
    throwAndNext(c, 'f'); // B 441
    expect(c.phase, CoPhase.finished);
    expect(c.winners, {0});
  });

  test('bundled 501 categories have enough darts for two teams', () {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    expect(repo.checkouts.length, greaterThanOrEqualTo(50));
    for (final c in repo.checkouts) {
      final darts = c.values.values.where((v) => v.$1 + v.$2 <= 180).length;
      expect(darts, greaterThanOrEqualTo(30), reason: c.id);
      for (final id in [...c.values.keys, ...c.noStats]) {
        expect(repo.players.byId(id), isNotNull, reason: '${c.id}: $id');
      }
    }
  });
}
