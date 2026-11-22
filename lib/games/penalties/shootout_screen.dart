import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/sound_service.dart';
import '../../core/theme.dart';
import '../../domain/tournament.dart';
import '../../multiplayer/turn_bridge.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/player_picker.dart';
import '../buzz_race_controller.dart' show GameEvent;
import '../game_screen_support.dart';
import 'penalty_kick.dart';
import 'shootout_controller.dart';
import 'shootout_layout.dart';

/// Full time, level at the top: penalties, or call it a draw. Then the
/// shootout itself - one quick question a kick - and on to the trophy.
class ShootoutScreen extends StatefulWidget {
  const ShootoutScreen({super.key, required this.tournament, required this.onDone});
  final Tournament tournament;

  /// The match is over (settled on penalties, or left as a draw).
  final VoidCallback onDone;

  @override
  State<ShootoutScreen> createState() => _ShootoutScreenState();
}

class _ShootoutScreenState extends State<ShootoutScreen>
    with TickerProviderStateMixin<ShootoutScreen>, GameScreenSupport<ShootoutScreen> {
  Tournament get _t => widget.tournament;
  final _random = Random();
  ShootoutController? _c;
  KickSource? _source;

  /// The next kick, fetched while the taker gets ready.
  PenaltyKick? _ready;
  bool _fetching = false;

  /// This round's kind of kick: every team gets the same kind, so a pure guess
  /// ("Terry or Gerrard?") is the same for everyone.
  KickKind? _roundKind;

  /// Who's taking it (a named player, when the team has names).
  String? _player;
  int _lastSecond = -1;

  /// Joined phones: each kick on the taker's own phone.
  TurnBridge? _phones;
  int _kickNo = 0;

  /// One phone passed round: the kick starts by itself after a few seconds.
  static const handoverSeconds = 5;
  Timer? _handoverTimer;
  int _handoverLeft = 0;

  static const _kettle = 'Put the kettle on, we’re going to penalties.';
  static const _scored = ['Ice in the veins!', 'Top bins.', 'Sends the keeper the wrong way!', 'Never in doubt.'];
  static const _saved = ['The keeper’s guessed right.', 'Straight at the keeper.', 'Ballooned it over the bar!', 'Bottled it.'];
  static const _winLines = ['Ice in the veins!', 'They’ll be singing about this one for years.', 'Cometh the hour…'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (roomFor(_t) case final room?) _phones = TurnBridge(room, _t)..start();
      _syncPhones();
      if (services.settings.commentaryOn) say(_kettle);
    });
  }

  @override
  void dispose() {
    _handoverTimer?.cancel();
    _phones?.dispose();
    _c?.dispose();
    disposeGameSupport();
    super.dispose();
  }

  void _goToPens() {
    final c = ShootoutController(teams: _t.leaders, kickSeconds: max(15, _t.config.answerSeconds));
    _source = KickSource(services.challenges, random: _random, genders: _t.config.genderMask);
    c.addListener(() => _onChange(c));
    setState(() => _c = c);
    _prepare(c);
    startClock(c.advance);
  }

  /// A new taker: who it is, and their question fetched while they get ready.
  void _prepare(ShootoutController c) {
    _player = _t.nextTurnPlayer(c.taker);
    _ready = null;
    _fetching = true;
    if (c.roundStart) _roundKind = null;
    _source!.next(kind: _roundKind).then((k) {
      if (!mounted) return;
      _fetching = false;
      if (k == null) {
        // Nothing left to ask (shouldn't happen): leave it as a draw.
        widget.onDone();
        return;
      }
      _ready = k;
      _roundKind ??= k.kind;
      _syncPhones();
      // On their own phone, or nobody's passing the phone: straight in.
      if (_phones?.phoneFor(c.taker, name: _player) != null) {
        _start(c);
      } else {
        _armHandover(c);
      }
      if (mounted) setState(() {});
    });
  }

  void _armHandover(ShootoutController c) {
    _handoverTimer?.cancel();
    _handoverLeft = handoverSeconds;
    _handoverTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _handoverLeft--);
      if (_handoverLeft <= 0) _start(c);
    });
  }

  void _start(ShootoutController c) {
    _handoverTimer?.cancel();
    _handoverTimer = null;
    final k = _ready;
    if (k == null || c.phase != ShootoutPhase.handover) return;
    _kickNo++;
    c.start(k);
  }

  void _onChange(ShootoutController c) {
    final scored = c.lastEvent == GameEvent.correct;
    handleEvent(c.eventSerial, c.lastEvent,
        line: switch (c.lastEvent) {
          GameEvent.complete => _winLines[_random.nextInt(_winLines.length)],
          _ when scored => _scored[_random.nextInt(_scored.length)],
          GameEvent.wrong || GameEvent.timeUp => _saved[_random.nextInt(_saved.length)],
          _ => null,
        });
    if (c.phase == ShootoutPhase.kicking) {
      final sec = c.secondsLeft.ceil();
      if (sec != _lastSecond) {
        _lastSecond = sec;
        if (sec <= 5 && sec > 0) services.sound.play(Sfx.tickFast, volume: 0.7);
      }
    } else {
      _lastSecond = -1;
    }
    if (c.phase == ShootoutPhase.finished && _t.penaltyWinner == null) {
      _t.penaltyWinner = c.winner;
      _t.penaltyGoals = {for (final team in c.teams) team: c.goals(team)};
    }
    _syncPhones();
    if (mounted) setState(() {});
  }

  void _next(ShootoutController c) {
    c.next();
    if (c.phase == ShootoutPhase.handover) _prepare(c);
  }

  String _label(ShootoutController c) {
    if (c.suddenDeath) return 'SUDDEN DEATH';
    return 'KICK ${c.kickNumber} OF ${c.kicksEach}';
  }

  Map<String, Object?> _teamView(int team) =>
      {'name': _t.teamName(team), 'color': _t.config.teams[team].colorIndex};

  Map<String, Object?> _view() {
    final c = _c;
    if (c == null) {
      return {
        'phase': 'choice',
        'level': [
          for (final team in _t.leaders) {..._teamView(team), 'score': _t.scores[team]},
        ],
      };
    }
    final kick = c.kick;
    return {
      'phase': c.phase.name,
      'each': c.kicksEach,
      'teams': [
        for (final team in c.teams)
          {..._teamView(team), 'kicks': c.kicks[team], if (!c.alive.contains(team)) 'out': true},
      ],
      'taker': {..._teamView(c.taker), if (_player != null) 'player': _player},
      'label': _label(c),
      if (kick != null && (c.phase == ShootoutPhase.kicking || c.phase == ShootoutPhase.result)) 'kick': kick.toView(),
      if (c.phase == ShootoutPhase.result) ...{
        'scored': c.lastScored,
        // A miss: the question shakes red (no "SAVED!").
        if (c.lastScored == false) 'shake': Object.hash('pens', _t.rounds.length, _kickNo),
        'reveal': kick?.reveal,
      },
      if (c.phase == ShootoutPhase.finished) ...{
        'winner': _teamView(c.winner!),
        'pens': _t.penaltyScore,
      },
    };
  }

  void _syncPhones() {
    final p = _phones;
    if (p == null) return;
    final c = _c;
    final view = _view();
    if (c == null || c.phase != ShootoutPhase.kicking) {
      p.idle('Penalties', game: 'pens', board: view);
      return;
    }
    final k = c.kick!;
    p.show(
      key: '${_t.rounds.length}-pens-$_kickNo',
      team: c.taker,
      name: _player,
      stage: k.tap ? TurnStage.choose : TurnStage.answer,
      title: 'PENALTIES · ${_label(c)}',
      headline: k.ask,
      game: 'pens',
      board: view,
      left: c.secondsLeft,
      total: c.kickSeconds.toDouble(),
      index: k.clubs ? services.repo.clubIndex : services.repo.players,
      answers: k.answers,
      clubs: k.clubs,
      hint: k.clubs ? 'Say or type a club…' : 'Say or type a player…',
      onPick: (pl) => c.submit(pl.id),
      onPass: c.pass,
      onChoose: c.choose,
    );
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<bool>(valueListenable: answerTyping, builder: (context, typing, _) => _build(typing));

  Widget _build(bool typingNow) {
    final c = _c;
    final view = _view();
    final kicking = c != null && c.phase == ShootoutPhase.kicking;
    final k = c?.kick;
    final remote = _phones?.remote;
    Widget? box;
    if (kicking && k != null && !k.tap) {
      final colour = _t.config.teams[c.taker].colorIndex;
      box = Column(children: [
        TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft),
        const SizedBox(height: 10),
        if (remote != null)
          OnTheirPhone(name: '${remote.name} (${_t.teamName(c.taker)})')
        else
          PlayerPicker(
            key: ValueKey('pens-$_kickNo'),
            index: k.clubs ? services.repo.clubIndex : services.repo.players,
            voice: services.voice,
            accent: Palette.team(colour),
            hint: k.clubs ? 'Say or type a club…' : 'Say or type a player…',
            showFlags: !k.clubs,
            isAnswer: (p) => k.answers.contains(p.id),
            onPick: (p) => c.submit(p.id),
            onPass: c.pass,
          ),
      ]);
    } else if (kicking && remote != null) {
      box = OnTheirPhone(name: '${remote.name} (${_t.teamName(c.taker)})');
    }
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PitchBackground(
        child: SafeArea(
          child: Column(children: [
            const Align(alignment: Alignment.centerLeft, child: ExitMatchButton()),
            Expanded(
              child: ShootoutLayout(
                data: view,
                typing: typingNow && kicking,
                commentary: commentaryText,
                answerBox: box,
                clock: kicking ? TimerBar(fraction: c.fractionLeft, seconds: c.secondsLeft) : null,
                startLabel: _handoverTimer != null ? 'TAP WHEN READY - STARTS IN $_handoverLeft' : (_fetching ? 'GETTING READY…' : null),
                onPens: c == null ? _goToPens : null,
                onDraw: c == null ? widget.onDone : null,
                onStart: c != null && c.phase == ShootoutPhase.handover && _ready != null && remote == null
                    ? () => _start(c)
                    : (c != null && c.phase == ShootoutPhase.handover ? () {} : null),
                onChoose: kicking && remote == null && (k?.tap ?? false) ? c.choose : null,
                onNext: c != null && c.phase == ShootoutPhase.result ? () => _next(c) : null,
                onFinish: c != null && c.phase == ShootoutPhase.finished ? widget.onDone : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
