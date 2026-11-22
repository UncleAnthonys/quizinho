import 'package:flutter/material.dart';

import '../../core/commentary.dart' show Commentary;
import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../../games/buzz_game_view.dart' show LoadingRound;
import '../../games/buzz_race_controller.dart';
import '../../games/game_screen_support.dart';
import '../../games/teaser/teaser_controller.dart';
import '../../multiplayer/buzz_bridge.dart';
import '../match_flow.dart';
import '../widgets/common.dart';
import '../widgets/match_table.dart' show MatchTable;
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
      handleEvent(c.eventSerial, c.lastEvent, miss: null, correctLine: teaserCorrectLine);
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
          if (halfTime) 'halfTime': true,
          'clock': c.lockedOut.isEmpty ? 'BUZZ IN' : 'YOUR GUESS',
        },
        answerIds: () => {...teaser.answerIds, ...teaser.unsure},
        reveal: () => teaser.answerNames,
        faceOff: () => null,
        paused: () => false,
        wrap: teaserPhonesView,
      )
        ..addListener(() {
          if (mounted) setState(() {});
        })
        ..start();
    }
    setState(() => teaserController = c);
    startClock(c.advance);
  }

  /// What joined phones show instead of the teaser, or null for the teaser
  /// itself (half-time). Between games, until it's opened here: the table,
  /// with the teaser tucked in for any phone to open and buzz on.
  Map<String, Object?>? teaserPhonesView(Map<String, Object?> teaser) => null;

  /// This screen's line for the teaser being got (null: the usual ones).
  String? get teaserCorrectLine => null;

  /// Hook: the teaser moved on (buzzed, answered, solved, revealed).
  void onTeaserPhase(BuzzPhase phase) {}

  void disposeTeaser() {
    teaserBridge?.dispose();
    teaserController?.dispose();
  }
}

/// The question card shakes red on a miss (wrong, out of time, passed).
Widget _shaking(TeaserController c, Widget prompt) =>
    MissShake(trigger: c.missShake == 0 ? null : Object.hash(c, c.missShake), child: prompt);

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
              // Typing: all of this folds away so the name suggestions show;
              // tap out of the box and it's back.
              Collapse(
                hidden: typing,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('HALF-TIME', style: AppText.label(16, color: Palette.gold)),
                  Text('THE TEASER', style: AppText.headline(44, color: Palette.gold)),
                  const SizedBox(height: 10),
                  if (!done) TimerBar(fraction: c.halfTimeLeft / c.halfTimeSeconds, seconds: c.halfTimeLeft),
                  const SizedBox(height: 12),
                  _shaking(c, TeaserPrompt(question: c.teaser.question, prefix: c.teaser.prefix, halfTime: !c.clockDone && !done)),
                  const SizedBox(height: 14),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: TeaserPlay(
                    controller: c,
                    remoteAnswerer: teaserBridge?.remote?.name,
                    showQuestion: false,
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
    required this.onResult,
    this.revealNow = false,
    this.openNow = false,
  });

  /// Full time's "Last chance": the panel opens for everyone to have a go.
  final bool openNow;

  /// Solved, or everyone's guessed wrong (between games): the result sits
  /// under the table rather than in place of it.
  final VoidCallback onResult;
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
    // After this frame: opening tells the summary screen, which is mid-build.
    if (widget.revealNow && !old.revealNow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal();
      });
    }
    if (widget.openNow && !old.openNow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setOpen(true);
      });
    }
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
    teaserBridge?.republish();
    widget.onOpenChanged(open);
  }

  /// The teams playing on this phone (not every player on their own).
  List<int> get _here {
    final onPhones = teaserBridge?.phoneTeams() ?? const <int>{};
    return [
      for (var i = 0; i < widget.tournament.teamCount; i++)
        if (!onPhones.contains(i)) i,
    ];
  }

  /// "Tap to answer" here. When only one team plays on this phone (everyone
  /// else has joined on their own), it's theirs: straight to the answer box.
  /// Otherwise it opens on every phone, each team with its buzzer.
  void _tapToAnswer(TeaserController c) {
    final here = _here.where(c.canBuzz).toList();
    _setOpen(true);
    if (teaserBridge != null && here.length == 1) c.buzz(here.single);
  }

  // Got at full time's last chance.
  @override
  String? get teaserCorrectLine => widget.openNow ? Commentary.lastChance : null;

  @override
  Map<String, Object?>? teaserPhonesView(Map<String, Object?> teaser) {
    if (_open) return null;
    final t = widget.tournament;
    return {
      'kind': 'table',
      ...MatchTable.round(t),
      // Full time has its own "Last chance", which opens it everywhere.
      if (!t.isFinished && teaser['phase'] == 'open') 'teaser': teaser,
    };
  }

  @override
  void onTeaserPhase(BuzzPhase phase) {
    widget.onBusyChanged(phase == BuzzPhase.answering);
    // A phone buzzed, or it's been solved/revealed: show it.
    if (phase != BuzzPhase.open) _setOpen(true);
    if (phase == BuzzPhase.resolved && !widget.revealNow) widget.onResult();
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
      // The question stays in view under the table, so nobody opens it just
      // to remind themselves; full time has its own "Last chance" button.
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TeaserPrompt(question: c.teaser.question, prefix: c.teaser.prefix, compact: true),
          if (!widget.tournament.isFinished)
            if (_here.any(c.canBuzz)) ...[
              const SizedBox(height: 12),
              TeaserChip(onPressed: () => _tapToAnswer(c)),
            ] else if (_here.isNotEmpty) ...[
              // The others answer on their own phones.
              const SizedBox(height: 12),
              Text(_here.length == 1 ? 'YOUR TEAM’S HAD ITS GUESS' : 'YOU’VE ALL HAD YOUR GUESS',
                  style: AppText.label(13)),
            ],
        ]),
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
        if (c.phase != BuzzPhase.resolved)
          ValueListenableBuilder<bool>(
            valueListenable: answerTyping,
            builder: (context, typing, _) => Collapse(
              hidden: typing,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _shaking(c, TeaserPrompt(question: c.teaser.question, prefix: c.teaser.prefix, compact: true)),
              ),
            ),
          ),
        TeaserPlay(controller: c, remoteAnswerer: teaserBridge?.remote?.name),
        if (c.phase == BuzzPhase.open && !widget.openNow)
          TextButton(
            onPressed: () => _setOpen(false),
            child: Text('NOT YET - KEEP THINKING', style: AppText.label(13)),
          )

      ]),
    );
  }
}
