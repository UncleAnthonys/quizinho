/// Plain data objects shared by every game mode. No Flutter imports, so the
/// game logic built on them is unit-testable.
library;

import 'dart:math';

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

/// Football eras the group can include or leave out. Bit values must match
/// ERAS in data_pipeline/build_db.py.
enum Era {
  classic(1, 'Pre-92'),
  nineties(2, '92–99'),
  noughties(4, '2000s'),
  tens(8, '2010s'),
  twenties(16, '2020s');

  const Era(this.bit, this.label);
  final int bit;
  final String label;

  static const int allMask = 31;

  static int maskOf(Iterable<Era> eras) => eras.fold(0, (m, e) => m | e.bit);
  static Set<Era> fromMask(int mask) => {for (final e in values) if (mask & e.bit != 0) e};
}

class Club {
  const Club({
    required this.id,
    required this.name,
    required this.fame,
    this.country,
    this.aliases = const [],
    this.women = false,
  });

  /// A women's team ("Arsenal Women").
  final bool women;
  final String id;
  final String name;
  final String? country;
  final int fame;

  /// Nicknames a player might type ("Spurs", "Man Utd").
  final List<String> aliases;

  /// As an answer entry, so the same type-or-say box can search clubs.
  Player get asAnswer => Player(id: id, name: name, fame: fame, aliases: aliases, nationality: country);
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
    this.women = false,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final int fame;
  final String? position;
  final String? nationality;
  final bool verified;

  /// Plays in the women's game.
  final bool women;
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
    this.eras = Era.allMask,
  });

  final String id;
  final Club clubA;
  final Club clubB;

  /// Every player ID in the database who played for both clubs.
  /// Never empty — the pipeline refuses to generate a pair without one.
  final Set<String> answerIds;
  final int difficulty;

  /// Women's clubs (a pair is never mixed).
  bool get women => clubA.women;

  /// Era bit flags in which a valid answer was at one of these clubs.
  final int eras;
}

/// Bidding War: a category with its complete, verified answer set.
class BiddingCategory {
  const BiddingCategory({
    required this.id,
    required this.prompt,
    required this.answerIds,
    required this.difficulty,
    this.eras = Era.allMask,
    this.scores = const {},
    this.women = false,
  });
  final String id;

  /// Pointless: 0-100 per answer — how many of 100 people would say it,
  /// estimated from how well known each answer is (0 = pointless).
  final Map<String, int> scores;

  /// Answers are from the women's game.
  final bool women;

  /// e.g. "Players who played for both Arsenal and Barcelona".
  final String prompt;
  final Set<String> answerIds;

  /// 1 easy … 3 hard (by how many answers fans would recognise).
  final int difficulty;
  final int eras;

  /// Nobody can bid more answers than exist.
  int get maxBid => answerIds.length;

  /// Which family the category comes from, told by its id prefix.
  BiddingKind get kind => BiddingKind.ofId(id);

  /// Answers are clubs ("Clubs that have won the Premier League"), not people.
  bool get answersAreClubs => id.startsWith('clubs:');
}

/// Men's football, women's, or both — bit flags like eras (1 men, 2 women).
enum FootballGender {
  men(1, "Men's"),
  both(3, 'Both'),
  women(2, "Women's");

  const FootballGender(this.mask, this.label);
  final int mask;
  final String label;

  static const int menBit = 1, womenBit = 2;

  /// Does a challenge from the women's (or men's) game fit [mask]?
  static bool allows(int mask, bool women) => (mask & (women ? womenBit : menBit)) != 0;

  static FootballGender fromName(String? name) =>
      values.firstWhere((g) => g.name == name, orElse: () => FootballGender.men);
}

/// Bidding War category families, and how often each comes up. The pipeline
/// makes 1,000+ club pairs but only a few dozen hand-made records/squads, so
/// picking uniformly would almost never show the hand-made ones.
enum BiddingKind {
  curated(40), // hand-made: records, awards, managers, clubs ("Top 10 PL scorers")
  pair(40), // "Played for both Arsenal and Barcelona"
  nationality(20); // "Brazilians who played for Chelsea"

  const BiddingKind(this.weight);
  final int weight;

  static BiddingKind ofId(String id) => id.startsWith('stat:') || id.startsWith('clubs:')
      ? curated
      : id.startsWith('nat:')
          ? nationality
          : pair;

  /// Picks a kind by weight among those that have something on offer.
  static BiddingKind? choose(Set<BiddingKind> available, Random random) {
    final kinds = [for (final k in values) if (available.contains(k)) k];
    if (kinds.isEmpty) return null;
    var roll = random.nextInt(kinds.fold(0, (sum, k) => sum + k.weight));
    for (final k in kinds) {
      roll -= k.weight;
      if (roll < 0) return k;
    }
    return kinds.last;
  }
}

/// "Who's this? Ajax → Juventus → Inter…"
class CareerPath {
  const CareerPath({required this.player, required this.spells, required this.difficulty, this.eras = Era.allMask});
  final Player player;
  final List<CareerSpell> spells;
  final int difficulty;

  /// Era bit flags the career touches.
  final int eras;

  String get id => player.id;
  bool get women => player.women;
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
    this.eras = Era.allMask,
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

  /// Era bit flag of the match date.
  final int eras;

  int get year => int.tryParse(date.split('-').first) ?? 0;
}
