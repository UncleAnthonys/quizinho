import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/domain/player_index.dart';
import 'package:quizinho/domain/text_normaliser.dart';

import 'fixtures.dart';

void main() {
  group('normaliseName', () {
    test('folds accents and case', () {
      expect(normaliseName('Zlatan Ibrahimović'), 'zlatan ibrahimovic');
      expect(normaliseName('CESC FÀBREGAS'), 'cesc fabregas');
      expect(normaliseName('Ronaldo Nazário'), 'ronaldo nazario');
    });

    test('handles hyphens, apostrophes and stray punctuation', () {
      expect(normaliseName('Trent Alexander-Arnold'), 'trent alexander arnold');
      expect(normaliseName("Samuel Eto'o"), 'samuel etoo');
      expect(normaliseName('  N’Golo   Kanté!! '), 'ngolo kante');
    });

    test('similarity tolerates small typos', () {
      expect(similarity('ibrahimovic', 'ibrahimovich'), greaterThan(0.9));
      expect(similarity('henry', 'messi'), lessThan(0.5));
    });
  });

  group('PlayerIndex', () {
    final index = PlayerIndex(allPlayers);

    test('accent-free surname finds the player first', () {
      expect(index.search('ibrahimovic').first.player.id, zlatan.id);
    });

    test('aliases work', () {
      expect(index.search('Zlatan').first.player.id, zlatan.id);
      expect(index.search('cesc').first.player.id, fabregas.id);
      expect(index.search('titi').first.player.id, henry.id);
    });

    test('prefix search for fast typing', () {
      final ids = index.search('hen').map((m) => m.player.id);
      expect(ids, contains(henry.id));
    });

    test('hyphenated surname matches either half', () {
      expect(index.search('arnold').first.player.id, taa.id);
      expect(index.search('alexander arnold').first.player.id, taa.id);
    });

    test('ambiguous alias returns both candidates', () {
      final ids = index.search('ronaldo').map((m) => m.player.id).toSet();
      expect(ids, containsAll([cr7.id, r9.id]));
    });

    test('resolveConfidently refuses to guess between two Ronaldos', () {
      expect(index.resolveConfidently('ronaldo'), isNull);
      expect(index.resolveConfidently('cristiano ronaldo')?.id, cr7.id);
    });

    test('typo tolerance', () {
      expect(index.search('ibrahimovich').first.player.id, zlatan.id);
    });

    test('empty query returns nothing', () {
      expect(index.search('  '), isEmpty);
    });
  });

  test('clubs are found by the name people type (Schalke, Hertha, Leipzig)', () {
    final index = PlayerIndex([
      for (final c in const [
        Club(id: 'Q32494', name: 'Schalke 04', fame: 5),
        Club(id: 'h', name: 'Hertha BSC', fame: 4),
        Club(id: 'l', name: 'RB Leipzig', fame: 5),
        Club(id: 'k', name: '1. FC Köln', fame: 4),
        Club(id: 'b', name: 'Bayer 04 Leverkusen', fame: 5),
      ])
        c.asAnswer,
    ]);
    for (final (typed, id) in [('Schalke', 'Q32494'), ('Hertha', 'h'), ('Leipzig', 'l'), ('Koln', 'k'), ('Leverkusen', 'b')]) {
      expect(index.matchTyped(typed).map((p) => p.id), contains(id), reason: typed);
    }
  });
}
