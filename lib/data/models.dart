/// Plain data objects shared by every game mode. No Flutter imports, so the
/// game logic built on them is unit-testable.
library;

/// 1 = easy, 4 = expert. Stored as an int in the database.
enum Difficulty {
  easy(1, 'Easy'),
  medium(2, 'Medium'),
  hard(3, 'Hard'),
  expert(4, 'Expert');

  const Difficulty(this.level, this.label);
  final int level;
  final String label;

  /// Challenge difficulty levels that may be served at this setting.
  /// Overlapping bands keep the pool large on a small database.
  Set<int> get allowedLevels => switch (this) {
        Difficulty.easy => {1},
        Difficulty.medium => {1, 2},
        Difficulty.hard => {2, 3},
        Difficulty.expert => {3, 4},
      };

  static Difficulty fromName(String? name) =>
      Difficulty.values.firstWhere((d) => d.name == name, orElse: () => Difficulty.medium);
}

class Club {
  const Club({required this.id, required this.name, required this.fame, this.country});
  final String id;
  final String name;
  final String? country;
  final int fame;
}

class Player {
  const Player({
    required this.id,
    required this.name,
    required this.fame,
    this.aliases = const [],
    this.position,
    this.nationality,
    this.verified = false,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final int fame;
  final String? position;
  final String? nationality;
  final bool verified;
}

class CareerSpell {
  const CareerSpell({
    required this.club,
    this.startYear,
    this.endYear,
    this.isLoan = false,
  });

  final Club club;
  final int? startYear;
  final int? endYear;
  final bool isLoan;

  String get yearsLabel {
    if (startYear == null) return '';
    if (endYear == null) return '$startYear–';
    if (endYear == startYear) return '$startYear';
    return '$startYear–$endYear';
  }
}

/// "Name a player who played for both A and B."
class ClubConnection {
  const ClubConnection({
    required this.id,
    required this.clubA,
    required this.clubB,
    required this.answerIds,
    required this.difficulty,
  });

  final String id;
  final Club clubA;
  final Club clubB;

  /// Every player ID in the database who played for both clubs.
  /// Never empty — the pipeline refuses to generate a pair without one.
  final Set<String> answerIds;
  final int difficulty;
}

/// "Who's this? Ajax → Juventus → Inter…"
class CareerPath {
  const CareerPath({required this.player, required this.spells, required this.difficulty});
  final Player player;
  final List<CareerSpell> spells;
  final int difficulty;

  String get id => player.id;
}

class LineupSlot {
  const LineupSlot({required this.index, required this.playerId, required this.playerName, required this.position});
  final int index;
  final String playerId;
  final String playerName;
  final String position;

  /// 0 = GK, 1 = defence, 2 = midfield, 3 = attack. Used to draw the formation.
  int get line => switch (position) {
        'GK' => 0,
        'RB' || 'CB' || 'LB' => 1,
        'RWB' || 'LWB' || 'DM' || 'CM' || 'RM' || 'LM' => 2,
        _ => 3,
      };
}

class HistoricMatch {
  const HistoricMatch({
    required this.id,
    required this.title,
    required this.competition,
    required this.date,
    required this.home,
    required this.away,
    required this.score,
    required this.targetTeam,
    required this.lineup,
    required this.difficulty,
    this.verified = false,
  });

  final String id;
  final String title;
  final String competition;
  final String date;
  final String home;
  final String away;
  final String score;

  /// The side whose XI the players must name.
  final String targetTeam;
  final List<LineupSlot> lineup;
  final int difficulty;
  final bool verified;

  int get year => int.tryParse(date.split('-').first) ?? 0;
}
