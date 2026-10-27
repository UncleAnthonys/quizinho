import '../domain/player_index.dart';
import 'models.dart';

/// Read-only access to football knowledge. Every game mode draws from here.
///
/// Implementations: [SqliteFootballRepository] in the app,
/// [InMemoryFootballRepository] in tests.
abstract class FootballRepository {
  PlayerIndex get players;

  /// Clubs, searchable like players — for categories whose answers are clubs.
  PlayerIndex get clubIndex;

  /// e.g. "demo_unverified" until the verified pipeline lands.
  String get dataStatus;

  /// Random challenge at one of [levels] (null = any level), from at least one
  /// of the [eras] (bit flags), whose ID is not in [exclude]. Null when the
  /// pool is exhausted.
  ///
  /// [genders]: men's (1), women's (2) or both (3) — see [FootballGender].
  Future<ClubConnection?> pickClubConnection(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1});
  Future<CareerPath?> pickCareerPath(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1});
  Future<HistoricMatch?> pickMatch(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1});

  Future<BiddingCategory?> pickBiddingCategory(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1});

  Future<CheckoutCategory?> pickCheckout(
      {Set<int>? levels, Set<String> exclude = const {}, int eras = Era.allMask, int genders = 1});

  /// Every club pairing with its answers (for grid games like Tic-Tac-Toe).
  Future<List<ClubConnection>> allClubConnections({int eras = Era.allMask, int genders = 1});
}

/// Applies difficulty and eras with a graceful fallback so a game doesn't
/// stall: chosen eras + difficulty → chosen eras, easier levels → any era at
/// the difficulty → any era, easier. Never harder than the chosen difficulty,
/// and the men's/women's choice is never widened.
class ChallengeSource {
  ChallengeSource(this.repo);
  final FootballRepository repo;

  Future<T?> _widen<T>(Difficulty d, int eras, Future<T?> Function(Set<int>? levels, int eras) pick) async =>
      await pick(d.allowedLevels, eras) ??
      await pick(d.atMostLevels, eras) ??
      await pick(d.allowedLevels, Era.allMask) ??
      await pick(d.atMostLevels, Era.allMask);

  Future<ClubConnection?> clubConnection(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _widen(d, eras, (l, e) => repo.pickClubConnection(levels: l, exclude: used, eras: e, genders: genders));

  Future<CareerPath?> careerPath(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _widen(d, eras, (l, e) => repo.pickCareerPath(levels: l, exclude: used, eras: e, genders: genders));

  Future<HistoricMatch?> match(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _widen(d, eras, (l, e) => repo.pickMatch(levels: l, exclude: used, eras: e, genders: genders));

  /// Pointless uses Bidding War's categories — ones with enough answers to
  /// spread the scores (6+), and that carry scores.
  Future<BiddingCategory?> pointless(Difficulty d, Set<String> used,
      {int eras = Era.allMask, int genders = 1}) async {
    final skip = {...used};
    for (var i = 0; i < 25; i++) {
      final b = await bidding(d, skip, eras: eras, genders: genders);
      if (b == null) return null;
      if (b.answerIds.length >= 6 && b.scores.isNotEmpty) return b;
      skip.add(b.id);
    }
    return null;
  }

  /// Football 501 has 2 levels: the giants (1) and other big clubs (2).
  Future<CheckoutCategory?> checkout(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _widen(
        d,
        eras,
        (l, e) => repo.pickCheckout(
            levels: l == null ? null : {for (final x in l) x > 2 ? 2 : x}, exclude: used, eras: e, genders: genders),
      );

  /// Bidding War has 3 levels; expert plays hard.
  Future<BiddingCategory?> bidding(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _widen(
        d,
        eras,
        (l, e) => repo.pickBiddingCategory(
            levels: l == null ? null : {for (final x in l) x > 3 ? 3 : x}, exclude: used, eras: e, genders: genders),
      );
}
