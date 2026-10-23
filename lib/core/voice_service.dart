import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_settings.dart';

/// Spoken answers via the device's own speech recogniser (Apple Speech on
/// iOS, Google on Android, the Web Speech API in Chrome/Safari). No server,
/// no per-use cost. Every failure degrades to "type it instead".
class VoiceService {
  VoiceService(this._settings);

  final AppSettings _settings;
  final SpeechToText _stt = SpeechToText();
  bool? _available;
  VoidCallback? _onStopped;

  /// Voice is on in settings and the device hasn't said no.
  bool get enabled => _settings.voiceOn && _available != false;

  Future<bool> _init() async {
    if (_available != null) return _available!;
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
  /// Returns false if voice isn't available, so the caller can fall back.
  Future<bool> listen({
    required void Function(String words) onWords,
    required void Function(List<String> alternatives) onDone,
  }) async {
    if (!_settings.voiceOn || !await _init()) return false;
    var finished = false;
    var last = '';
    void finish(List<String> alts) {
      if (finished) return;
      finished = true;
      _onStopped = null;
      onDone(alts);
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
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
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
    try {
      _stt.cancel();
    } catch (_) {}
  }
}
