import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

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
  fanfare('fanfare'),
  kick('kick'),
  ooh('ooh');

  const Sfx(this.file);
  final String file;
  String get asset => 'sounds/$file.wav';
}

/// Pundit lines for big moments. Placeholders until a voice actor records
/// them: only TestFlight builds carry the files (see codemagic.yaml), so
/// elsewhere playing one silently does nothing.
enum Clip {
  /// Kick-off: "I would love it if we beat them".
  keegan('keegan'),

  /// Nobody even tried an obvious one: "That is a bad one".
  neville('neville'),

  /// Final whistle: "We'll have a look, course we'll have a look".
  mcmanaman('mcmanaman'),

  /// Face-off, both missed an obvious one: "Leave the football before the football leaves you".
  carragher('carragher'),

  /// A team tried and missed an obvious one: "The game's gone".
  gamesGone('games_gone'),

  /// Same team wrong twice in a row: "It can't go on like this, can it? It can."
  mccarthy('mccarthy');

  const Clip(this.file);
  final String file;
  String get asset => 'clips/$file.m4a';
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
    // Sounds load first, on their own: nothing about the audio session may
    // ever stop them loading.
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

  AudioPlayer? _clipPlayer;

  /// How many pundit clips this build carries (0 = not a TestFlight build
  /// with the clips unpacked).
  Future<int> clipsInBuild() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets().where((a) => a.startsWith('assets/clips/') && a.endsWith('.m4a')).length;
    } catch (_) {
      return 0;
    }
  }

  /// Settings → Test sounds: a whistle, then a clip, ignoring the cooldowns.
  Future<void> test() async {
    _clipPlayed.clear();
    _lastClip = null;
    play(Sfx.whistle);
    playClip(Clip.keegan, delay: const Duration(milliseconds: 1200));
  }
  final Map<Clip, DateTime> _clipPlayed = {};
  DateTime? _lastClip;

  /// A pundit line, at most one at a time and not the same line twice in a
  /// minute, so they stay a treat. Off with sound or commentary.
  void playClip(Clip c, {Duration delay = Duration.zero}) {
    if (!_settings.soundOn || !_settings.commentaryOn) return;
    final now = DateTime.now();
    final last = _clipPlayed[c];
    if (last != null && now.difference(last) < const Duration(seconds: 60)) return;
    if (_lastClip != null && now.difference(_lastClip!) < const Duration(seconds: 6)) return;
    _clipPlayed[c] = now;
    _lastClip = now;
    unawaited(Future.delayed(delay, () async {
      try {
        final p = _clipPlayer ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await p.stop();
        await p.play(AssetSource(c.asset));
      } catch (e) {
        debugPrint('Clip ${c.file} unavailable: $e');
      }
    }));
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
