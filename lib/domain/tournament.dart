import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'game_mode.dart';

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
  TeamSetup({required this.name, required this.colorIndex});
  String name;
  int colorIndex;
}

class TournamentConfig {
  TournamentConfig({
    required this.teams,
    this.length = MatchLength.medium,
    this.difficulty = Difficulty.medium,
    Set<GameModeId>? modes,
    this.questionsPerRound = 3,
    this.answerSeconds = 15,
    this.bombSeconds = 20,
    this.bombLives = 3,
  }) : modes = modes ?? {...GameModeId.concreteGames, GameModeId.wildcard};

  final List<TeamSetup> teams;
  final MatchLength length;
  final Difficulty difficulty;

  /// Enabled wheel segments. May include [GameModeId.wildcard].
  final Set<GameModeId> modes;
  final int questionsPerRound;
  final int answerSeconds;
  final int bombSeconds;
  final int bombLives;

  List<GameModeId> get enabledGames =>
      GameModeId.concreteGames.where(modes.contains).toList();
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

  int get teamCount => config.teams.length;
  String teamName(int i) => config.teams[i].name;
  int get roundNumber => rounds.length + 1;
  int get totalRounds => config.length.rounds;
  bool get isFinished => rounds.length >= totalRounds;
  bool get isFinalRound => rounds.length == totalRounds - 1;

  Set<String> usedIds(GameModeId mode) => _used.putIfAbsent(mode, () => <String>{});
  void markUsed(GameModeId mode, String id) => usedIds(mode).add(id);

  /// Wheel segments shown to players (enabled games, plus wildcard if on).
  List<GameModeId> get wheelSegments {
    final games = config.enabledGames;
    final segs = <GameModeId>[...games];
    if (config.modes.contains(GameModeId.wildcard) && games.isNotEmpty) segs.add(GameModeId.wildcard);
    return segs.isEmpty ? GameModeId.concreteGames : segs;
  }

  /// Picks where the wheel lands. Avoids the same game twice in a row when
  /// there is a choice.
  GameModeId spin() {
    final segs = wheelSegments;
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
