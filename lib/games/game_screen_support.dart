import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:flutter/widgets.dart';

import '../core/app_services.dart';
import '../core/commentary.dart' show PunditMoment;
import '../core/sound_service.dart';
import '../domain/tournament.dart';
import '../multiplayer/room.dart' show HostRoom;
import 'buzz_race_controller.dart' show GameEvent;

/// What every game screen receives from the tournament flow.
class RoundContext {
  const RoundContext({required this.tournament, required this.multiplier, required this.onComplete});
  final Tournament tournament;

  /// 2 on a wildcard round.
  final int multiplier;
  final void Function(RoundResult result) onComplete;
}

/// Shared plumbing for game screens: a frame-accurate game clock and the
/// sound/haptic/commentary reactions to game events.
mixin GameScreenSupport<W extends StatefulWidget> on State<W>, TickerProviderStateMixin<W> {
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  String? commentaryText;
  Timer? _commentaryTimer;
  int _seenSerial = 0;
  double? _clockSeen;
  bool _firstSaid = false;

  AppServices get services => AppScope.read(context);

  /// The room's phones for this round — none in solo play (one team).
  HostRoom? roomFor(Tournament t) => t.teamCount > 1 ? services.room : null;

  /// Whose go it is in a turn game: round the team's players who've joined
  /// on their own phone. Nobody joined: the team's go on this phone (null).
  String? phoneTurnPlayer(Tournament t, int team) {
    final room = roomFor(t);
    final names = t.config.teams[team].players;
    if (room == null || !names.any((n) => room.memberFor(team, n) != null)) return null;
    for (var i = 0; i < names.length; i++) {
      final n = t.nextTurnPlayer(team);
      if (n != null && room.memberFor(team, n) != null) return n;
    }
    return null;
  }

  /// Start calling [onTick] every frame with the time since the last frame.
  void startClock(void Function(Duration dt) onTick) {
    _ticker?.dispose();
    _lastTick = Duration.zero;
    _ticker = createTicker((elapsed) {
      final dt = elapsed - _lastTick;
      _lastTick = elapsed;
      if (dt > Duration.zero && dt < const Duration(milliseconds: 500)) onTick(dt);
    })
      ..start();
  }

  /// Call from the controller listener; reacts once per new event.
  /// [moment]: a pundit line for the moment, in place of the usual one.
  /// [clock]: seconds left on the go, every call (a right answer with 3 or
  /// fewer left gets its own line). [matchStart]: no rounds played yet (the
  /// match's first right answer gets its own line). [correctLine]: this
  /// screen's own line for a right answer. [line]: this screen's own line, whatever happened.
  void handleEvent(int serial, GameEvent? event,
      {String? miss, PunditMoment? moment, double? clock, bool matchStart = false, String? correctLine, String? line}) {
    final clockBefore = _clockSeen;
    _clockSeen = clock;
    if (event == null || serial == _seenSerial) return;
    _seenSerial = serial;
    final s = services;
    // (A wrong answer shakes the question card - MissShake, in each game's
    // view - and a time-out is plain from the clock: no message.)
    switch (event) {
      case GameEvent.buzz:
        s.sound.play(Sfx.buzzIn);
        s.haptic(HapticStrength.heavy);
      case GameEvent.correct || GameEvent.steal || GameEvent.deepCut:
        s.sound.play(Sfx.correct);
        s.sound.play(Sfx.cheer, volume: 0.7);
        s.haptic(HapticStrength.medium);
      case GameEvent.wrong:
        s.sound.play(Sfx.wrong);
        s.haptic(HapticStrength.heavy);
      case GameEvent.timeUp:
        // A go running out of time. The whistle is kept for kick-off and full time.
        s.sound.play(Sfx.wrong);
        s.haptic(HapticStrength.heavy);
      case GameEvent.nobodyGotIt:
        s.sound.play(Sfx.groan);
      case GameEvent.reveal:
        s.sound.play(Sfx.reveal, volume: 0.6);
        s.haptic(HapticStrength.tick);
      case GameEvent.explode || GameEvent.eliminated:
        s.sound.play(Sfx.boom);
        s.haptic(HapticStrength.heavy);
        if (event == GameEvent.eliminated) s.sound.play(Sfx.groan, volume: 0.8);
      case GameEvent.complete:
        s.sound.play(Sfx.whistle);
        s.sound.play(Sfx.cheer);
    }
    final late = clockBefore != null && clockBefore > 0 && clockBefore <= 3;
    if (line != null) {
      say(line);
    } else if (moment != null) {
      say(s.commentary.moment(moment));
    } else if (event == GameEvent.correct && correctLine != null) {
      say(correctLine);
    } else if (event == GameEvent.correct && matchStart && !_firstSaid) {
      _firstSaid = true;
      say(s.commentary.first());
    } else if (event == GameEvent.correct && late) {
      say(s.commentary.late());
    } else if (event == GameEvent.buzz) {
      say(s.commentary.maybeBuzzLine());
    } else if (event != GameEvent.reveal) {
      say(s.commentary.lineFor(event));
    }
  }

  void say(String? line) {
    if (line == null || !services.settings.commentaryOn) return;
    _commentaryTimer?.cancel();
    setState(() => commentaryText = line);
    _commentaryTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => commentaryText = null);
    });
  }

  bool _tableMode = false;

  /// Buzzer games: let the phone turn sideways for table mode (the rest of
  /// the app stays portrait). Browsers rotate on their own.
  void allowTableMode() {
    _tableMode = true;
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void disposeGameSupport() {
    if (_tableMode && !kIsWeb) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _ticker?.dispose();
    _commentaryTimer?.cancel();
  }
}
