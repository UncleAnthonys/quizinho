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
    this.bidding = const [],
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
  final List<BiddingCategory> bidding;
  final Random _random;

  T? _pick<T>(List<T> pool, String Function(T) id, int Function(T) level, int Function(T) era, Set<int>? levels,
      Set<String> exclude, int eras) {
    final options = pool
        .where((x) =>
            !exclude.contains(id(x)) && (levels == null || levels.contains(level(x))) && (era(x) & eras) != 0)
        .toList();
    if (options.isEmpty) return null;
    return options[_random.nextInt(options.length)];
  }

  @override
  Future<ClubConnection?> pickClubConnection(
          {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask}) async =>
      _pick(connections, (c) => c.id, (c) => c.difficulty, (c) => c.eras, levels, exclude, eras);

  @override
  Future<CareerPath?> pickCareerPath({Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask}) async =>
      _pick(careers, (c) => c.id, (c) => c.difficulty, (c) => c.eras, levels, exclude, eras);

  @override
  Future<HistoricMatch?> pickMatch({Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask}) async =>
      _pick(matches, (m) => m.id, (m) => m.difficulty, (m) => m.eras, levels, exclude, eras);

  @override
  Future<BiddingCategory?> pickBiddingCategory(
          {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask}) async =>
      _pick(bidding, (b) => b.id, (b) => b.difficulty, (b) => b.eras, levels, exclude, eras);

  @override
  Future<List<ClubConnection>> allClubConnections({int eras = Era.allMask}) async =>
      [for (final c in connections) if ((c.eras & eras) != 0) c];
}
