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

  /// Random challenge at one of [levels] (null = any level) whose ID is not in
  /// [exclude]. Returns null when the pool is exhausted.
  Future<ClubConnection?> pickClubConnection({Set<int>? levels, Set<String> exclude = const {}});
  Future<CareerPath?> pickCareerPath({Set<int>? levels, Set<String> exclude = const {}});
  Future<HistoricMatch?> pickMatch({Set<int>? levels, Set<String> exclude = const {}});
}

/// Applies difficulty with a graceful fallback: if nothing fresh is left at the
/// chosen difficulty, serve something fresh at any difficulty rather than
/// repeating or stalling the game.
class ChallengeSource {
  ChallengeSource(this.repo);
  final FootballRepository repo;

  Future<ClubConnection?> clubConnection(Difficulty d, Set<String> used) async =>
      await repo.pickClubConnection(levels: d.allowedLevels, exclude: used) ??
      await repo.pickClubConnection(exclude: used);

  Future<CareerPath?> careerPath(Difficulty d, Set<String> used) async =>
      await repo.pickCareerPath(levels: d.allowedLevels, exclude: used) ??
      await repo.pickCareerPath(exclude: used);

  Future<HistoricMatch?> match(Difficulty d, Set<String> used) async =>
      await repo.pickMatch(levels: d.allowedLevels, exclude: used) ??
      await repo.pickMatch(exclude: used);
}
