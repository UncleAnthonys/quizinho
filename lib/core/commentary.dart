import 'dart:math';

import '../games/buzz_race_controller.dart' show GameEvent;

/// Original, generic "commentator" one-liners shown on screen.
/// Deliberately not modelled on any identifiable pundit. Voiced versions
/// (recorded by a voice actor) can be dropped in later keyed by the same events.
class Commentary {
  Commentary({Random? random}) : _random = random ?? Random();
  final Random _random;
  final Map<GameEvent, int> _last = {};

  static const Map<GameEvent, List<String>> _lines = {
    GameEvent.correct: [
      'Lovely stuff.',
      'Textbook. Absolutely textbook.',
      'Ice in the veins!',
      'Never in doubt.',
      'Top bins.',
    ],
    GameEvent.deepCut: [
      'Where on earth did THAT come from?!',
      'Proper football knowledge, that.',
      'Somebody’s done their homework!',
      'An absolute anorak — and I mean that as a compliment.',
    ],
    GameEvent.steal: [
      'Daylight robbery!',
      'Pinched it from under their noses!',
      'Smash and grab!',
    ],
    GameEvent.wrong: [
      'Oh dear. Oh dear oh dear.',
      'That’s nowhere near.',
      'Not even in the same postcode.',
      'Swing and a miss.',
    ],
    GameEvent.timeUp: [
      'Frozen like a rabbit in the headlights.',
      'The clock waits for no one.',
      'Bottled it.',
    ],
    GameEvent.nobodyGotIt: [
      'Nobody? Not one of you?',
      'Tumbleweed.',
      'I’ve seen better from the Sunday league.',
    ],
    GameEvent.explode: [
      'BOOM. That’s gone off.',
      'Kaboom! Get the physio on.',
      'Blown it. Literally.',
    ],
    GameEvent.eliminated: [
      'They’re out! Pack the kit bag.',
      'And that’s curtains for them.',
      'Early bath!',
    ],
    GameEvent.complete: [
      'Full team sheet! Frame it.',
      'Every name on the board!',
    ],
  };

  String? lineFor(GameEvent e) {
    final options = _lines[e];
    if (options == null || options.isEmpty) return null;
    var i = _random.nextInt(options.length);
    if (options.length > 1 && i == _last[e]) i = (i + 1) % options.length;
    _last[e] = i;
    return options[i];
  }

  static const winnerLines = [
    'Champions! Get the open-top bus booked.',
    'Lift that trophy!',
    'They’ll be singing about this one for years.',
  ];
  static const drawLines = [
    'All square! Honours even — for now.',
    'Nothing to separate them. Rematch?',
  ];

  String winner({required bool draw}) {
    final l = draw ? drawLines : winnerLines;
    return l[_random.nextInt(l.length)];
  }
}
