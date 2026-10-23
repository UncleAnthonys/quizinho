import 'package:flutter_test/flutter_test.dart';
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

  test('spoken search lists the likely players for tapping', () {
    final ids = index.searchSpoken('ronaldo').map((m) => m.player.id).toSet();
    expect(ids, containsAll(['cristiano-ronaldo', 'ronaldo-nazario']));
  });
}
