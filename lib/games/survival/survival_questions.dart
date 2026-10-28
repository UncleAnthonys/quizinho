import 'dart:math';

import '../../data/football_repository.dart';
import '../../data/models.dart';
import 'survival_controller.dart';

/// Turns the party games' questions into one-answer Survival questions:
/// club connections, career paths, line-ups and categories, mixed at random.
class SurvivalQuestions {
  SurvivalQuestions(this.source, {required this.genders, this.seenBefore = const {}, Random? random})
      : _random = random ?? Random();

  final ChallengeSource source;

  /// Men's / women's / both, from the home-screen switch.
  final int genders;

  /// Questions from earlier runs: kept out until the pool runs dry, so the
  /// same handful of Easy questions doesn't open every run.
  final Set<String> seenBefore;
  final Random _random;

  /// Rough mix: mostly connections and careers, some line-ups and categories.
  static const _weights = {
    SurvivalKind.connection: 35,
    SurvivalKind.career: 35,
    SurvivalKind.lineup: 15,
    SurvivalKind.category: 15,
  };

  Future<SurvivalQuestion?> next(Difficulty d, Set<String> used) async {
    // Line-ups are men's only so far.
    final kinds = [
      for (final k in SurvivalKind.values)
        if (k != SurvivalKind.lineup || genders & FootballGender.men.mask != 0) k
    ];
    final first = _pick(kinds);
    final order = [first, ...kinds.where((k) => k != first)];
    // Something new first (the chosen kind, then any other); only when every
    // kind has run dry do earlier runs' questions come back.
    for (final avoid in [{...used, ...seenBefore}, used]) {
      for (final k in order) {
        final q = await _question(k, d, avoid);
        if (q != null) return q;
      }
    }
    return null;
  }

  SurvivalKind _pick(List<SurvivalKind> kinds) {
    final total = kinds.fold<int>(0, (a, k) => a + _weights[k]!);
    var r = _random.nextInt(total);
    for (final k in kinds) {
      r -= _weights[k]!;
      if (r < 0) return k;
    }
    return kinds.last;
  }

  /// Ids are prefixed by kind so a club pair and a category can't clash.
  static Set<String> _raw(Set<String> used, String prefix) =>
      {for (final u in used) if (u.startsWith(prefix)) u.substring(prefix.length)};

  Future<SurvivalQuestion?> _question(SurvivalKind k, Difficulty d, Set<String> used) async {
    switch (k) {
      case SurvivalKind.connection:
        final c = await source.clubConnection(d, _raw(used, 'c:'), genders: genders);
        if (c == null) return null;
        return SurvivalQuestion(
          kind: k,
          id: 'c:${c.id}',
          heading: 'CLUB CONNECTIONS',
          prompt: 'Name a player who played for both',
          lines: [c.clubA.name, c.clubB.name],
          answerIds: c.answerIds,
          difficulty: c.difficulty,
        );
      case SurvivalKind.career:
        final c = await source.careerPath(d, _raw(used, 'p:'), genders: genders);
        if (c == null) return null;
        return SurvivalQuestion(
          kind: k,
          id: 'p:${c.id}',
          heading: 'CAREER PATH',
          prompt: 'Who had this career?',
          lines: [
            for (final s in c.spells)
              '${s.club.name}${s.isLoan ? ' (loan)' : ''}${s.yearsLabel.isEmpty ? '' : '  ${s.yearsLabel}'}'
          ],
          answerIds: {c.player.id},
          difficulty: c.difficulty,
        );
      case SurvivalKind.lineup:
        final m = await source.match(d, _raw(used, 'm:'), genders: genders);
        if (m == null) return null;
        return SurvivalQuestion(
          kind: k,
          id: 'm:${m.id}',
          heading: 'STARTING XI',
          prompt: 'Name a player who started for ${m.targetTeam}',
          lines: ['${m.home} ${m.score} ${m.away}', '${m.title} · ${m.year}'],
          answerIds: {for (final s in m.lineup) s.playerId},
          difficulty: m.difficulty,
        );
      case SurvivalKind.category:
        // Categories that aren't just a club pair (that's a connection) and
        // whose answers are players, not clubs.
        final skip = _raw(used, 'b:');
        for (var i = 0; i < 12; i++) {
          final b = await source.bidding(d, skip, genders: genders);
          if (b == null) return null;
          if (!b.id.startsWith('pair:') && !b.answersAreClubs) {
            return SurvivalQuestion(
              kind: k,
              id: 'b:${b.id}',
              heading: 'NAME ONE',
              prompt: b.prompt,
              answerIds: b.answerIds,
              difficulty: b.difficulty,
              showFlags: !b.hidesFlags,
              showPositions: !b.hidesPositions,
            );
          }
          skip.add(b.id);
        }
        return null;
    }
  }
}
