import 'dart:math';

import '../domain/player_index.dart';
import 'football_repository.dart';
import 'models.dart';

/// Fully in-memory repository. Used by tests, and handy for previews.
class InMemoryFootballRepository implements FootballRepository {
  InMemoryFootballRepository({
    required List<Player> players,
    this.connections = const [],
    this.categoryPairs = const [],
    this.careers = const [],
    this.matches = const [],
    this.bidding = const [],
    this.checkouts = const [],
    this.hatTricks = const [],
    this.clubRosters = const {},
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
  final List<ClubConnection> categoryPairs;
  final List<CareerPath> careers;
  final List<HistoricMatch> matches;
  final List<BiddingCategory> bidding;
  final List<CheckoutCategory> checkouts;
  final List<HatTrickSet> hatTricks;

  /// Club id -> every player who played there: fills in a Hat-Trick set's
  /// [HatTrickSet.played] when it's picked (the web data). Sets that come
  /// with it already (tests) are used as they are.
  final Map<String, List<String>> clubRosters;
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
          {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1}) async {
    if (!FootballGender.allows(genders, false)) return null; // line-ups are men's only so far
    final options = [
      for (final m in matches)
        if (!exclude.contains(m.id) && (levels == null || levels.contains(m.difficulty)) && (m.eras & eras) != 0) m
    ];
    return options.isEmpty ? null : HistoricMatch.weightedPick<HistoricMatch>(options, (m) => m.weight, _random);
  }

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
  Future<HatTrickSet?> pickHatTrick({Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask}) async {
    final h = _pick(hatTricks, (h) => h.id, (h) => h.difficulty, (h) => h.eras, levels, exclude, eras, (h) => false, 1);
    if (h == null || h.played.isNotEmpty) return h;
    final played = <String, int>{};
    for (final (i, c) in h.clubs.indexed) {
      for (final pid in clubRosters[c.id] ?? const <String>[]) {
        played[pid] = (played[pid] ?? 0) | (1 << i);
      }
    }
    return HatTrickSet(id: h.id, clubs: h.clubs, played: played, difficulty: h.difficulty, eras: h.eras);
  }

  @override
  Future<List<ClubConnection>> allClubConnections({int eras = Era.allMask, int genders = 1}) async =>
      [for (final c in connections) if ((c.eras & eras) != 0 && FootballGender.allows(genders, c.women)) c];

  @override
  Future<List<ClubConnection>> categoryClubPairs({int eras = Era.allMask, int genders = 1}) async =>
      [for (final c in categoryPairs) if ((c.eras & eras) != 0 && FootballGender.allows(genders, c.women)) c];

  @override
  Future<ClubConnection?> clubConnectionById(String id) async => connections.where((c) => c.id == id).firstOrNull;

  @override
  Future<CareerPath?> careerPathById(String playerId) async => careers.where((c) => c.id == playerId).firstOrNull;

  @override
  Future<BiddingCategory?> biddingCategoryById(String id) async => bidding.where((b) => b.id == id).firstOrNull;
}
