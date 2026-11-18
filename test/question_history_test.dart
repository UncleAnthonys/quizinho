import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/football_repository.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';

void main() {
  final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());

  test('a new match does not repeat questions from earlier matches', () async {
    final history = QuestionHistory();
    final source = ChallengeSource(repo, history: history);
    // Match 1 and match 2 each start with nothing used, like real matches.
    final first = {for (var i = 0; i < 10; i++) (await source.match(Difficulty.easy, {}))!.id};
    final second = <String>{};
    for (var i = 0; i < 3; i++) {
      second.add((await source.match(Difficulty.easy, second))!.id);
    }
    expect(second.intersection(first), isEmpty);
  });

  test('when everything has been seen, repeats come back rather than running dry', () async {
    final history = QuestionHistory();
    final source = ChallengeSource(repo, history: history);
    for (var i = 0; i < 40; i++) {
      expect(await source.match(Difficulty.easy, {}), isNotNull);
    }
  });

  test('history is stored and read back through the given storage', () {
    final store = <String, List<String>>{};
    QuestionHistory(read: (k) => store[k], write: (k, v) => store[k] = [...v]).add('conn', 'a|b');
    expect(QuestionHistory(read: (k) => store[k]).seen('conn'), {'a|b'});
  });

  group('with the room\'s phones', () {
    test('counts what joined phones have had, and repeats the fewest-seen first', () {
      final h = QuestionHistory()..addAll('teaser', ['a', 'b']);
      h.setOthers({
        'ann': {'teaser': ['b', 'c']},
        'bob': {'teaser': ['c', 'd']},
      });
      expect(h.seen('teaser'), {'a', 'b', 'c', 'd'});
      expect(h.order('teaser'), ['a', 'b'], reason: 'this phone\'s own stays its own');
      expect(h.seenCounts('teaser'), {'a': 1, 'b': 2, 'c': 2, 'd': 1});
      // One phone each: a and d, oldest first (a is the older on this phone,
      // d the newest on Bob's); then b and c, seen by two.
      expect(h.repeatOrder('teaser'), ['a', 'd', 'b', 'c']);
      h.setOthers(const {});
      expect(h.seen('teaser'), {'a', 'b'});
    });

    test('hands over its most recent, and keeps what the room sends without passing it back', () {
      final h = QuestionHistory()..addAll('conn', [for (var i = 0; i < QuestionHistory.shareCap + 5; i++) 'c$i']);
      final out = h.export();
      expect(out.keys, ['conn']);
      expect(out['conn']!.length, QuestionHistory.shareCap);
      expect(out['conn']!.last, 'c${QuestionHistory.shareCap + 4}');
      final sent = <String>[];
      h.onRecord = (k, ids) => sent.addAll(ids);
      h.addFromRoom('top10', ['x']);
      h.add('top10', 'y');
      expect(h.seen('top10'), {'x', 'y'});
      expect(sent, ['y']);
    });
  });

  test('a question a joined phone has had comes after the fresh ones', () async {
    final history = QuestionHistory();
    final source = ChallengeSource(repo, history: history);
    // What a friend's phone has had: everything this phone would pick first.
    // (Club Connections: thousands of pairs, so fresh ones never run out here.)
    final friend = ChallengeSource(repo);
    final theirs = [for (var i = 0; i < 20; i++) (await friend.clubConnection(Difficulty.medium, {}))!.id];
    history.setOthers({'friend': {'conn': theirs}});
    for (var i = 0; i < 10; i++) {
      expect(theirs, isNot(contains((await source.clubConnection(Difficulty.medium, {}))!.id)));
    }
  });
}
