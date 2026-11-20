import 'dart:math';

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

  /// Grid category x club pairs: clubA is the category ([gridCategory]),
  /// clubB the club, answers the players who fit both.
  Future<List<ClubConnection>> categoryClubPairs({int eras = Era.allMask, int genders = 1});

  /// A specific challenge by id (the hand-picked Warm-Up Cup). Null if gone.
  Future<ClubConnection?> clubConnectionById(String id);
  Future<CareerPath?> careerPathById(String playerId);
  Future<BiddingCategory?> biddingCategoryById(String id);
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
    // Nobody in the room has had it; then had by just one phone, two... (the
    // fewest first); then anything not already in this match.
    final counts = history.seenCounts(kind);
    final most = counts.values.fold(0, max);
    final tiers = [
      for (var k = 1; k <= most; k++) {...used, for (final e in counts.entries) if (e.value >= k) e.key},
      used,
    ];
    T? found;
    levels:
    for (final levels in [d.allowedLevels, d.atMostLevels]) {
      for (final exclude in tiers) {
        found = await pick(levels, eras, exclude) ?? await pick(levels, Era.allMask, exclude);
        if (found != null) break levels;
      }
    }
    if (found != null && record) history.add(kind, idOf(found));
    return found;
  }

  /// Hand-picked challenges (the Warm-Up Cup). Recorded as seen, so the full
  /// game doesn't serve them straight back.
  Future<ClubConnection?> fixedConnection(String id) async {
    final c = await repo.clubConnectionById(id);
    if (c != null) history.add('conn', c.id);
    return c;
  }

  Future<CareerPath?> fixedCareer(String playerId) async {
    final c = await repo.careerPathById(playerId);
    if (c != null) history.add('career', c.id);
    return c;
  }

  Future<BiddingCategory?> fixedBidding(String id) async {
    final b = await repo.biddingCategoryById(id);
    if (b != null) history.add('bidding', b.id);
    return b;
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

  /// Under the Radar uses Bidding War's categories with scores and plenty of
  /// answers ([pointlessMinAnswers]): a short list is all well-known names,
  /// with nothing obscure to dig for.
  Future<BiddingCategory?> pointless(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      bidding(d, used,
          eras: eras, genders: genders, where: (b) => b.answerIds.length >= pointlessMinAnswers && b.scores.isNotEmpty);

  static const pointlessMinAnswers = 10;

  /// Football 501 has 3 levels: British giants and the biggest clubs abroad
  /// (1), other British clubs (2), other clubs abroad (3).
  Future<CheckoutCategory?> checkout(Difficulty d, Set<String> used, {int eras = Era.allMask, int genders = 1}) =>
      _fresh(
        'checkout',
        d,
        used,
        eras,
        (l, e, x) => repo.pickCheckout(
            levels: l == null ? null : {for (final v in l) v > 3 ? 3 : v}, exclude: x, eras: e, genders: genders),
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
