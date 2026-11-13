import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../match_flow.dart' show GameModeStyle;
import 'common.dart';

/// The table after a round, and at full time, drawn from a snapshot so the
/// main phone and every joined phone show exactly the same thing.
///
/// No nulls in lists (the rooms database drops them).
class MatchTable {
  MatchTable._();

  static List<Map<String, Object?>> _rows(Tournament t, {bool plus = false}) {
    final last = t.rounds.isEmpty ? null : t.rounds.last;
    return [
      for (final team in t.standings)
        {
          'name': t.teamName(team),
          'colour': t.config.teams[team].colorIndex,
          'score': t.scores[team],
          if (plus) 'plus': last?.points[team] ?? 0,
        },
    ];
  }

  /// After a round: which game it was, and the table with this round's points.
  static Map<String, Object?> round(Tournament t) {
    final last = t.rounds.last;
    return {
      'round': t.rounds.length,
      'of': t.totalRounds,
      'game': last.mode.title,
      'colour': last.mode.color.toARGB32(),
      if (last.multiplier > 1) 'double': true,
      'rows': _rows(t, plus: true),
    };
  }

  /// Full time: the winners, player of the match, and the final table.
  static Map<String, Object?> fullTime(Tournament t) {
    final table = t.playerTable;
    final potm = table.isNotEmpty && !t.everyTeamSolo;
    return {
      'full': true,
      'leaders': [
        for (final l in t.leaders) {'name': t.teamName(l), 'colour': t.config.teams[l].colorIndex},
      ],
      if (potm)
        'potm': {
          'name': table.first.name,
          'colour': t.config.teams[table.first.team].colorIndex,
          'points': table.first.points,
          'others': table.skip(1).take(3).map((p) => '${p.name} ${p.points}').join('  ·  '),
        },
      'rows': _rows(t),
    };
  }

  static List<Map<String, Object?>> rowsOf(Map<String, Object?> data) =>
      [for (final r in (data['rows'] as List?) ?? const []) Map<String, Object?>.from(r as Map)];
}

/// "Round 2 of 4 · Pointless · The table".
class RoundTableHeader extends StatelessWidget {
  const RoundTableHeader({super.key, required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('ROUND ${data['round']} OF ${data['of']}', style: AppText.label(16)),
        Text('${data['game'] ?? ''}'.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppText.headline(40, color: Color((data['colour'] as num?)?.toInt() ?? 0xFFFFCC29))),
        if (data['double'] == true) Text('DOUBLE POINTS', style: AppText.label(15, color: Palette.gold)),
        const SizedBox(height: 24),
        Text('THE TABLE', style: AppText.label(14)),
        const SizedBox(height: 8),
      ]);
}

/// The rows of the table: round style (this round's points) or full time.
List<Widget> matchTableRows(Map<String, Object?> data) {
  final full = data['full'] == true;
  return [
    for (final (pos, r) in MatchTable.rowsOf(data).indexed)
      if (full)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 30, child: Text('${pos + 1}', style: AppText.headline(24, color: Palette.muted))),
            Container(width: 10, height: 28, color: Palette.team((r['colour'] as num?)?.toInt() ?? 0)),
            const SizedBox(width: 10),
            Expanded(child: Text('${r['name']}'.toUpperCase(), style: AppText.headline(26))),
            Text('${r['score']}', style: AppText.headline(30)),
          ]),
        )
      else
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: Palette.team((r['colour'] as num?)?.toInt() ?? 0), width: 6)),
          ),
          child: Row(children: [
            SizedBox(width: 28, child: Text('${pos + 1}', style: AppText.headline(26, color: Palette.muted))),
            Expanded(child: Text('${r['name']}'.toUpperCase(), style: AppText.headline(28))),
            if (((r['plus'] as num?) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('+${r['plus']}', style: AppText.headline(24, color: Palette.yellow)),
              ),
            Text('${r['score']}', style: AppText.headline(36)),
          ]),
        ),
  ];
}

/// Full time: trophy, champions (or a draw) and player of the match.
class FullTimeHeader extends StatelessWidget {
  const FullTimeHeader({super.key, required this.data, this.line = ''});
  final Map<String, Object?> data;

  /// The commentator's line (main phone only).
  final String line;

  @override
  Widget build(BuildContext context) {
    final leaders = [for (final l in (data['leaders'] as List?) ?? const []) Map<String, Object?>.from(l as Map)];
    final potm = data['potm'] is Map ? Map<String, Object?>.from(data['potm']! as Map) : null;
    return Column(children: [
      const SizedBox(height: 20),
      Text('FULL TIME', style: AppText.label(18)),
      const Icon(Icons.emoji_events_rounded, color: Palette.gold, size: 110),
      Text(leaders.length > 1 ? 'IT’S A DRAW' : 'CHAMPIONS', style: AppText.headline(30, color: Palette.gold)),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        for (final l in leaders) TeamChip(name: '${l['name']}', colorIndex: (l['colour'] as num?)?.toInt() ?? 0, size: 34),
      ]),
      const SizedBox(height: 10),
      if (line.isNotEmpty)
        Text(line, textAlign: TextAlign.center, style: AppText.headline(22, color: Palette.text, weight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (potm != null) _PlayerOfTheMatch(data: potm),
      const SizedBox(height: 8),
    ]);
  }
}

class _PlayerOfTheMatch extends StatelessWidget {
  const _PlayerOfTheMatch({required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final others = '${data['others'] ?? ''}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.gold),
      ),
      child: Column(children: [
        Text('PLAYER OF THE MATCH', style: AppText.label(13, color: Palette.gold)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.star_rounded, color: Palette.gold),
          const SizedBox(width: 6),
          Flexible(child: TeamChip(name: '${data['name']}', colorIndex: (data['colour'] as num?)?.toInt() ?? 0, size: 24)),
          const SizedBox(width: 8),
          Text('${data['points']} PTS', style: AppText.headline(24, color: Palette.gold)),
        ]),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(others, textAlign: TextAlign.center, style: AppText.label(13)),
        ],
      ]),
    );
  }
}
