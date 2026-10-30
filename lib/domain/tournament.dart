import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'game_mode.dart';
import 'warm_up_cup.dart';

enum MatchLength {
  short(4, 'Short', '4 rounds · ~20 min'),
  medium(6, 'Medium', '6 rounds · ~35 min'),
  long(9, 'Long', '9 rounds · ~50 min');

  const MatchLength(this.rounds, this.label, this.description);
  final int rounds;
  final String label;
  final String description;

  static MatchLength fromName(String? n) =>
      MatchLength.values.firstWhere((m) => m.name == n, orElse: () => MatchLength.medium);
}

class TeamSetup {
  TeamSetup({required this.name, required this.colorIndex, List<String>? players})
      : players = players ?? [];
  String name;
  int colorIndex;

  /// Optional individual names. Enables face-offs and Player of the Match.
  final List<String> players;
}

/// Two (or more) named players going head to head, one per team.
class FaceOff {
  const FaceOff(this.players);

  /// team index → player name
  final Map<int, String> players;
  String nameFor(int team) => players[team] ?? '';
}

class PlayerScore {
  const PlayerScore(this.team, this.name, this.points);
  final int team;
  final String name;
  final int points;
}

class TournamentConfig {
  TournamentConfig({
    required this.teams,
    this.length = MatchLength.medium,
    this.difficulty = Difficulty.medium,
    Set<GameModeId>? modes,
    this.questionsPerRound = 3,
    this.answerSeconds = 8,
    this.bombSeconds = 20,
    this.bombLives = 3,
    this.headsUpSeconds = 60,
    Set<Era>? eras,
    this.gender = FootballGender.men,
    this.warmUp = false,
  })  : modes = modes ?? {...GameModeId.concreteGames, GameModeId.wildcard},
        eras = (eras == null || eras.isEmpty) ? Era.values.toSet() : eras;

  final List<TeamSetup> teams;
  final MatchLength length;
  final Difficulty difficulty;

  /// Enabled wheel segments. May include [GameModeId.wildcard].
  final Set<GameModeId> modes;
  final int questionsPerRound;
  final int answerSeconds;
  final int bombSeconds;
  final int bombLives;
  final int headsUpSeconds;

  /// Eras the group wants questions from (all by default).
  final Set<Era> eras;
  int get eraMask => Era.maskOf(eras);

  /// Men's, women's or both — chosen on the home screen.
  final FootballGender gender;

  /// The free Warm-Up Cup: three fixed rounds of hand-picked challenges.
  final bool warmUp;

  /// The same teams in the Warm-Up Cup instead of the full game.
  TournamentConfig asWarmUp() => TournamentConfig(
        teams: teams,
        difficulty: Difficulty.easy,
        modes: WarmUpCup.games.toSet(),
        answerSeconds: answerSeconds,
        gender: FootballGender.men,
        warmUp: true,
      );
  int get genderMask => gender.mask;

  /// Women's-only drops games that have no women's questions yet.
  List<GameModeId> get enabledGames => GameModeId.concreteGames
      .where(modes.contains)
      .where((m) => gender != FootballGender.women || m.hasWomensGame)
      .toList();
}

/// Points a single round awarded, before any wildcard multiplier.
class RoundResult {
  RoundResult({required this.mode, required this.points, this.headline = ''});

  /// Nothing played — zero for everyone.
  factory RoundResult.empty(GameModeId mode, int teamCount) =>
      RoundResult(mode: mode, points: {for (var i = 0; i < teamCount; i++) i: 0});
  final GameModeId mode;

  /// team index → points earned this round
  final Map<int, int> points;
  final String headline;
}

class RoundRecord {
  RoundRecord(this.mode, this.points, this.multiplier, this.headline);
  final GameModeId mode;
  final Map<int, int> points; // after multiplier
  final int multiplier;
  final String headline;
}

/// One evening's competition: teams, running scores, rounds played, and
/// which challenges have been used (so nothing repeats).
class Tournament extends ChangeNotifier {
  Tournament(this.config, {Random? random})
      : _random = random ?? Random(),
        scores = List<int>.filled(config.teams.length, 0);

  final TournamentConfig config;
  final Random _random;
  final List<int> scores;
  final List<RoundRecord> rounds = [];
  final Map<GameModeId, Set<String>> _used = {};
  GameModeId? _lastGame;

  /// Phone lying flat between players: buzzer games draw sideways with a
  /// buzzer at each end. Chosen once, sticks for the match.
  bool _tableMode = false;
  bool get tableMode => _tableMode;
  set tableMode(bool on) {
    _tableMode = on;
    notifyListeners();
  }

  /// "team|name" → points scored personally (face-offs, bomb turns).
  final Map<String, int> _playerPoints = {};

  /// "team|name" → times picked, so face-offs rotate fairly.
  final Map<String, int> _picks = {};
  final Map<int, int> _turnIndex = {};

  /// Share of buzzer questions played as face-offs when names are set.
  static const double faceOffChance = 0.5;

  int get teamCount => config.teams.length;
  String teamName(int i) => config.teams[i].name;
  int get roundNumber => rounds.length + 1;
  int get totalRounds => config.warmUp ? WarmUpCup.games.length : config.length.rounds;
  bool get isFinished => rounds.length >= totalRounds;
  bool get isFinalRound => rounds.length == totalRounds - 1;

  // ---- saving, so a match survives the app being closed --------------------

  /// Everything needed to carry on this match later.
  Map<String, Object?> toJson() => {
        'config': {
          'teams': [
            for (final t in config.teams) {'name': t.name, 'color': t.colorIndex, 'players': t.players},
          ],
          'length': config.length.name,
          'difficulty': config.difficulty.name,
          'modes': [for (final m in config.modes) m.name],
          'questionsPerRound': config.questionsPerRound,
          'answerSeconds': config.answerSeconds,
          'bombSeconds': config.bombSeconds,
          'bombLives': config.bombLives,
          'headsUpSeconds': config.headsUpSeconds,
          'eras': config.eraMask,
          'gender': config.gender.name,
          'warmUp': config.warmUp,
        },
        'scores': scores,
        'rounds': [
          for (final r in rounds)
            {
              'mode': r.mode.name,
              'points': {for (final e in r.points.entries) '${e.key}': e.value},
              'multiplier': r.multiplier,
              'headline': r.headline,
            },
        ],
        'used': {for (final e in _used.entries) e.key.name: e.value.toList()},
        'lastGame': _lastGame?.name,
        'tableMode': _tableMode,
        'playerPoints': _playerPoints,
        'picks': _picks,
        'turnIndex': {for (final e in _turnIndex.entries) '${e.key}': e.value},
        'holds': _holds,
      };

  /// A match saved with [toJson]; null if it can't be read.
  static Tournament? fromJson(Map<String, Object?> j, {Random? random}) {
    try {
      final c = j['config']! as Map;
      final config = TournamentConfig(
        teams: [
          for (final t in c['teams'] as List)
            TeamSetup(
              name: '${(t as Map)['name']}',
              colorIndex: (t['color'] as num).toInt(),
              players: [for (final p in t['players'] as List) '$p'],
            ),
        ],
        length: MatchLength.fromName(c['length'] as String?),
        difficulty: Difficulty.fromName(c['difficulty'] as String?),
        modes: {for (final m in c['modes'] as List) if (GameModeId.fromName('$m') case final g?) g},
        questionsPerRound: (c['questionsPerRound'] as num).toInt(),
        answerSeconds: (c['answerSeconds'] as num).toInt(),
        bombSeconds: (c['bombSeconds'] as num).toInt(),
        bombLives: (c['bombLives'] as num).toInt(),
        headsUpSeconds: (c['headsUpSeconds'] as num).toInt(),
        eras: Era.fromMask((c['eras'] as num).toInt()),
        gender: FootballGender.fromName(c['gender'] as String?),
        warmUp: c['warmUp'] == true,
      );
      final t = Tournament(config, random: random);
      final sc = j['scores'] as List;
      for (var i = 0; i < t.scores.length && i < sc.length; i++) {
        t.scores[i] = (sc[i] as num).toInt();
      }
      for (final r in j['rounds'] as List) {
        final m = r as Map;
        final mode = GameModeId.fromName('${m['mode']}');
        if (mode == null) continue;
        t.rounds.add(RoundRecord(
          mode,
          {for (final e in (m['points'] as Map).entries) int.parse('${e.key}'): (e.value as num).toInt()},
          (m['multiplier'] as num).toInt(),
          '${m['headline'] ?? ''}',
        ));
      }
      for (final e in (j['used'] as Map? ?? const {}).entries) {
        final mode = GameModeId.fromName('${e.key}');
        if (mode != null) t._used[mode] = {for (final id in e.value as List) '$id'};
      }
      t._lastGame = j['lastGame'] == null ? null : GameModeId.fromName('${j['lastGame']}');
      t._tableMode = j['tableMode'] == true;
      Map<String, int> counts(Object? v) => {for (final e in (v as Map? ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
      t._playerPoints.addAll(counts(j['playerPoints']));
      t._picks.addAll(counts(j['picks']));
      t._holds.addAll(counts(j['holds']));
      for (final e in counts(j['turnIndex']).entries) {
        t._turnIndex[int.parse(e.key)] = e.value;
      }
      return t;
    } catch (_) {
      return null;
    }
  }

  Set<String> usedIds(GameModeId mode) => _used.putIfAbsent(mode, () => <String>{});
  void markUsed(GameModeId mode, String id) => usedIds(mode).add(id);

  /// Face-offs need at least one named player in every team.
  bool get hasPlayerNames => config.teams.every((t) => t.players.isNotEmpty);

  /// Every team is one person (a 1 v 1, names added for phone buzzers):
  /// face-offs and Player of the Match would just repeat the team result.
  bool get everyTeamSolo => config.teams.every((t) => t.players.length <= 1);

  static String _key(int team, String name) => '$team|$name';

  /// Least-picked player in [team] (random among ties); records the pick.
  String _pickPlayer(int team) {
    final names = config.teams[team].players;
    final fewest = names.map((n) => _picks[_key(team, n)] ?? 0).reduce(min);
    final options = names.where((n) => (_picks[_key(team, n)] ?? 0) == fewest).toList();
    final name = options[_random.nextInt(options.length)];
    _picks[_key(team, name)] = fewest + 1;
    return name;
  }

  /// Roll for a face-off on the next buzzer question. Null = whole-team question.
  FaceOff? maybeFaceOff() {
    if (!hasPlayerNames || everyTeamSolo || _random.nextDouble() >= faceOffChance) return null;
    return FaceOff({for (var t = 0; t < teamCount; t++) t: _pickPlayer(t)});
  }

  /// Next player in [team] for turn-based games, cycling in order. Null if no names.
  String? nextTurnPlayer(int team) {
    final names = config.teams[team].players;
    if (names.isEmpty) return null;
    final i = _turnIndex[team] ?? 0;
    _turnIndex[team] = i + 1;
    return names[i % names.length];
  }

  final Map<String, int> _holds = {};

  /// Who holds the phone next (Heads Up): random, but nobody goes twice until
  /// everyone in the team has had a go. Null if no names.
  String? fairRandomPlayer(int team) {
    final names = config.teams[team].players;
    if (names.isEmpty) return null;
    final fewest = names.map((n) => _holds[_key(team, n)] ?? 0).reduce(min);
    final options = names.where((n) => (_holds[_key(team, n)] ?? 0) == fewest).toList();
    final name = options[_random.nextInt(options.length)];
    _holds[_key(team, name)] = fewest + 1;
    return name;
  }

  void creditPlayer(int team, String name, int points) {
    if (name.isEmpty || points <= 0) return;
    _playerPoints[_key(team, name)] = (_playerPoints[_key(team, name)] ?? 0) + points;
  }

  /// Individual scores, best first.
  List<PlayerScore> get playerTable {
    final list = [
      for (final e in _playerPoints.entries)
        PlayerScore(int.parse(e.key.split('|').first), e.key.substring(e.key.indexOf('|') + 1), e.value),
    ]..sort((a, b) => b.points.compareTo(a.points));
    return list;
  }

  /// Wheel segments shown to players (enabled games, plus wildcard if on).
  List<GameModeId> get wheelSegments {
    final games = config.enabledGames;
    final segs = <GameModeId>[...games];
    if (config.modes.contains(GameModeId.wildcard) && games.isNotEmpty) segs.add(GameModeId.wildcard);
    return segs.isEmpty ? GameModeId.concreteGames : segs;
  }

  /// Picks where the wheel lands. Avoids the same game twice in a row when
  /// there is a choice, and never opens a match on the double-points wildcard.
  GameModeId spin() {
    if (config.warmUp) return WarmUpCup.games[min(rounds.length, WarmUpCup.games.length - 1)];
    var segs = wheelSegments;
    if (rounds.isEmpty && segs.length > 1) segs = segs.where((m) => m != GameModeId.wildcard).toList();
    final options = segs.length > 1 ? segs.where((m) => m != _lastGame).toList() : segs;
    final pick = options[_random.nextInt(options.length)];
    if (pick != GameModeId.wildcard) _lastGame = pick;
    return pick;
  }

  /// The real game behind a wildcard.
  GameModeId resolveWildcard() {
    final games = config.enabledGames.isEmpty ? GameModeId.concreteGames : config.enabledGames;
    final pick = games[_random.nextInt(games.length)];
    _lastGame = pick;
    return pick;
  }

  void recordRound(RoundResult result, {int multiplier = 1}) {
    final applied = <int, int>{};
    result.points.forEach((team, pts) {
      final p = pts * multiplier;
      scores[team] += p;
      applied[team] = p;
    });
    rounds.add(RoundRecord(result.mode, applied, multiplier, result.headline));
    notifyListeners();
  }

  /// Team indices, best first. Ties keep setup order.
  List<int> get standings {
    final idx = List<int>.generate(teamCount, (i) => i);
    idx.sort((a, b) {
      final c = scores[b].compareTo(scores[a]);
      return c != 0 ? c : a.compareTo(b);
    });
    return idx;
  }

  /// All teams sharing the top score (more than one = a draw).
  List<int> get leaders {
    final top = scores.reduce(max);
    return [for (var i = 0; i < teamCount; i++) if (scores[i] == top) i];
  }
}
