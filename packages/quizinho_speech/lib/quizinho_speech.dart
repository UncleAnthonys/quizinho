import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One update from the recogniser: live words while speaking, then the final
/// transcript alternatives (best first; empty if nothing was heard).
sealed class SpeechEvent {}

class SpeechPartial extends SpeechEvent {
  SpeechPartial(this.text);
  final String text;
}

class SpeechFinal extends SpeechEvent {
  SpeechFinal(this.alternatives);
  final List<String> alternatives;
}

/// Quizinho's own iOS recogniser: Apple on-device speech with a custom
/// language model of every player's name (iOS 17+). Other platforms use the
/// generic recogniser instead — check [supported].
class QuizinhoSpeech {
  static const _methods = MethodChannel('quizinho/speech');
  static const _eventChannel = EventChannel('quizinho/speech/events');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  late final Stream<SpeechEvent> events = _eventChannel.receiveBroadcastStream().map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    return m['type'] == 'final'
        ? SpeechFinal([for (final a in (m['alts'] as List? ?? const [])) a as String])
        : SpeechPartial(m['text'] as String? ?? '');
  });

  Future<bool> authorize() async => await _methods.invokeMethod<bool>('authorize') ?? false;

  /// Builds the player-name model from the bundled vocabulary. Slow the first
  /// time after install or a data update; returns "ready" or the reason not.
  Future<String> prepareModel([String asset = 'assets/voice/vocab.json']) async =>
      await _methods.invokeMethod<String>('prepareModel', {'asset': asset}) ?? 'unknown';

  Future<Map<String, Object?>> status() async =>
      Map<String, Object?>.from(await _methods.invokeMethod<Map>('status') ?? const {});

  Future<bool> listen({
    Duration pause = const Duration(seconds: 2),
    Duration max = const Duration(seconds: 30),
    List<String> contextual = const [],
  }) async =>
      await _methods.invokeMethod<bool>('listen', {
        'pauseMs': pause.inMilliseconds,
        'maxMs': max.inMilliseconds,
        'contextual': contextual,
      }) ??
      false;

  Future<void> stop() => _methods.invokeMethod('stop');

  Future<void> cancel() => _methods.invokeMethod('cancel');
}
