import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
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

  /// Full time, teaser unsolved: "Last chance" gives everyone this long to
  /// buzz (the clock waits while someone's answering), then out come the answers.
  static const lastChanceSeconds = 30;
  double? _lastChance;
  Timer? _lastChanceTimer;

  void _startLastChance() {
    setState(() => _lastChance = lastChanceSeconds.toDouble());
    // Ticks often, so the bar runs down smoothly.
    _lastChanceTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      if (_teaserBusy) return; // someone's answering: wait for them
      setState(() => _lastChance = _lastChance! - 0.1);
      if (_lastChance! <= 0) _revealTeaser();
    });
  }

  void _revealTeaser() {
    _lastChanceTimer?.cancel();
    setState(() => _revealed = true);
  }

  Tournament get t => widget.tournament;

  /// The pundit on the moment of the match (a late winner, a thrashing,
  /// squeaky bum time), over the table's title for a few seconds.
  String? _line;
  Timer? _lineTimer;

  @override
  void initState() {
    super.initState();
    t.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = AppScope.read(context);
      if (!s.settings.commentaryOn) return;
      final line = s.commentary.afterRound(t);
      if (line == null) return;
      setState(() => _line = line);
      _lineTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _line = null);
      });
    });
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
    _lineTimer?.cancel();
    _holdTimer?.cancel();
    _lastChanceTimer?.cancel();
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
      // An unsolved teaser: one last go for anyone who's been thinking all
      // game, or straight to the answers - then the final whistle.
      if (t.teaserOpen && !_revealed) {
        final left = _lastChance;
        if (left == null) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            BigButton(
              label: 'Last chance at the teaser',
              icon: Icons.psychology_alt_rounded,
              color: Palette.gold,
              onPressed: _teaserBusy ? null : _startLastChance,
            ),
            TextButton(
              onPressed: _teaserBusy ? null : _revealTeaser,
              child: Text('REVEAL TEASER ANSWER', style: AppText.label(14, color: Palette.text)),
            ),
          ]);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TimerBar(fraction: left / lastChanceSeconds, seconds: left.clamp(0, lastChanceSeconds).toDouble()),
          ),
          BigButton(
            label: 'Reveal teaser answer',
            icon: Icons.visibility_rounded,
            color: Palette.gold,
            onPressed: _teaserBusy ? null : _revealTeaser,
          ),
        ]);
      }
      return BigButton(
        label: 'Final whistle',
        icon: Icons.emoji_events,
        color: Palette.gold,
        onPressed: _teaserBusy ? null : () => MatchFlow.toWinner(context, t),
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
            openNow: _lastChance != null,
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
                RoundTableHeader(data: table, commentary: _line),
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
