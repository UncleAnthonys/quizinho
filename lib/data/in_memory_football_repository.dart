import 'dart:math';

import '../domain/player_index.dart';
import 'football_repository.dart';
import 'models.dart';

/// Fully in-memory repository. Used by tests, and handy for previews.
class InMemoryFootballRepository implements FootballRepository {
  InMemoryFootballRepository({
    required List<Player> players,
    this.connections = const [],
    this.careers = const [],
    this.matches = const [],
    Random? random,
    this.dataStatus = 'test',
  })  : players = PlayerIndex(players),
        _random = random ?? Random();

  @override
  final PlayerIndex players;
  @override
  final String dataStatus;

  final List<ClubConnection> connections;
  final List<CareerPath> careers;
  final List<HistoricMatch> matches;
  final Random _random;

  T? _pick<T>(List<T> pool, String Function(T) id, int Function(T) level, Set<int>? levels, Set<String> exclude) {
    final options = pool
        .where((x) => !exclude.contains(id(x)) && (levels == null || levels.contains(level(x))))
        .toList();
    if (options.isEmpty) return null;
    return options[_random.nextInt(options.length)];
  }

  @override
  Future<ClubConnection?> pickClubConnection({Set<int>? levels, Set<String> exclude = const {}}) async =>
      _pick(connections, (c) => c.id, (c) => c.difficulty, levels, exclude);

  @override
  Future<CareerPath?> pickCareerPath({Set<int>? levels, Set<String> exclude = const {}}) async =>
      _pick(careers, (c) => c.id, (c) => c.difficulty, levels, exclude);

  @override
  Future<HistoricMatch?> pickMatch({Set<int>? levels, Set<String> exclude = const {}}) async =>
      _pick(matches, (m) => m.id, (m) => m.difficulty, levels, exclude);
}
