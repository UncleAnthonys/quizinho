import 'dart:async';

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

  StreamSubscription<AccelerometerEvent>? _sub;
  bool _armed = false; // must start from upright
  bool enabled = false;
  int _turns = 0;

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
    if (e.x.abs() > _trigger) {
      final turns = e.x > 0 ? 1 : 3;
      if (turns != _turns) {
        _turns = turns;
        onQuarterTurns?.call(turns);
      }
    }
    if (!enabled) {
      _armed = false;
      return;
    }
    if (!_armed) {
      if (e.z.abs() < _neutral) _armed = true;
      return;
    }
    if (e.z < -_trigger) {
      _armed = false;
      onCorrect();
    } else if (e.z > _trigger) {
      _armed = false;
      onPass();
    }
  }
}
