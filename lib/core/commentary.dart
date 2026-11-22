import 'dart:math';

import '../domain/tournament.dart';
import '../games/buzz_race_controller.dart' show GameEvent;

/// Moments that get a pundit-style line in place of the usual one.
enum PunditMoment {
  /// Face-off: both missed an obvious one.
  faceOffMiss,

  /// A team tried and missed an obvious one.
  triedAndMissed,

  /// Nobody even tried an obvious one.
  nobodyTried,

  /// The same team wrong twice in a row.
  wrongAgain,
}

/// Original, generic "commentator" one-liners shown on screen.
/// Deliberately not modelled on any identifiable pundit. Voiced versions
/// (recorded by a voice actor) can be dropped in later keyed by the same events.
class Commentary {
  Commentary({Random? random}) : _random = random ?? Random();
  final Random _random;
  final Map<GameEvent, int> _last = {};

  /// Buzz-in reactions — shown on roughly a third of buzzes so they stay fun.
  static const _buzzLines = [
    'Oh, I’d LOVE it if they got this!',
    'They’ve gone early! Brave, brave stuff.',
    'Confidence! I like it.',
    'Here we go… don’t bottle it!',
    'Fortune favours the brave!',
    'Big moment. BIG moment.',
  ];

  String? maybeBuzzLine() {
    if (_random.nextDouble() > 0.35) return null;
    return _buzzLines[_random.nextInt(_buzzLines.length)];
  }

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
      'An absolute anorak - and I mean that as a compliment.',
      'Ooh, you beauty! What a hit, son, what a hit!',
      'Unbelievable, Jeff!',
      'Proper cold Tuesday night in Stoke knowledge.',
      'Someone’s got a Panini sticker album at home.',
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
      'That’s gone straight into Row Z.',
      'VAR’s had a look… still wrong.',
      'He’s left his shooting boots in the car.',
      'Hairdryer treatment incoming.',
    ],
    GameEvent.timeUp: [
      'Frozen like a rabbit in the headlights.',
      'The clock waits for no one.',
      'Bottled it.',
      'Like a keeper rooted to his line.',
      'Buffering… buffering…',
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

  static const Map<PunditMoment, List<String>> _moments = {
    PunditMoment.faceOffMiss: ['Leave the football before the football leaves you… the football’s left him.'],
    PunditMoment.triedAndMissed: ['The game’s gone.'],
    PunditMoment.nobodyTried: ['That is a bad one.'],
    PunditMoment.wrongAgain: [
      'It can’t go on like this, can it?',
      'Is it too late to sell them in January?',
      'Sacked in the morning, you’re getting sacked in the morning.',
    ],
  };

  String moment(PunditMoment m) => _pick(_moments[m]!);

  /// A right answer with the clock nearly gone (3 seconds or less).
  String late() => _pick(const ['AGÜEROOOOO!', 'Fergie time!']);

  /// The first right answer of the match.
  String first() => _pick(const ['Early doors!', 'Remember the name!']);

  /// The teaser got at full time's last chance.
  static const lastChance = 'Cometh the hour, cometh the man.';

  /// After a round, on the table: the moment of the match, if there is one.
  /// Final round: won by the team already ahead, or by a team that wasn't
  /// and it's won them the match. Otherwise a thrashing, the bottom team
  /// winning, or one round left with it tight at the top.
  String? afterRound(Tournament t) {
    if (t.rounds.isEmpty || t.teamCount < 2) return null;
    final pts = t.rounds.last.points;
    final n = t.teamCount;
    final before = [for (var i = 0; i < n; i++) t.scores[i] - (pts[i] ?? 0)];
    final got = [for (var i = 0; i < n; i++) pts[i] ?? 0];
    final best = got.reduce(max);
    final roundWinners = [for (var i = 0; i < n; i++) if (got[i] == best) i];
    final w = best > 0 && roundWinners.length == 1 ? roundWinners.single : null;
    bool aheadOfAll(List<int> v, int team) => [for (var i = 0; i < n; i++) if (i != team) v[i]].every((x) => x < v[team]);
    bool behindAll(List<int> v, int team) => [for (var i = 0; i < n; i++) if (i != team) v[i]].every((x) => x > v[team]);
    if (w != null && t.isFinished) {
      if (aheadOfAll(before, w)) return 'They think it’s all over… it is now!';
      if (aheadOfAll(t.scores, w)) return 'And Solskjær has won it!';
    }
    if (w != null) {
      final second = [for (var i = 0; i < n; i++) if (i != w) got[i]].reduce(max);
      if (best - second >= thrashing) return 'Your boys took a hell of a beating!';
      if (behindAll(before, w)) return 'It’s a funny old game.';
    }
    if (t.rounds.length == t.totalRounds - 1) {
      final sorted = [...t.scores]..sort((a, b) => b.compareTo(a));
      if (sorted[0] - sorted[1] <= 3) return 'Squeaky bum time.';
    }
    return null;
  }

  /// A round won by this many points or more is a thrashing.
  static const thrashing = 6;

  String _pick(List<String> l) => l[_random.nextInt(l.length)];

  static const winnerLines = [
    'Champions! Get the open-top bus booked.',
    'Lift that trophy!',
    'They’ll be singing about this one for years.',
  ];
  static const drawLines = [
    'All square! Honours even - for now.',
    'Nothing to separate them. Rematch?',
    'Honours even. Nobody’s happy.',
  ];

  String winner({required bool draw}) {
    final l = draw ? drawLines : winnerLines;
    return l[_random.nextInt(l.length)];
  }
}
