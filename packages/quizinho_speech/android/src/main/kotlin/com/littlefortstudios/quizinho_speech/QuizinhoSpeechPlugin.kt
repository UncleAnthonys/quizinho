package com.littlefortstudios.quizinho_speech

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

    // Some recognisers (on-device ones on some Samsungs) hear the words but
    // never say they're done, so listening never ends. A watchdog: when the
    // words stop changing for the pause, or the time's up, stop listening
    // and, if no final answer comes, use the last words heard.
    private val handler = Handler(Looper.getMainLooper())
    private var lastPartial = ""
    private var pauseMsNow = 2000L
    private val silence = Runnable { wrapUp() }
    private val giveUp = Runnable { if (!finished) emitFinal(if (lastPartial.isBlank()) emptyList() else listOf(lastPartial)) }

    private fun wrapUp() {
        if (finished) return
        try {
            recognizer?.stopListening()
        } catch (e: Exception) {}
        handler.removeCallbacks(giveUp)
        handler.postDelayed(giveUp, 1500)
    }

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

    /** Connected to a working internet (Wi-Fi or data). */
    private fun online(): Boolean = try {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    } catch (e: Exception) {
        false
    }

    private fun onDeviceAvailable(): Boolean =
        Build.VERSION.SDK_INT >= 33 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "authorize" -> result.success(micAllowed() && SpeechRecognizer.isRecognitionAvailable(context))
            "prepareModel" -> result.success("ready") // nothing to build on Android
            "status" -> result.success(
                mapOf(
                    "recogniser" to if (online()) "Google online" else if (onDeviceAvailable()) "Google on-device (offline)" else "system",
                    "name boost" to if (!online() && onDeviceAvailable()) "answers biased (Android 13+)" else "none (online)",
                )
            )
            "listen" -> {
                val hints = call.argument<List<String>>("contextual") ?: emptyList()
                val pauseMs = call.argument<Int>("pauseMs") ?: 2000
                val maxMs = call.argument<Int>("maxMs") ?: 30000
                // Voice test only: force one way of listening to compare them.
                // "auto" (games): on-device with the answers when the phone has it.
                val mode = call.argument<String>("mode") ?: "auto"
                val onDevice = when (mode) {
                    "server", "serverSearch" -> false
                    "device" -> onDeviceAvailable()
                    // Games: Google's online recogniser whenever there's
                    // internet - on a real phone (Galaxy A13) it got 84% of
                    // hard names where on-device misheard and hung. On-device
                    // (with the answers' names) only when offline.
                    else -> !online() && hints.isNotEmpty() && onDeviceAvailable()
                }
                result.success(listen(hints, pauseMs, onDevice = onDevice, search = mode == "serverSearch", maxMs = maxMs))
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
        handler.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
    }

    private fun emitFinal(alternatives: List<String>) {
        if (finished) return
        finished = true
        handler.removeCallbacksAndMessages(null)
        sink?.success(mapOf("type" to "final", "alts" to alternatives))
    }

    private fun listen(hints: List<String>, pauseMs: Int, onDevice: Boolean, search: Boolean = false, maxMs: Int = 30000): Boolean {
        destroy()
        finished = false
        lastPartial = ""
        pauseMsNow = pauseMs.toLong()
        handler.postDelayed({ wrapUp() }, maxMs.toLong())
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
                if (finished) return
                if (text.isNotBlank() && text != lastPartial) {
                    lastPartial = text
                    handler.removeCallbacks(silence)
                    handler.postDelayed(silence, pauseMsNow + 500)
                }
                sink?.success(mapOf("type" to "partial", "text" to text))
            }

            override fun onResults(results: Bundle?) {
                val alts = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.toList().orEmpty()
                emitFinal(if (alts.isEmpty() && lastPartial.isNotBlank()) listOf(lastPartial) else alts)
            }

            override fun onError(error: Int) {
                // On-device speech not downloaded for English: try the normal one.
                if (onDevice && (error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                        error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE)) {
                    listen(hints, pauseMs, onDevice = false, search = search, maxMs = maxMs)
                    return
                }
                emitFinal(if (lastPartial.isBlank()) emptyList() else listOf(lastPartial))
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            // Web search mode is tuned for search queries, which are full of
            // names - maybe better at footballers on the online recogniser.
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                if (search) RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH else RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
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
