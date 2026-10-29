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

  bool Function(Player) answerIs(String id) => (p) => p.id == id;

  test('"david louise" is accepted as David Luiz when he is the answer', () {
    expect(index.resolveSpoken(['david louise'], isAnswer: answerIs('david-luiz'))?.id, 'david-luiz');
  });

  test('misheard surnames of the right answer still resolve', () {
    expect(index.resolveSpoken(['van dyke'], isAnswer: answerIs('virgil-van-dijk'))?.id, 'virgil-van-dijk');
    expect(index.resolveSpoken(['kanty'], isAnswer: answerIs('ngolo-kante'))?.id, 'ngolo-kante');
    expect(index.resolveSpoken(['ibrahimovich'], isAnswer: answerIs('zlatan'))?.id, 'zlatan');
  });

  test('real phone mishearings of the right answer go in', () {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    for (final (heard, id) in const [
      ('Voyce Chesney', 'wojciech-szczesny'), ('Martin Audiard', 'martin-odegaard'), ('Do Sam Tadić', 'dusan-tadic'),
      ('Pneumonia Vidić', 'nemanja-vidic'), ('Diane Loughran', 'dejan-lovren'), ('Pet check', 'petr-cech'),
      ('Golo Cante', 'ngolo-kante'), ('Olivia are rude', 'olivier-giroud'), ('Frankie Deon', 'frenkie-de-jong'),
      ('Busting shrine Steiger', 'bastian-schweinsteiger'), ('Tia Marie', 'thierry-henry'),
      ('Bouček Szczęsny', 'wojciech-szczesny'),
      ('Denver Ball', 'demba-ba'), ('Mediterranean', 'mehdi-taremi'), ('Juan Cano Canoe', 'nwankwo-kanu'),
    ]) {
      expect(repo.players.resolveSpoken([heard], isAnswer: (p) => p.id == id)?.id, id, reason: heard);
    }
  });

  test('a clear full name counts as a wrong answer; a lone sound-alike does not', () {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    bool kane(Player p) => p.id == 'harry-kane';
    expect(repo.players.resolveSpoken(['Virgil van Dyke'], isAnswer: kane)?.id, 'virgil-van-dijk');
    expect(repo.players.resolveSpoken(['Golo Cante'], isAnswer: kane), isNull);
    expect(repo.players.resolveSpoken(['Chesney'], isAnswer: kane), isNull);
    expect(repo.players.resolveSpoken(['Bouček Szczęsny'], isAnswer: kane), isNull);
    // A long-shot alternative never submits someone else.
    bool mignolet(Player p) => p.id == 'simon-mignolet';
    expect(repo.players.resolveSpoken(['Simonyan', 'Cemil', 'Seymour', 'Sio'], isAnswer: mignolet), isNull);
  });

  test('a sound-alike of a wrong player is never auto-submitted', () {
    // Shows the list to tap instead, so chatter can't cost a life.
    expect(index.resolveSpoken(['kanty'], isAnswer: answerIs('thierry-henry')), isNull);
    expect(index.resolveSpoken(['ibrahimovich'], isAnswer: answerIs('thierry-henry')), isNull);
    expect(index.searchSpoken('kanty').map((m) => m.player.id), contains('ngolo-kante'));
  });

  test('a wrong player said clearly does count', () {
    expect(index.resolveSpoken(['david luiz'], isAnswer: answerIs('thierry-henry'))?.id, 'david-luiz');
    expect(index.resolveSpoken(['kante'], isAnswer: answerIs('thierry-henry'))?.id, 'ngolo-kante');
  });

  test('rambling chatter never submits a wrong answer', () {
    expect(index.resolveSpoken(['no wait I think it might be david luiz or someone'], isAnswer: answerIs('thierry-henry')),
        isNull);
  });

  test('ambiguous names: the right one goes in, otherwise tap', () {
    expect(index.resolveSpoken(['ronaldo'], isAnswer: answerIs('cristiano-ronaldo'))?.id, 'cristiano-ronaldo');
    expect(index.resolveSpoken(['ronaldo'], isAnswer: answerIs('thierry-henry')), isNull);
  });

  test('filler words are ignored', () {
    expect(index.resolveSpoken(["um it's thierry henry"])?.id, 'thierry-henry');
  });

  test('mid-speech, only a complete name is accepted', () {
    expect(index.resolveSpoken(['thierry'], partial: true), isNull);
    expect(index.resolveSpoken(['thierry henry'], partial: true)?.id, 'thierry-henry');
    expect(index.resolveSpoken(['david louise'], partial: true, isAnswer: answerIs('david-luiz'))?.id, 'david-luiz');
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
      expect(foreign.resolveSpoken(['chesney'], isAnswer: answerIs('szczesny'))?.id, 'szczesny');
      expect(foreign.resolveSpoken(['shezny'], isAnswer: answerIs('szczesny'))?.id, 'szczesny');
      expect(foreign.resolveSpoken(['tardich'], isAnswer: answerIs('tadic'))?.id, 'tadic');
    });

    test('the English reading still works, even split into words', () {
      expect(foreign.resolveSpoken(['odegaard'])?.id, 'odegaard');
      expect(foreign.resolveSpoken(['order guard'], isAnswer: answerIs('odegaard'))?.id, 'odegaard');
      expect(foreign.resolveSpoken(['harry kane'])?.id, 'kane');
    });

    test('bundled data carries respellings and finds them', () {
      final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
      expect(repo.players.byId('wojciech-szczesny')!.spoken, isNotEmpty);
      final hits = repo.players.searchSpoken('chesney', limit: 5).map((m) => m.player.id);
      expect(hits, contains('wojciech-szczesny'));
      // In an Arsenal-keepers question he's the answer, so "chesney" lands on him.
      bool arsenalKeeper(Player p) => {'wojciech-szczesny', 'david-seaman', 'jens-lehmann'}.contains(p.id);
      expect(repo.players.resolveSpoken(['chesney'], isAnswer: arsenalKeeper)?.id, 'wojciech-szczesny');
      expect(repo.players.searchSpoken('order guard', limit: 5).map((m) => m.player.id), contains('martin-odegaard'));
    });
  });
}
