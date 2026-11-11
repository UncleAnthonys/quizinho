import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../../games/buzz_game_view.dart' show LoadingRound;
import '../../games/buzz_race_controller.dart';
import '../../games/game_screen_support.dart';
import '../../games/teaser/teaser_controller.dart';
import '../../multiplayer/buzz_bridge.dart';
import '../match_flow.dart';
import '../widgets/common.dart';
import '../widgets/player_picker.dart' show answerTyping;
import 'teaser_play.dart';
import 'teaser_widgets.dart';

/// Runs a teaser on this phone and the room's phones: the controller, the
/// clock, sounds, and the bridge that lets joined phones buzz and answer.
mixin TeaserRunner<W extends StatefulWidget> on State<W>, TickerProviderStateMixin<W>, GameScreenSupport<W> {
  TeaserController? teaserController;
  BuzzBridge? teaserBridge;
  BuzzPhase? _lastPhase;

  Future<void> startTeaser(Tournament t, {required bool halfTime}) async {
    final s = t.teaser;
    if (s == null) return;
    final bank = await services.teasers;
    final teaser = bank.byId(s.id);
    if (!mounted || teaser == null) return;
    final c = TeaserController(tournament: t, teaser: teaser, halfTime: halfTime);
    c.addListener(() {
      handleEvent(c.eventSerial, c.lastEvent, miss: null);
      if (c.phase != _lastPhase) {
        _lastPhase = c.phase;
        MatchFlow.save(context, t);
        onTeaserPhase(c.phase);
      }
      if (mounted) setState(() {});
    });
    final room = roomFor(t);
    if (room != null && s.isOpen) {
      teaserBridge = BuzzBridge(
        room: room,
        controller: c,
        tournament: t,
        players: services.repo.players,
        title: 'HALF-TIME TEASER',
        prompt: teaser.prefix,
        question: () => {
          'teaser': teaser.question,
          'prefix': teaser.prefix,
          'worth': c.worth,
          if (!halfTime || c.clockDone) 'noClock': true,
          'clock': c.lockedOut.isEmpty ? 'BUZZ IN' : 'YOUR GUESS',
        },
        answerIds: () => {...teaser.answerIds, ...teaser.unsure},
        reveal: () => teaser.answerNames,
        faceOff: () => null,
        paused: () => false,
      )
        ..addListener(() {
          if (mounted) setState(() {});
        })
        ..start();
    }
    setState(() => teaserController = c);
    startClock(c.advance);
  }

  /// Hook: the teaser moved on (buzzed, answered, solved, revealed).
  void onTeaserPhase(BuzzPhase phase) {}

  void disposeTeaser() {
    teaserBridge?.dispose();
    teaserController?.dispose();
  }
}

/// Half-time: the teaser, full screen, with a 90-second clock worth 5.
class TeaserHalfTimeScreen extends StatefulWidget {
  const TeaserHalfTimeScreen({super.key, required this.tournament});
  final Tournament tournament;

  @override
  State<TeaserHalfTimeScreen> createState() => _TeaserHalfTimeScreenState();
}

class _TeaserHalfTimeScreenState extends State<TeaserHalfTimeScreen>
    with TickerProviderStateMixin<TeaserHalfTimeScreen>, GameScreenSupport<TeaserHalfTimeScreen>, TeaserRunner<TeaserHalfTimeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await startTeaser(widget.tournament, halfTime: true);
      // No teaser to show (the bank's changed since kick-off): play on.
      if (mounted && teaserController == null) _secondHalf();
    });
  }

  @override
  void dispose() {
    disposeTeaser();
    disposeGameSupport();
    super.dispose();
  }

  void _secondHalf() => MatchFlow.toWheel(context, widget.tournament);

  @override
  Widget build(BuildContext context) {
    final c = teaserController;
    if (c == null) return const LoadingRound();
    final done = c.phase == BuzzPhase.resolved;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: ValueListenableBuilder<bool>(
            valueListenable: answerTyping,
            builder: (context, typing, _) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(children: [
              const Align(alignment: Alignment.centerLeft, child: ExitMatchButton()),
              if (!typing) ...[
                Text('HALF-TIME', style: AppText.label(16, color: Palette.gold)),
                Text('THE TEASER', style: AppText.headline(44, color: Palette.gold)),
                const SizedBox(height: 10),
                if (!done) TimerBar(fraction: c.halfTimeLeft / c.halfTimeSeconds, seconds: c.halfTimeLeft),
                const SizedBox(height: 12),
              ],
              TeaserPrompt(question: c.teaser.question, prefix: c.teaser.prefix, halfTime: !c.clockDone && !done, compact: typing),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: TeaserPlay(
                    controller: c,
                    remoteAnswerer: teaserBridge?.remote?.name,
                    onPlayHere: teaserBridge?.localBuzz,
                  ),
                ),
              ),
              if (done || c.clockDone)
                BigButton(label: 'Second half', icon: Icons.sports_soccer, onPressed: _secondHalf)
              else if (c.phase == BuzzPhase.open) ...[
                GhostButton(label: 'Keep thinking – second half', icon: Icons.sports_soccer, onPressed: _secondHalf),
                Text('It stays open between games until someone gets it', style: AppText.label(12)),
              ],
            ]),
          ),
          ),
        ),
      ),
    );
  }
}

/// Between games: the teaser chip, and the teaser itself once tapped (or
/// once a phone buzzes). At full time an unsolved teaser is revealed.
class TeaserBetweenGames extends StatefulWidget {
  const TeaserBetweenGames({
    super.key,
    required this.tournament,
    required this.onOpenChanged,
    required this.onBusyChanged,
    this.revealNow = false,
  });
  final Tournament tournament;

  /// Someone's answering: the summary screen holds "Next challenge".
  final ValueChanged<bool> onBusyChanged;

  /// The panel opened or closed: the summary screen makes room for it.
  final ValueChanged<bool> onOpenChanged;

  /// Full time: out come the answers.
  final bool revealNow;

  @override
  State<TeaserBetweenGames> createState() => _TeaserBetweenGamesState();
}

class _TeaserBetweenGamesState extends State<TeaserBetweenGames>
    with TickerProviderStateMixin<TeaserBetweenGames>, GameScreenSupport<TeaserBetweenGames>, TeaserRunner<TeaserBetweenGames> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await startTeaser(widget.tournament, halfTime: false);
      if (widget.revealNow) _reveal();
    });
  }

  @override
  void didUpdateWidget(TeaserBetweenGames old) {
    super.didUpdateWidget(old);
    if (widget.revealNow && !old.revealNow) _reveal();
  }

  void _reveal() {
    final c = teaserController;
    if (c == null) return;
    c.reveal();
    _setOpen(true);
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
    widget.onOpenChanged(open);
  }

  @override
  void onTeaserPhase(BuzzPhase phase) {
    widget.onBusyChanged(phase == BuzzPhase.answering);
    // A phone buzzed, or it's been solved/revealed: show it.
    if (phase != BuzzPhase.open) _setOpen(true);
  }

  @override
  void dispose() {
    disposeTeaser();
    disposeGameSupport();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = teaserController;
    if (c == null) return const SizedBox.shrink();
    if (!_open) {
      if (!c.state.isOpen) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TeaserChip(onPressed: () => _setOpen(true)),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.gold, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (c.phase != BuzzPhase.resolved) ...[
          TeaserPrompt(question: c.teaser.question, prefix: c.teaser.prefix, compact: true),
          const SizedBox(height: 12),
        ],
        TeaserPlay(controller: c, remoteAnswerer: teaserBridge?.remote?.name, onPlayHere: teaserBridge?.localBuzz),
        if (c.phase == BuzzPhase.open)
          TextButton(
            onPressed: () => _setOpen(false),
            child: Text('NOT YET — KEEP THINKING', style: AppText.label(13)),
          )
        else if (c.phase == BuzzPhase.resolved && !widget.revealNow)
          TextButton(
            onPressed: () => _setOpen(false),
            child: Text('BACK TO THE TABLE', style: AppText.label(13)),
          ),
      ]),
    );
  }
}
