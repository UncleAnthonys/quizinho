import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';

enum Sfx {
  tick('tick'),
  tickFast('tick_fast'),
  spinTick('spin_tick'),
  countdownBeep('countdown_beep'),
  whistle('whistle'),
  buzzIn('buzz_in'),
  wrong('wrong'),
  correct('correct'),
  boom('boom'),
  cheer('cheer'),
  groan('groan'),
  reveal('reveal'),
  fanfare('fanfare');

  const Sfx(this.file);
  final String file;
  String get asset => 'sounds/$file.wav';
}

/// Fire-and-forget sound effects from bundled files (instant, offline).
/// Sound must never break gameplay, so every failure is swallowed.
class SoundService {
  SoundService(this._settings);

  final AppSettings _settings;
  final Map<Sfx, List<AudioPlayer>> _pools = {};
  final Map<Sfx, int> _next = {};

  /// Rapid-fire sounds get more players so overlapping plays don't cut off.
  static const _poolSizes = {Sfx.spinTick: 4, Sfx.tick: 3, Sfx.tickFast: 3};

  Future<void> init() async {
    try {
      await AudioCache.instance.loadAll([for (final s in Sfx.values) s.asset]);
      for (final s in Sfx.values) {
        _pools[s] = [
          for (var i = 0; i < (_poolSizes[s] ?? 2); i++) AudioPlayer()..setReleaseMode(ReleaseMode.stop),
        ];
      }
    } catch (e) {
      debugPrint('Sound init failed: $e');
    }
  }

  void play(Sfx s, {double volume = 1.0}) {
    if (!_settings.soundOn) return;
    final pool = _pools[s];
    if (pool == null || pool.isEmpty) return;
    final i = (_next[s] ?? 0) % pool.length;
    _next[s] = i + 1;
    unawaited(_play(pool[i], s, volume));
  }

  Future<void> _play(AudioPlayer p, Sfx s, double volume) async {
    try {
      await p.stop();
      // lowLatency is a mobile-only mode; browsers use the standard player.
      await p.play(AssetSource(s.asset), volume: volume, mode: kIsWeb ? PlayerMode.mediaPlayer : PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('Sound ${s.file} failed: $e');
    }
  }
}
