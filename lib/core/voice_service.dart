import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quizinho_speech/quizinho_speech.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_settings.dart';
import 'hinted_speech.dart';

/// Spoken answers via the device's own speech recogniser. On iPhone that's
/// Quizinho's own recogniser (Apple on-device speech taught every player's
/// name — see packages/quizinho_speech); elsewhere Google on Android or the
/// Web Speech API in browsers. No server, no per-use cost. Every failure
/// degrades to "type it instead".
class VoiceService {
  VoiceService(this._settings);

  final AppSettings _settings;
  final SpeechToText _stt = SpeechToText();
  final QuizinhoSpeech? _native = QuizinhoSpeech.supported ? QuizinhoSpeech() : null;
  StreamSubscription<SpeechEvent>? _nativeSub;
  final HintedSpeech _hinted = HintedSpeech();
  Future<String>? _model;
  bool? _available;
  VoidCallback? _onStopped;

  /// Voice is on in settings and the device hasn't said no.
  bool get enabled => _settings.voiceOn && _available != false;

  /// Builds the player-name model in the background (iPhone only). Called at
  /// launch; safe to call repeatedly. Built once per install or data update,
  /// then kept on the phone. Until it's ready, voice still works, just
  /// without the player-name boost. A failed build is retried next call.
  Future<String> prepareModel() {
    final n = _native;
    if (n == null) return Future.value('not used here');
    return _model ??= n.prepareModel().then((s) {
      if (s.startsWith('failed')) _model = null;
      return s;
    }, onError: (Object e) {
      _model = null;
      return 'failed: $e';
    });
  }

  /// What the recogniser is doing, for the voice test report.
  Future<String> describe() async {
    final n = _native;
    if (n == null) return kIsWeb ? 'browser speech' : 'system speech';
    try {
      final s = await n.status();
      return [for (final e in s.entries) '${e.key}: ${e.value}'].join('\n');
    } catch (e) {
      return 'status failed: $e';
    }
  }

  Future<bool> _init() async {
    if (_available != null) return _available!;
    if (_native case final n?) {
      try {
        _available = await n.authorize();
      } catch (e) {
        debugPrint('Speech unavailable: $e');
        _available = false;
      }
      if (_available!) unawaited(prepareModel());
      return _available!;
    }
    try {
      _available = await _stt.initialize(
        onError: (e) => debugPrint('Speech error: ${e.errorMsg}'),
        onStatus: (status) {
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
            _onStopped?.call();
          }
        },
      );
    } catch (e) {
      debugPrint('Speech unavailable: $e');
      _available = false;
    }
    return _available!;
  }

  /// Listens for one answer. [onWords] gets the live transcript; [onDone] gets
  /// the final transcript alternatives, best first (empty if nothing heard).
  /// [hints] are names worth listening for (the right answers): in Chrome,
  /// where supported, the recogniser leans towards them.
  /// Returns false if voice isn't available, so the caller can fall back.
  Future<bool> listen({
    required void Function(String words) onWords,
    required void Function(List<String> alternatives) onDone,
    List<String> hints = const [],
  }) async {
    if (!_settings.voiceOn || !await _init()) return false;
    // Browsers: our own recogniser, boosted with the answers' names where
    // Chrome can; the speech_to_text plugin only if that can't start.
    if (kIsWeb) {
      final boost = hints.isNotEmpty && await HintedSpeech.ready();
      if (_hinted.listen(hints: hints, boost: boost, onWords: onWords, onDone: onDone) ||
          (boost && _hinted.listen(hints: hints, boost: false, onWords: onWords, onDone: onDone))) {
        return true;
      }
    }
    var finished = false;
    var last = '';
    void finish(List<String> alts) {
      if (finished) return;
      finished = true;
      _onStopped = null;
      onDone(alts);
    }

    if (_native case final n?) {
      await _nativeSub?.cancel();
      _nativeSub = n.events.listen((e) {
        switch (e) {
          case SpeechPartial(:final text):
            if (!finished) onWords(text);
          case SpeechFinal(:final alternatives):
            _nativeSub?.cancel();
            _nativeSub = null;
            finish(alternatives);
        }
      });
      try {
        return await n.listen();
      } catch (e) {
        debugPrint('Speech listen failed: $e');
        await _nativeSub?.cancel();
        _nativeSub = null;
        return false;
      }
    }

    _onStopped = () => finish(last.trim().isEmpty ? const [] : [last]);
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) {
          last = r.recognizedWords;
          onWords(last);
          if (r.finalResult) {
            final alts = [
              for (final a in r.alternates)
                if (a.recognizedWords.trim().isNotEmpty) a.recognizedWords,
            ];
            finish(alts.isEmpty && last.trim().isNotEmpty ? [last] : alts);
          }
        },
        // Long windows; the answer box restarts listening whenever it stops.
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.search,
        ),
      );
    } catch (e) {
      debugPrint('Speech listen failed: $e');
      finish(const []);
      return false;
    }
    return true;
  }

  void stop() {
    _onStopped = null;
    _hinted.stop();
    if (_native case final n?) {
      _nativeSub?.cancel();
      _nativeSub = null;
      n.cancel().catchError((Object _) {});
      return;
    }
    try {
      _stt.cancel();
    } catch (_) {}
  }
}
