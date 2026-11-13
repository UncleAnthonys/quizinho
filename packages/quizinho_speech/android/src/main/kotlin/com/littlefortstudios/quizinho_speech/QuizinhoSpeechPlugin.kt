package com.littlefortstudios.quizinho_speech

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Quizinho's Android recogniser, the same channels as the iOS one.
 *
 * Android has no equivalent of Apple's custom language model, so the boost
 * here is per question: the right answers' names go in as biasing strings
 * (Android 13+, Google's on-device recogniser), so it leans towards
 * "Kalajdžić" rather than "collage itch". Without on-device speech it falls
 * back to the phone's normal recogniser; the app's name matching does the rest.
 *
 * The microphone permission is asked for by speech_to_text before this runs.
 */
class QuizinhoSpeechPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var finished = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "quizinho/speech").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "quizinho/speech/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        destroy()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun micAllowed(): Boolean =
        Build.VERSION.SDK_INT < 23 ||
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun onDeviceAvailable(): Boolean =
        Build.VERSION.SDK_INT >= 33 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "authorize" -> result.success(micAllowed() && SpeechRecognizer.isRecognitionAvailable(context))
            "prepareModel" -> result.success("ready") // nothing to build on Android
            "status" -> result.success(
                mapOf(
                    "recogniser" to if (onDeviceAvailable()) "Google on-device" else "system",
                    "name boost" to if (onDeviceAvailable()) "answers biased (Android 13+)" else "none (no on-device speech)",
                )
            )
            "listen" -> {
                val hints = call.argument<List<String>>("contextual") ?: emptyList()
                val pauseMs = call.argument<Int>("pauseMs") ?: 2000
                result.success(listen(hints, pauseMs, onDevice = hints.isNotEmpty() && onDeviceAvailable()))
            }
            "stop" -> {
                recognizer?.stopListening()
                result.success(null)
            }
            "cancel" -> {
                destroy()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun destroy() {
        recognizer?.destroy()
        recognizer = null
    }

    private fun emitFinal(alternatives: List<String>) {
        if (finished) return
        finished = true
        sink?.success(mapOf("type" to "final", "alts" to alternatives))
    }

    private fun listen(hints: List<String>, pauseMs: Int, onDevice: Boolean): Boolean {
        destroy()
        finished = false
        val r = try {
            if (onDevice && Build.VERSION.SDK_INT >= 31) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            else SpeechRecognizer.createSpeechRecognizer(context)
        } catch (e: Exception) {
            return false
        }
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
                if (!finished) sink?.success(mapOf("type" to "partial", "text" to text))
            }

            override fun onResults(results: Bundle?) {
                emitFinal(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.toList() ?: emptyList())
            }

            override fun onError(error: Int) {
                // On-device speech not downloaded for English: try the normal one.
                if (onDevice && (error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                        error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE)) {
                    listen(hints, pauseMs, onDevice = false)
                    return
                }
                emitFinal(emptyList())
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-GB")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, pauseMs.toLong())
            if (Build.VERSION.SDK_INT >= 33 && hints.isNotEmpty()) {
                putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(hints.take(MAX_HINTS)))
            }
        }
        return try {
            r.startListening(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val MAX_HINTS = 100
    }
}
