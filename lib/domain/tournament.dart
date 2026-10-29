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

  Set<String> usedIds(GameModeId mode) => _used.putIfAbsent(mode, () => <String>{});
  void markUsed(GameModeId mode, String id) => usedIds(mode).add(id);

  /// Face-offs need at least one named player in every team.
  bool get hasPlayerNames => config.teams.every((t) => t.players.isNotEmpty);

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
    if (!hasPlayerNames || _random.nextDouble() >= faceOffChance) return null;
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
