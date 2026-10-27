import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/domain/player_index.dart';
import 'package:quizinho/domain/text_normaliser.dart';

const _players = [
  Player(id: 'david-luiz', name: 'David Luiz', fame: 4, aliases: ['Luiz']),
  Player(id: 'david-beckham', name: 'David Beckham', fame: 5),
  Player(id: 'virgil-van-dijk', name: 'Virgil van Dijk', fame: 5, aliases: ['VVD', 'Van Dijk']),
  Player(id: 'cristiano-ronaldo', name: 'Cristiano Ronaldo', fame: 5, aliases: ['Ronaldo', 'CR7']),
  Player(id: 'ronaldo-nazario', name: 'Ronaldo Nazário', fame: 5, aliases: ['Ronaldo', 'R9']),
  Player(id: 'ngolo-kante', name: "N'Golo Kanté", fame: 4, aliases: ['Kante']),
  Player(id: 'thierry-henry', name: 'Thierry Henry', fame: 5),
  Player(id: 'zlatan', name: 'Zlatan Ibrahimović', fame: 5, aliases: ['Zlatan']),
];

void main() {
  final index = PlayerIndex(_players);

  test('sound keys ignore vowel mishearings', () {
    expect(soundKey('luiz'), soundKey('louise'));
    expect(soundKey('van dijk'), soundKey('van dyke'));
    expect(soundKey('mbappe'), soundKey('embappe'));
  });

  test('"david louise" is accepted as David Luiz', () {
    expect(index.resolveSpoken(['david louise'])?.id, 'david-luiz');
  });

  test('misheard surnames still resolve', () {
    expect(index.resolveSpoken(['van dyke'])?.id, 'virgil-van-dijk');
    expect(index.resolveSpoken(['kanty'])?.id, 'ngolo-kante');
    expect(index.resolveSpoken(['ibrahimovich'])?.id, 'zlatan');
  });

  test('filler words are ignored', () {
    expect(index.resolveSpoken(["um it's thierry henry"])?.id, 'thierry-henry');
  });

  test('mid-speech, only a complete name is accepted', () {
    expect(index.resolveSpoken(['thierry'], partial: true), isNull);
    expect(index.resolveSpoken(['thierry henry'], partial: true)?.id, 'thierry-henry');
    expect(index.resolveSpoken(['david louise'], partial: true)?.id, 'david-luiz');
  });

  test('ambiguous names are never auto-accepted', () {
    expect(index.resolveSpoken(['ronaldo']), isNull);
    expect(index.resolveSpoken(['david'], partial: true), isNull);
  });

  test('any alternative can settle it', () {
    expect(index.resolveSpoken(['ronaldo', 'cristiano ronaldo'])?.id, 'cristiano-ronaldo');
  });

  group('typed answers give nothing away', () {
    test('full name, nickname or surname is accepted', () {
      expect(index.matchTyped('Thierry Henry').map((p) => p.id), ['thierry-henry']);
      expect(index.matchTyped('henry').map((p) => p.id), ['thierry-henry']);
      expect(index.matchTyped('Zlatan').map((p) => p.id), ['zlatan']);
      expect(index.matchTyped('van dijk').map((p) => p.id), ['virgil-van-dijk']);
    });

    test('small spelling slips are fine', () {
      expect(index.matchTyped('ibrahimovich').map((p) => p.id), ['zlatan']);
      expect(index.matchTyped('kante').map((p) => p.id), ['ngolo-kante']);
    });

    test('partial words and first names get nothing', () {
      expect(index.matchTyped('sa'), isEmpty);
      expect(index.matchTyped('hen'), isEmpty);
      expect(index.matchTyped('thierry'), isEmpty);
      expect(index.isFirstNameOnly('thierry'), isTrue);
      expect(index.matchTyped('david'), isEmpty);
    });

    test('an ambiguous full answer lists only exact namesakes', () {
      expect(index.matchTyped('ronaldo').map((p) => p.id).toSet(), {'cristiano-ronaldo', 'ronaldo-nazario'});
    });
  });

  test('a first name alone is never accepted by voice either', () {
    expect(index.resolveSpoken(['thierry']), isNull);
  });

  test('spoken search lists the likely players for tapping', () {
    final ids = index.searchSpoken('ronaldo').map((m) => m.player.id).toSet();
    expect(ids, containsAll(['cristiano-ronaldo', 'ronaldo-nazario']));
  });

  group('names said the English way', () {
    test('sound keys match common mishearings', () {
      for (final (a, b) in const [
        ('shchesny', 'chesney'), ('odegaard', 'order guard'), ('urdegord', 'order guard'),
        ('tadic', 'tardich'), ('modric', 'modrich'), ('gerrard', 'gerard'), ('ibrahimovic', 'ibrahimovich'),
      ]) {
        expect(soundKey(a), soundKey(b), reason: '$a vs $b');
      }
    });

    final foreign = PlayerIndex(const [
      Player(id: 'szczesny', name: 'Wojciech Szczęsny', fame: 4, spoken: ['voychyeh shchesny']),
      Player(id: 'odegaard', name: 'Martin Ødegaard', fame: 4, spoken: ['martin urdegord']),
      Player(id: 'tadic', name: 'Dušan Tadić', fame: 3, spoken: ['dushan tadich']),
      Player(id: 'kane', name: 'Harry Kane', fame: 5),
    ]);

    test('the native-pronunciation respelling is matched', () {
      expect(foreign.resolveSpoken(['chesney'])?.id, 'szczesny');
      expect(foreign.resolveSpoken(['shezny'])?.id, 'szczesny');
      expect(foreign.resolveSpoken(['tardich'])?.id, 'tadic');
    });

    test('the English reading still works, even split into words', () {
      expect(foreign.resolveSpoken(['odegaard'])?.id, 'odegaard');
      expect(foreign.resolveSpoken(['order guard'])?.id, 'odegaard');
      expect(foreign.resolveSpoken(['harry kane'])?.id, 'kane');
    });

    test('bundled data carries respellings and finds them', () {
      final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
      expect(repo.players.byId('wojciech-szczesny')!.spoken, isNotEmpty);
      final hits = repo.players.searchSpoken('chesney', limit: 5).map((m) => m.player.id);
      expect(hits, contains('wojciech-szczesny'));
      expect(repo.players.searchSpoken('order guard', limit: 5).map((m) => m.player.id), contains('martin-odegaard'));
    });
  });
}
