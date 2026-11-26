import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:sensors_plus/sensors_plus.dart';

/// Turns accelerometer readings into Heads Up gestures.
///
/// Phone held upright on the forehead → z ≈ 0. Nod forward (screen to the
/// floor) → z ≈ −9.8 = correct. Tilt back (screen to the ceiling) → z ≈ +9.8
/// = pass. After each gesture the phone must return to upright before the
/// next one counts, so one nod never scores twice.
///
/// Also reports which way the phone is held sideways so the card can be
/// rotated to read correctly. Silently does nothing where there is no
/// sensor (e.g. a laptop browser) — the on-screen buttons still work.
class TiltDetector {
  TiltDetector({required this.onCorrect, required this.onPass, this.onQuarterTurns});

  final void Function() onCorrect;
  final void Function() onPass;

  /// 1 or 3: how many clockwise quarter turns make the card upright.
  final void Function(int quarterTurns)? onQuarterTurns;

  static const double _trigger = 6.5;
  static const double _neutral = 3.5;

  /// Readings are smoothed (a jolt bringing the phone back up looked like
  /// another nod and scored a card nobody had seen); the phone must then be
  /// held upright this long before the next tilt counts...
  static const _settle = Duration(milliseconds: 350);

  /// ...and a new card can't be scored this soon after the last one.
  static const _cooldown = Duration(milliseconds: 1000);
  static const double _smoothing = 0.25; // share of each new reading
  double? _z;
  DateTime? _uprightSince;
  DateTime _lastGesture = DateTime(2000);

  StreamSubscription<AccelerometerEvent>? _sub;
  bool _armed = false; // must start from upright
  bool enabled = false;
  int _turns = 0;

  /// True once the phone has reported its tilt at all (the app always does;
  /// a laptop never does; an iPhone browser only after permission). Until
  /// then the game shows Pass/Correct buttons instead.
  final ValueNotifier<bool> sensing = ValueNotifier(false);

  void start() {
    if (_sub != null) return;
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen(_onEvent, onError: (Object _) {}, cancelOnError: true);
    } catch (_) {
      _sub = null;
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onEvent(AccelerometerEvent e) {
    if (!sensing.value) sensing.value = true;
    if (e.x.abs() > _trigger) {
      final turns = e.x > 0 ? 1 : 3;
      if (turns != _turns) {
        _turns = turns;
        onQuarterTurns?.call(turns);
      }
    }
    final z = _z = _z == null ? e.z : _z! + (e.z - _z!) * _smoothing;
    if (!enabled) {
      _armed = false;
      _uprightSince = null;
      return;
    }
    final now = DateTime.now();
    if (!_armed) {
      if (z.abs() < _neutral) {
        _uprightSince ??= now;
        if (now.difference(_uprightSince!) >= _settle) _armed = true;
      } else {
        _uprightSince = null;
      }
      return;
    }
    if (now.difference(_lastGesture) < _cooldown) return;
    if (z < -_trigger) {
      _gesture(now);
      onCorrect();
    } else if (z > _trigger) {
      _gesture(now);
      onPass();
    }
  }

  void _gesture(DateTime now) {
    _armed = false;
    _uprightSince = null;
    _lastGesture = now;
  }
}
