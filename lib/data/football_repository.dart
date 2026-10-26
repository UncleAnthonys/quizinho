import '../domain/player_index.dart';
import 'models.dart';

/// Read-only access to football knowledge. Every game mode draws from here.
///
/// Implementations: [SqliteFootballRepository] in the app,
/// [InMemoryFootballRepository] in tests.
abstract class FootballRepository {
  PlayerIndex get players;

  /// e.g. "demo_unverified" until the verified pipeline lands.
  String get dataStatus;

  /// Random challenge at one of [levels] (null = any level), from at least one
  /// of the [eras] (bit flags), whose ID is not in [exclude]. Null when the
  /// pool is exhausted.
  Future<ClubConnection?> pickClubConnection(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask});
  Future<CareerPath?> pickCareerPath({Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask});
  Future<HistoricMatch?> pickMatch({Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask});

  Future<BiddingCategory?> pickBiddingCategory(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask});

  /// Every club pairing with its answers (for grid games like Tic-Tac-Toe).
  Future<List<ClubConnection>> allClubConnections({int eras = Era.allMask});
}

/// Applies difficulty and eras with a graceful fallback, so a game never
/// stalls or repeats: chosen eras + difficulty → chosen eras, any difficulty →
/// any era at the difficulty → anything fresh.
class ChallengeSource {
  ChallengeSource(this.repo);
  final FootballRepository repo;

  Future<T?> _widen<T>(Difficulty d, int eras, Future<T?> Function(Set<int>? levels, int eras) pick) async =>
      await pick(d.allowedLevels, eras) ??
      await pick(null, eras) ??
      await pick(d.allowedLevels, Era.allMask) ??
      await pick(null, Era.allMask);

  Future<ClubConnection?> clubConnection(Difficulty d, Set<String> used, {int eras = Era.allMask}) =>
      _widen(d, eras, (l, e) => repo.pickClubConnection(levels: l, exclude: used, eras: e));

  Future<CareerPath?> careerPath(Difficulty d, Set<String> used, {int eras = Era.allMask}) =>
      _widen(d, eras, (l, e) => repo.pickCareerPath(levels: l, exclude: used, eras: e));

  Future<HistoricMatch?> match(Difficulty d, Set<String> used, {int eras = Era.allMask}) =>
      _widen(d, eras, (l, e) => repo.pickMatch(levels: l, exclude: used, eras: e));

  /// Bidding War has 3 levels; expert plays hard.
  Future<BiddingCategory?> bidding(Difficulty d, Set<String> used, {int eras = Era.allMask}) => _widen(
        d,
        eras,
        (l, e) => repo.pickBiddingCategory(levels: l == null ? null : {for (final x in l) x > 3 ? 3 : x}, exclude: used, eras: e),
      );
}
