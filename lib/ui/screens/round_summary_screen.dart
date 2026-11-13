import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../match_flow.dart';
import '../teaser/teaser_screens.dart';
import '../widgets/common.dart';
import '../widgets/match_table.dart';

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

  /// The teaser's been settled between games: its result goes under the table.
  bool _teaserResult = false;

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
    // The same snapshot the joined phones draw (MatchFlow sends it).
    final table = MatchTable.round(t);
    final rows = matchTableRows(table);
    // Between games (not at half-time, which has its own screen).
    final showTeaser = t.teaser != null && t.teaser!.halfTimeDone && !t.teaserDue;
    final teaser = showTeaser
        ? TeaserBetweenGames(
            key: _teaserKey,
            tournament: t,
            revealNow: _revealed,
            onOpenChanged: (open) => setState(() => _teaserOpen = open),
            onBusyChanged: (busy) => setState(() => _teaserBusy = busy),
            onResult: () => setState(() {
              _teaserResult = true;
              _teaserOpen = false;
            }),
          )
        : null;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Align(alignment: Alignment.centerLeft, child: ExitMatchButton()),
              if (_teaserOpen && !_teaserResult)
                Expanded(child: SingleChildScrollView(child: teaser))
              else ...[
                RoundTableHeader(data: table),
                if (_teaserResult)
                  Expanded(child: ListView(children: [...rows, if (teaser != null) teaser]))
                else ...[
                  Expanded(child: ListView(children: rows)),
                  if (teaser != null) teaser,
                ],
              ],
              _button(),
            ]),
          ),
        ),
      ),
    );
  }
}
