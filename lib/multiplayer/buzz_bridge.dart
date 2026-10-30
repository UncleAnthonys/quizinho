import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/player_index.dart';
import '../domain/tournament.dart';
import '../games/buzz_race_controller.dart';
import 'room.dart';

/// Runs a buzzer game (Club Connections, Career Path) across the room's phones,
/// from the host phone: puts the question on every phone, takes buzzes from
/// them — the earliest by the database's clock wins — and feeds the buzzing
/// phone's answer into the game. Everyone on a team can buzz; in a face-off
/// only the two named players' phones can.
class BuzzBridge extends ChangeNotifier {
  BuzzBridge({
    required this.room,
    required this.controller,
    required this.tournament,
    required this.players,
    required this.title,
    required this.prompt,
    required this.question,
    required this.answerIds,
    required this.reveal,
    required this.faceOff,
    required this.paused,
    this.multiplier = 1,
  });

  /// 2 on a wildcard round: points shown on the phones match the host.
  final int multiplier;

  /// The face-off intro is up: the clock's stopped and nobody can buzz yet.
  final bool Function() paused;

  final HostRoom room;
  final BuzzRaceController controller;
  final Tournament tournament;
  final PlayerIndex players;
  final String title;
  final String prompt;

  /// What the question shows right now, for the phones to draw with the same
  /// widgets as the host: {"clubs": [a, b]} or {"spells": [...], "shown",
  /// "highlight", "worth"}.
  final Map<String, Object?> Function() question;

  /// Right answers, so the answering phone can judge speech like the host does.
  final Set<String> Function() answerIds;

  /// Shown when the question ends ("It was Tim Cahill", the full answer list).
  final List<String> Function() reveal;
  final FaceOff? Function() faceOff;

  /// The phone answering now (null = nobody, or answering on the host phone).
  RoomMember? remote;

  /// Buzzes that came in within a moment of each other: the earliest wins.
  final List<RemoteBuzz> _pending = [];
  Timer? _window;
  static const _fairnessWindow = Duration(milliseconds: 200);
  final List<StreamSubscription<Object?>> _subs = [];

  String get questionKey => '${tournament.rounds.length}-${controller.questionIndex}';

  void start() {
    _subs.add(room.buzzes.listen(_onBuzz));
    _subs.add(room.answers.listen(_onAnswer));
    controller.addListener(_onChange);
    _publish();
  }

  void _onBuzz(RemoteBuzz b) {
    if (b.question != questionKey || controller.phase != BuzzPhase.open || paused()) return;
    _pending.add(b);
    _window ??= Timer(_fairnessWindow, _decide);
  }

  void _decide() {
    _window = null;
    final buzzes = [..._pending]..sort((a, b) => a.at.compareTo(b.at));
    _pending.clear();
    if (controller.phase != BuzzPhase.open) return;
    final f = faceOff();
    for (final b in buzzes) {
      final m = room.members[b.device];
      if (m == null || !controller.canBuzz(m.team)) continue;
      if (f != null && f.nameFor(m.team) != m.name) continue;
      remote = m;
      controller.buzz(m.team);
      notifyListeners();
      return;
    }
  }

  void _onAnswer(RemoteAnswer a) {
    final r = remote;
    if (r == null || a.device != r.device || a.question != questionKey) return;
    if (controller.phase != BuzzPhase.answering || controller.answeringTeam != r.team) return;
    if (a.pass) {
      controller.pass();
      return;
    }
    final p = a.playerId == null ? null : players.byId(a.playerId!);
    if (p != null) controller.submit(p);
  }

  /// Teams that buzz only on their own phones, so the host screen hides their
  /// buzzer: in a face-off, the named player's phone has joined; otherwise
  /// every player on the team has one (anyone without still needs the host).
  Set<int> phoneTeams() {
    final f = faceOff();
    return {
      for (var t = 0; t < tournament.teamCount; t++)
        if (f != null
            ? f.players[t] != null && room.memberFor(t, f.players[t]!) != null
            : tournament.config.teams[t].players.isNotEmpty &&
                tournament.config.teams[t].players.every((n) => room.memberFor(t, n) != null))
          t,
    };
  }

  /// A team buzzed on the host phone: they answer there, not on a phone.
  void localBuzz() {
    remote = null;
    notifyListeners();
  }

  void _onChange() {
    if (controller.phase != BuzzPhase.answering && remote != null) {
      remote = null;
      notifyListeners();
    }
    _publish();
  }

  Map<String, Object?> _view() {
    final c = controller;
    final f = faceOff();
    final answering = c.answeringTeam;
    final resolved = c.phase == BuzzPhase.resolved || c.phase == BuzzPhase.finished;
    final o = c.outcome;
    return {
      'kind': 'buzz',
      'mode': c.mode.name,
      'title': title,
      'q': questionKey,
      'n': '${c.questionIndex + 1}/${c.questions.length}',
      'prompt': prompt,
      // Nothing until the host's face-off intro is dismissed — no head start.
      'question': paused() ? const <String, Object?>{} : question(),
      'round': '${tournament.roundNumber.clamp(1, tournament.totalRounds)}/${tournament.totalRounds}',
      'phase': paused() && c.phase == BuzzPhase.open ? 'ready' : c.phase.name,
      'teams': teamsView(tournament),
      'canBuzz': [for (var i = 0; i < tournament.teamCount; i++) if (c.canBuzz(i)) i],
      if (f != null) 'faceOff': {for (final e in f.players.entries) '${e.key}': e.value},
      if (answering != null)
        'answering': {
          'team': answering,
          'name': remote?.name ?? f?.nameFor(answering) ?? tournament.teamName(answering),
          if (remote != null) 'device': remote!.device,
        },
      if (c.phase == BuzzPhase.answering && remote != null) 'answers': answerIds().toList(),
      if (resolved)
        'result': {
          'scored': o?.scored ?? false,
          if (o != null && o.scored) 'team': o.team,
          if (o?.player != null) 'player': o!.player!.name,
          'points': (o?.points ?? 0) * multiplier,
          'reveal': reveal().take(30).toList(),
        },
    };
  }

  String? _lastShape;

  /// The clock as last sent, and how long ago: phones count down from it.
  double? _sentLeft;
  final Stopwatch _sinceSent = Stopwatch();
  static const _resync = Duration(seconds: 3);

  void _publish() {
    final v = _view();
    final ticking = controller.phase == BuzzPhase.open || controller.phase == BuzzPhase.answering;
    // The clock isn't sent every frame — with each change, then every few
    // seconds or whenever it's drifted from the phones' countdown (a reset,
    // a pause), so a phone can never get stuck on a stale clock.
    final shape = jsonEncode(v);
    final sent = _sentLeft;
    final drifted = ticking &&
        !paused() &&
        (sent == null ||
            _sinceSent.elapsed >= _resync ||
            (sent - _sinceSent.elapsedMilliseconds / 1000 - controller.secondsLeft).abs() > 0.5);
    if (shape == _lastShape && !drifted) return;
    _lastShape = shape;
    if (ticking) {
      v['left'] = (controller.secondsLeft * 10).round() / 10;
      v['total'] = (controller.phaseSeconds * 10).round() / 10;
      _sentLeft = controller.secondsLeft;
      _sinceSent
        ..reset()
        ..start();
    } else {
      _sentLeft = null;
    }
    room.show(v);
  }

  @override
  void dispose() {
    _window?.cancel();
    controller.removeListener(_onChange);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
