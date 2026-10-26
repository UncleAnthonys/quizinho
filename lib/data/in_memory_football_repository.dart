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
    this.checkouts = const [],
    List<Club> clubs = const [],
    Random? random,
    this.dataStatus = 'test',
  })  : players = PlayerIndex(players),
        _clubs = clubs,
        _random = random ?? Random();

  @override
  final PlayerIndex players;
  @override
  final String dataStatus;

  final List<ClubConnection> connections;
  final List<CareerPath> careers;
  final List<HistoricMatch> matches;
  final List<BiddingCategory> bidding;
  final List<CheckoutCategory> checkouts;
  final List<Club> _clubs;
  final Random _random;

  @override
  late final PlayerIndex clubIndex = PlayerIndex([for (final c in _clubs) c.asAnswer]);

  T? _pick<T>(List<T> pool, String Function(T) id, int Function(T) level, int Function(T) era, Set<int>? levels,
      Set<String> exclude, int eras, bool Function(T) women, int genders) {
    final options = pool
        .where((x) =>
            !exclude.contains(id(x)) &&
            (levels == null || levels.contains(level(x))) &&
            (era(x) & eras) != 0 &&
            FootballGender.allows(genders, women(x)))
        .toList();
    if (options.isEmpty) return null;
    return options[_random.nextInt(options.length)];
  }

  @override
  Future<ClubConnection?> pickClubConnection(
          {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async =>
      _pick(connections, (c) => c.id, (c) => c.difficulty, (c) => c.eras, levels, exclude, eras, (c) => c.women, genders);

  @override
  Future<CareerPath?> pickCareerPath(
          {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async =>
      _pick(careers, (c) => c.id, (c) => c.difficulty, (c) => c.eras, levels, exclude, eras, (c) => c.women, genders);

  @override
  Future<HistoricMatch?> pickMatch(
          {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async =>
      _pick(matches, (m) => m.id, (m) => m.difficulty, (m) => m.eras, levels, exclude, eras, (m) => false, genders);

  @override
  Future<BiddingCategory?> pickBiddingCategory(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async {
    // Choose the kind of category by weight first, then one of that kind.
    bool fits(BiddingCategory b) =>
        !exclude.contains(b.id) &&
        (levels == null || levels.contains(b.difficulty)) &&
        (b.eras & eras) != 0 &&
        FootballGender.allows(genders, b.women);
    final kind = BiddingKind.choose({for (final b in bidding) if (fits(b)) b.kind}, _random);
    if (kind == null) return null;
    final options = [for (final b in bidding) if (b.kind == kind && fits(b)) b];
    return options[_random.nextInt(options.length)];
  }

  @override
  Future<CheckoutCategory?> pickCheckout(
          {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async =>
      _pick(checkouts, (c) => c.id, (c) => c.difficulty, (c) => c.eras, levels, exclude, eras, (c) => c.women, genders);

  @override
  Future<List<ClubConnection>> allClubConnections({int eras = Era.allMask, int genders = 1}) async =>
      [for (final c in connections) if ((c.eras & eras) != 0 && FootballGender.allows(genders, c.women)) c];
}
