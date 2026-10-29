import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:flutter/widgets.dart';

import '../core/app_services.dart';
import '../core/sound_service.dart';
import '../domain/tournament.dart';
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

  AppServices get services => AppScope.read(context);

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
  /// [miss]: shown on a wrong answer or time-out ("✗ Gary Cahill").
  void handleEvent(int serial, GameEvent? event, {String? miss}) {
    if (event == null || serial == _seenSerial) return;
    _seenSerial = serial;
    final s = services;
    if ((event == GameEvent.wrong || event == GameEvent.timeUp) && miss != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('✗ $miss'), duration: const Duration(milliseconds: 1800)));
    }
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
        s.sound.play(Sfx.whistle);
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
    if (event == GameEvent.buzz) {
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
