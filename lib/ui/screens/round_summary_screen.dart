import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../match_flow.dart';
import '../teaser/teaser_screens.dart';
import '../widgets/common.dart';

/// After each round: who scored what, and the table. Then half-time (the
/// teaser), or the next game — with the teaser there to be had in between.
class RoundSummaryScreen extends StatefulWidget {
  const RoundSummaryScreen({super.key, required this.tournament});
  final Tournament tournament;

  @override
  State<RoundSummaryScreen> createState() => _RoundSummaryScreenState();
}

class _RoundSummaryScreenState extends State<RoundSummaryScreen> {
  final _teaserKey = GlobalKey();

  /// The teaser panel is open (the table makes way for it).
  bool _teaserOpen = false;

  /// Someone's answering the teaser: nobody moves on until they're done.
  bool _teaserBusy = false;

  /// Full time with the teaser unsolved: the answers are out.
  bool _revealed = false;

  /// "Next challenge in 5": a moment to go for the teaser before moving on.
  int _hold = 0;
  Timer? _holdTimer;

  Tournament get t => widget.tournament;

  @override
  void initState() {
    super.initState();
    t.addListener(_changed);
    if (t.teaserOpen && !t.isFinished) {
      _hold = 5;
      _holdTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => _hold--);
        if (_hold <= 0) timer.cancel();
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    t.removeListener(_changed);
    super.dispose();
  }

  Widget _button() {
    if (t.teaserDue) {
      return BigButton(
        label: 'Half-time teaser',
        icon: Icons.psychology_alt_rounded,
        color: Palette.gold,
        onPressed: () => MatchFlow.toHalfTime(context, t),
      );
    }
    if (t.isFinished) {
      // An unsolved teaser comes out before the final whistle.
      final reveal = t.teaserOpen && !_revealed;
      return BigButton(
        label: reveal ? 'Full time – the teaser' : 'Final whistle',
        icon: reveal ? Icons.psychology_alt_rounded : Icons.emoji_events,
        color: Palette.gold,
        onPressed: _teaserBusy
            ? null
            : () => reveal ? setState(() => _revealed = true) : MatchFlow.toWinner(context, t),
      );
    }
    return BigButton(
      label: _hold > 0 ? 'Next challenge in $_hold' : 'Next challenge',
      icon: Icons.casino,
      onPressed: _hold > 0 || _teaserBusy ? null : () => MatchFlow.toWheel(context, t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = t.rounds.last;
    final standings = t.standings;
    final table = ListView(children: [
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
    ]);
    // Between games (not at half-time, which has its own screen).
    final showTeaser = t.teaser != null && t.teaser!.halfTimeDone && !t.teaserDue;
    final teaser = showTeaser
        ? TeaserBetweenGames(
            key: _teaserKey,
            tournament: t,
            revealNow: _revealed,
            onOpenChanged: (open) => setState(() => _teaserOpen = open),
            onBusyChanged: (busy) => setState(() => _teaserBusy = busy),
          )
        : null;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Align(alignment: Alignment.centerLeft, child: ExitMatchButton()),
              if (!_teaserOpen) ...[
                Text('ROUND ${t.rounds.length} OF ${t.totalRounds}', style: AppText.label(16)),
                Text(last.mode.title.toUpperCase(), style: AppText.headline(40, color: last.mode.color)),
                if (last.multiplier > 1) Text('DOUBLE POINTS', style: AppText.label(15, color: Palette.gold)),
                const SizedBox(height: 24),
                Text('THE TABLE', style: AppText.label(14)),
                const SizedBox(height: 8),
                Expanded(child: table),
                if (teaser != null) teaser,
              ] else
                Expanded(child: SingleChildScrollView(child: teaser)),
              _button(),
            ]),
          ),
        ),
      ),
    );
  }
}
