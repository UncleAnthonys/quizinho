import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../match_flow.dart';
import '../widgets/common.dart';

/// After each round: who scored what, and the table.
class RoundSummaryScreen extends StatelessWidget {
  const RoundSummaryScreen({super.key, required this.tournament});
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final last = t.rounds.last;
    final standings = t.standings;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Align(alignment: Alignment.centerLeft, child: ExitMatchButton()),
              Text('ROUND ${t.rounds.length} OF ${t.totalRounds}', style: AppText.label(16)),
              Text(last.mode.title.toUpperCase(), style: AppText.headline(40, color: last.mode.color)),
              if (last.multiplier > 1) Text('DOUBLE POINTS', style: AppText.label(15, color: Palette.gold)),
              const SizedBox(height: 24),
              Text('THE TABLE', style: AppText.label(14)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  for (final (pos, team) in standings.indexed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border(left: BorderSide(color: Palette.team(t.config.teams[team].colorIndex), width: 6)),
                      ),
                      child: Row(children: [
                        SizedBox(width: 28, child: Text('${pos + 1}', style: AppText.headline(26, color: Palette.muted))),
                        Expanded(child: Text(t.teamName(team).toUpperCase(), style: AppText.headline(28))),
                        if ((last.points[team] ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text('+${last.points[team]}', style: AppText.headline(24, color: Palette.yellow)),
                          ),
                        Text('${t.scores[team]}', style: AppText.headline(36)),
                      ]),
                    ),
                ]),
              ),
              BigButton(
                label: t.isFinished ? 'Final whistle' : 'Next challenge',
                icon: t.isFinished ? Icons.emoji_events : Icons.casino,
                color: t.isFinished ? Palette.gold : Palette.yellow,
                onPressed: () => t.isFinished ? MatchFlow.toWinner(context, t) : MatchFlow.toWheel(context, t),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
