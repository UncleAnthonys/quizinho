import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'web_sfx.dart';

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
  fanfare('fanfare'),
  kick('kick'),
  ooh('ooh');

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

  /// Browsers: Web Audio, decoded up front (no lag, sounds overlap).
  WebSfx? _web;

  Future<void> init() async {
    // Sounds load first, on their own: nothing about the audio session may
    // ever stop them loading.
    if (kIsWeb && WebSfx.supported) {
      try {
        final web = WebSfx();
        await Future.wait([for (final s in Sfx.values) rootBundle.load('assets/${s.asset}').then((b) => web.load(s.file, b))]);
        _web = web;
      } catch (e) {
        debugPrint('Web Audio unavailable, using <audio>: $e');
      }
    }
    if (_web == null) {
      try {
        await AudioCache.instance.loadAll([for (final s in Sfx.values) s.asset]);
        final mode = kIsWeb ? PlayerMode.mediaPlayer : PlayerMode.lowLatency;
        for (final s in Sfx.values) {
          final pool = <AudioPlayer>[];
          for (var i = 0; i < (_poolSizes[s] ?? 2); i++) {
            // Each player holds its sound ready, so a play is just "go".
            final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
            await p.setPlayerMode(mode);
            await p.setSource(AssetSource(s.asset));
            pool.add(p);
          }
          _pools[s] = pool;
        }
      } catch (e) {
        debugPrint('Sound init failed: $e');
      }
    }
    try {
      // iPhone: share one record-capable audio session with the mic. The
      // default (playback only) switches the mic off under the recogniser
      // whenever a sound plays, e.g. the buzzer just before an answer.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await AudioPlayer.global.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.allowBluetoothA2DP,
            },
          ),
        ));
      }
    } catch (e) {
      debugPrint('Audio context failed: $e');
    }
  }

  /// Settings → Test sounds: the whistle.
  void test() => play(Sfx.whistle);

  /// Told about every sound played (the demo video adds them back in later).
  static void Function(String asset, double volume)? onPlay;

  void play(Sfx s, {double volume = 1.0}) {
    if (!_settings.soundOn) return;
    onPlay?.call(s.asset, volume);
    if (_web?.play(s.file, volume) ?? false) return;
    final pool = _pools[s];
    if (pool == null || pool.isEmpty) return;
    final i = (_next[s] ?? 0) % pool.length;
    _next[s] = i + 1;
    unawaited(_play(pool[i], s, volume));
  }

  Future<void> _play(AudioPlayer p, Sfx s, double volume) async {
    try {
      // The source is already loaded (see init): rewind if it's mid-play, then go.
      if (p.state == PlayerState.playing) await p.stop();
      await p.setVolume(volume);
      await p.resume();
    } catch (e) {
      debugPrint('Sound ${s.file} failed: $e');
    }
  }
}
