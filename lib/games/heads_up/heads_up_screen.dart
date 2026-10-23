import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/app_services.dart';
import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/game_mode.dart';
import '../../domain/tournament.dart';
import '../../ui/widgets/common.dart';
import '../buzz_game_view.dart' show LoadingRound;
import '../game_screen_support.dart';
import 'heads_up_controller.dart';
import 'tilt_detector.dart';

class HeadsUpScreen extends StatefulWidget {
  const HeadsUpScreen({super.key, required this.round});
  final RoundContext round;

  @override
  State<HeadsUpScreen> createState() => _HeadsUpScreenState();
}

class _HeadsUpScreenState extends State<HeadsUpScreen>
    with TickerProviderStateMixin<HeadsUpScreen>, GameScreenSupport<HeadsUpScreen> {
  static const _mode = GameModeId.headsUp;
  static const _mix = 'mix';

  HeadsUpController? _c;
  List<HeadsUpPack> _packs = const [];
  String _packId = _mix;
  String? _holder;
  HeadsUpPhase? _lastPhase;
  int _lastSecond = -1;
  int _quarterTurns = kIsWeb ? 0 : 1;
  Color? _flash;
  Timer? _flashTimer;
  late final TiltDetector _tilt = TiltDetector(
    onCorrect: _correct,
    onPass: _pass,
    onQuarterTurns: (t) => setState(() => _quarterTurns = t),
  );

  Tournament get _t => widget.round.tournament;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packs = parseHeadsUpPacks(await rootBundle.loadString('assets/packs/heads_up.json'));
    if (!mounted) return;
    final c = HeadsUpController(
      teamCount: _t.teamCount,
      turnSeconds: _t.config.headsUpSeconds,
      startTeam: _t.standings.last,
    );
    c.addListener(() => _onChange(c));
    setState(() {
      _packs = packs;
      _c = c;
    });
    _onChange(c);
    _tilt.start();
    startClock(c.advance);
  }

  void _onChange(HeadsUpController c) {
    if (c.phase != _lastPhase) {
      final from = _lastPhase;
      _lastPhase = c.phase;
      _tilt.enabled = c.phase == HeadsUpPhase.playing;
      if (c.phase == HeadsUpPhase.ready) _holder = _t.nextTurnPlayer(c.currentTeam);
      if (c.phase == HeadsUpPhase.playing) services.sound.play(Sfx.whistle);
      if (c.phase == HeadsUpPhase.turnOver && from == HeadsUpPhase.playing) {
        services.sound.play(Sfx.whistle);
        services.haptic(HapticStrength.heavy);
        for (final card in c.shown) {
          _t.markUsed(_mode, card);
        }
        final holder = _holder;
        if (holder != null) _t.creditPlayer(c.currentTeam, holder, c.turnCorrect * widget.round.multiplier);
      }
    }
    if (c.phase == HeadsUpPhase.countdown || c.phase == HeadsUpPhase.playing) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        if (c.phase == HeadsUpPhase.countdown) services.sound.play(Sfx.countdownBeep);
        if (c.phase == HeadsUpPhase.playing && sec <= 5 && sec > 0) services.sound.play(Sfx.tickFast);
      }
    }
    if (mounted) setState(() {});
  }

  void _correct() {
    final c = _c;
    if (c == null || c.phase != HeadsUpPhase.playing) return;
    c.correct();
    services.sound.play(Sfx.correct);
    services.haptic(HapticStrength.medium);
    _showFlash(Palette.green);
  }

  void _pass() {
    final c = _c;
    if (c == null || c.phase != HeadsUpPhase.playing) return;
    c.pass();
    services.sound.play(Sfx.wrong, volume: 0.5);
    services.haptic(HapticStrength.light);
    _showFlash(Palette.danger);
  }

  void _showFlash(Color colour) {
    _flashTimer?.cancel();
    setState(() => _flash = colour);
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  List<String> _buildDeck() {
    final source = _packId == _mix
        ? [for (final p in _packs) ...p.cards]
        : _packs.firstWhere((p) => p.id == _packId, orElse: () => _packs.first).cards;
    final used = _t.usedIds(_mode);
    var fresh = source.where((c) => !used.contains(c)).toList();
    if (fresh.length < 15) fresh = [...source]; // pack exhausted: allow repeats rather than stall
    return fresh..shuffle(Random());
  }

  @override
  void dispose() {
    _tilt.stop();
    _flashTimer?.cancel();
    disposeGameSupport();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const LoadingRound();
    final playing = c.phase == HeadsUpPhase.countdown || c.phase == HeadsUpPhase.playing;
    return Scaffold(
      body: PitchBackground(
        child: SafeArea(
          child: playing
              ? _fullScreen(c)
              : Column(children: [
                  Scoreboard(tournament: _t, highlightTeam: c.currentTeam),
                  Expanded(child: c.phase == HeadsUpPhase.ready ? _ready(c) : _summary(c)),
                ]),
        ),
      ),
    );
  }

  Widget _ready(HeadsUpController c) {
    final team = c.currentTeam;
    final colour = _t.config.teams[team].colorIndex;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      Row(children: [
        Text('FOOTBALL HEADS UP', style: AppText.label(15, color: Palette.yellow)),
        const Spacer(),
        if (widget.round.multiplier > 1)
          Text('x${widget.round.multiplier} POINTS', style: AppText.label(15, color: Palette.gold)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(color: Palette.team(colour), borderRadius: BorderRadius.circular(22)),
        child: Column(children: [
          Icon(Icons.face_retouching_natural, size: 40, color: Palette.onTeam(colour)),
          Text('PHONE ON YOUR HEAD', style: AppText.label(16, color: Palette.onTeam(colour))),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text((_holder ?? _t.teamName(team)).toUpperCase(),
                style: AppText.headline(52, color: Palette.onTeam(colour))),
          ),
          Text(
            _holder == null ? 'One player guesses, the rest describe' : '${_t.teamName(team).toUpperCase()} — DESCRIBE!',
            style: AppText.label(15, color: Palette.onTeam(colour)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Text('PICK A PACK', style: AppText.label(13)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, title) in [(_mix, 'Mix it up'), for (final p in _packs) (p.id, p.title)])
          ChoiceChip(
            label: Text(title),
            selected: _packId == id,
            onSelected: (_) => setState(() => _packId = id),
          ),
      ]),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(14)),
        child: Text(
          '${c.turnSeconds} seconds. Tilt the phone DOWN for correct, UP to pass — or tap the buttons.',
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
      ),
      const SizedBox(height: 16),
      BigButton(label: 'Start', icon: Icons.play_arrow_rounded, onPressed: () => c.startTurn(_buildDeck())),
    ]);
  }

  /// Countdown and cards, rotated to read sideways on a forehead.
  Widget _fullScreen(HeadsUpController c) {
    final counting = c.phase == HeadsUpPhase.countdown;
    return RotatedBox(
      quarterTurns: _quarterTurns,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _flash ?? Colors.transparent,
        padding: const EdgeInsets.all(12),
        child: counting
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('PHONE ON YOUR FOREHEAD', style: AppText.label(18, color: Palette.yellow)),
                Text('${max(1, c.secondsLeft.ceil())}', style: AppText.headline(120)),
              ])
            : Column(children: [
                Row(children: [
                  Expanded(child: TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft)),
                  const SizedBox(width: 12),
                  Text('${c.turnCorrect} ✓', style: AppText.headline(28, color: Palette.yellow)),
                ]),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          (c.currentCard ?? '').toUpperCase(),
                          textAlign: TextAlign.center,
                          style: AppText.headline(80, color: _flash == null ? Colors.white : Palette.pitchDeep),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(children: [
                  Expanded(
                    child: BigButton(
                      label: 'Pass',
                      icon: Icons.close_rounded,
                      color: Palette.danger,
                      textColor: Colors.white,
                      onPressed: _pass,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BigButton(
                      label: 'Correct',
                      icon: Icons.check_rounded,
                      color: Palette.green,
                      textColor: Colors.white,
                      onPressed: _correct,
                    ),
                  ),
                ]),
              ]),
      ),
    );
  }

  Widget _summary(HeadsUpController c) {
    final team = c.currentTeam;
    final colour = _t.config.teams[team].colorIndex;
    final finished = c.phase == HeadsUpPhase.finished || c.isLastTurn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(children: [
        TeamChip(name: _holder ?? _t.teamName(team), colorIndex: colour, size: 22),
        const SizedBox(height: 6),
        Text('${c.turnCorrect} CORRECT', style: AppText.headline(48, color: Palette.yellow)),
        if (widget.round.multiplier > 1) Text('x${widget.round.multiplier} POINTS', style: AppText.label(14, color: Palette.gold)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(children: [
            for (final r in c.turnResults)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(r.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: r.correct ? Palette.green : Palette.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(r.card,
                        style: TextStyle(fontSize: 17, color: r.correct ? Palette.text : Palette.muted)),
                  ),
                ]),
              ),
          ]),
        ),
        BigButton(
          label: finished ? 'Finish round' : 'Next team',
          icon: finished ? Icons.flag : Icons.arrow_forward,
          onPressed: () {
            c.nextTurn();
            if (c.phase == HeadsUpPhase.finished) widget.round.onComplete(c.result());
          },
        ),
      ]),
    );
  }
}
