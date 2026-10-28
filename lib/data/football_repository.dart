import '../domain/player_index.dart';
import 'models.dart';
import 'question_history.dart';

export 'question_history.dart';

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
/// stall, and keeps questions fresh: something this phone hasn't been asked
/// before ([history]) comes first, at the right level; a repeat only when
/// that level has run dry; easier levels after that. Never harder than the
/// chosen difficulty, and the men's/women's choice is never widened.
class ChallengeSource {
  ChallengeSource(this.repo, {QuestionHistory? history}) : history = history ?? QuestionHistory();
  final FootballRepository repo;
  final QuestionHistory history;

  Future<T?> _fresh<T>(
    String kind,
    Difficulty d,
    Set<String> used,
    int eras,
    Future<T?> Function(Set<int>? levels, int eras, Set<String> exclude) pick,
    String Function(T) idOf, {
    bool record = true,
  }) async {
    final unseen = {...used, ...history.seen(kind)};
    T? found;
    for (final levels in [d.allowedLevels, d.atMostLevels]) {
      found = await pick(levels, eras, unseen) ??
          await pick(levels, Era.allMask, unseen) ??
          await pick(levels, eras, used) ??
          await pick(levels, Era.allMask, used);
      if (found != null) break;
    }
    if (found != null && record) history.add(kind, idOf(found));
    return found;
  }

  Future<ClubConnection?> clubConnection(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _fresh('conn', d, used, eras,
          (l, e, x) => repo.pickClubConnection(levels: l, exclude: x, eras: e, genders: genders), (c) => c.id);

  Future<CareerPath?> careerPath(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _fresh('career', d, used, eras,
          (l, e, x) => repo.pickCareerPath(levels: l, exclude: x, eras: e, genders: genders), (c) => c.id);

  Future<HistoricMatch?> match(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _fresh('match', d, used, eras, (l, e, x) => repo.pickMatch(levels: l, exclude: x, eras: e, genders: genders),
          (m) => m.id);

  /// Pointless uses Bidding War's categories — ones with enough answers to
  /// spread the scores (6+), and that carry scores.
  Future<BiddingCategory?> pointless(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      bidding(d, used, eras: eras, genders: genders, where: (b) => b.answerIds.length >= 6 && b.scores.isNotEmpty);

  /// Football 501 has 2 levels: the giants (1) and other big clubs (2).
  Future<CheckoutCategory?> checkout(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _fresh(
        'checkout',
        d,
        used,
        eras,
        (l, e, x) => repo.pickCheckout(
            levels: l == null ? null : {for (final v in l) v > 2 ? 2 : v}, exclude: x, eras: e, genders: genders),
        (c) => c.id,
      );

  /// Bidding War has 3 levels; expert plays hard. [where] narrows the
  /// categories (Pointless needs scores; Survival skips club pairs).
  Future<BiddingCategory?> bidding(Difficulty d, Set<String> used,
      {int eras = Era.allMask, int genders = 1, bool Function(BiddingCategory)? where}) async {
    final rejected = <String>{};
    for (var i = 0; i < 25; i++) {
      final b = await _fresh(
        'bidding',
        d,
        {...used, ...rejected},
        eras,
        (l, e, x) => repo.pickBiddingCategory(
            levels: l == null ? null : {for (final v in l) v > 3 ? 3 : v}, exclude: x, eras: e, genders: genders),
        (b) => b.id,
        record: false,
      );
      if (b == null) return null;
      if (where == null || where(b)) {
        history.add('bidding', b.id);
        return b;
      }
      rejected.add(b.id);
    }
    return null;
  }
}
