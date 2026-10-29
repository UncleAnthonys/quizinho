import AVFoundation
import Flutter
import Speech
import UIKit

/// Quizinho's own iOS speech recogniser: Apple's on-device recognition, taught
/// every player's name and how it's said (a custom language model, iOS 17+).
///
/// Methods on "quizinho/speech":
///   authorize() -> Bool                       speech + microphone permission
///   prepareModel({asset}) -> String           builds the player-name model (slow the first time)
///   status() -> Map                           model state, on-device support, phoneme info
///   listen({pauseMs, maxMs, contextual}) -> Bool
///   stop()                                    finish now and send what was heard
///   cancel()                                  stop without a result
/// Events on "quizinho/speech/events":
///   {type: "partial", text}   {type: "final", alts: [String]}
public class QuizinhoSpeechPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let modelId = "com.littlefortstudios.quizinho.players"

  private let registrar: FlutterPluginRegistrar
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
  /// A fresh engine per listen, made only after the session is in record mode
  /// (an engine whose input node was first touched in playback mode reports a
  /// 0 Hz format, and tapping that aborts the app).
  private var engine: AVAudioEngine?
  private var tapped = false
  private var observers: [NSObjectProtocol] = []
  private var sink: FlutterEventSink?

  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var silenceTimer: Timer?
  private var maxTimer: Timer?
  private var session = 0
  private var finished = true
  private var lastAlts: [String] = []

  /// SFSpeechLanguageModel.Configuration once the model is ready (iOS 17+).
  private var modelConfig: AnyObject?
  private var modelState = "not prepared"
  private var modelInfo: [String: Any] = [:]
  private var preparing = false

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = QuizinhoSpeechPlugin(registrar: registrar)
    let channel = FlutterMethodChannel(name: "quizinho/speech", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "quizinho/speech/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "authorize":
      authorize(result)
    case "prepareModel":
      prepareModel(asset: args["asset"] as? String ?? "assets/voice/vocab.json", result: result)
    case "status":
      var s = modelInfo
      s["model"] = modelState
      s["available"] = recognizer?.isAvailable ?? false
      s["onDevice"] = recognizer?.supportsOnDeviceRecognition ?? false
      s["ios"] = UIDevice.current.systemVersion
      result(s)
    case "listen":
      do {
        try startListening(
          pauseMs: args["pauseMs"] as? Int ?? 2000,
          maxMs: args["maxMs"] as? Int ?? 30000,
          contextual: args["contextual"] as? [String] ?? [])
        result(true)
      } catch {
        teardown()
        result(FlutterError(code: "listen", message: error.localizedDescription, details: nil))
      }
    case "stop":
      endAudio()
      result(nil)
    case "cancel":
      finished = true
      session += 1
      teardown()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Permissions

  private func authorize(_ result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async { result(false) }
        return
      }
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async { result(granted) }
      }
    }
  }

  // MARK: Player-name language model

  private func prepareModel(asset: String, result: @escaping FlutterResult) {
    guard #available(iOS 17, *) else {
      modelState = "needs iOS 17"
      result(modelState)
      return
    }
    if modelConfig != nil || preparing {
      result(modelState)
      return
    }
    preparing = true
    modelState = "preparing"
    let path = Bundle.main.path(forResource: registrar.lookupKey(forAsset: asset), ofType: nil)
    Task.detached(priority: .utility) { [weak self] in
      let outcome: (AnyObject?, String, [String: Any])
      do {
        outcome = try await QuizinhoSpeechPlugin.buildModel(vocabPath: path)
      } catch {
        outcome = (nil, "failed: \(error.localizedDescription)", [:])
      }
      await MainActor.run {
        guard let self = self else { return }
        self.modelConfig = outcome.0
        self.modelState = outcome.1
        self.modelInfo.merge(outcome.2) { _, new in new }
        self.preparing = false
        result(self.modelState)
      }
    }
  }

  @available(iOS 17, *)
  private static func buildModel(vocabPath: String?) async throws -> (AnyObject?, String, [String: Any]) {
    guard let vocabPath = vocabPath else { return (nil, "failed: vocab asset missing", [:]) }
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: vocabPath)))
    guard let doc = json as? [String: Any],
      let version = doc["version"] as? String,
      let phrases = doc["phrases"] as? [[Any]],
      let prons = doc["pronunciations"] as? [String: [String]]
    else { return (nil, "failed: vocab unreadable", [:]) }
    let locale = Locale(identifier: doc["locale"] as? String ?? "en-GB")

    let fm = FileManager.default
    let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("player_voice_model", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let dataURL = dir.appendingPathComponent("data-\(version).bin")
    let config = SFSpeechLanguageModel.Configuration(
      languageModel: dir.appendingPathComponent("lm-\(version)"),
      vocabulary: dir.appendingPathComponent("vocab-\(version)"))

    let supported = SFCustomLanguageModelData.supportedPhonemes(locale: locale)
    var info: [String: Any] = [
      "version": version,
      "phrases": phrases.count,
      "supportedPhonemes": supported.joined(separator: " "),
    ]

    if !fm.fileExists(atPath: dataURL.path) {
      for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
        try? fm.removeItem(at: old)
      }
      let allowed = Set(supported)
      let data = SFCustomLanguageModelData(locale: locale, identifier: modelId, version: version)
      for p in phrases {
        guard p.count == 2, let text = p[0] as? String, let count = p[1] as? Int else { continue }
        data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: text, count: count))
      }
      var kept = 0
      var dropped = 0
      var unknown: [String: Int] = [:]
      for (word, list) in prons {
        var ok: [String] = []
        for pron in list {
          let missing = pron.split(separator: " ").map(String.init).filter { !allowed.isEmpty && !allowed.contains($0) }
          if missing.isEmpty {
            ok.append(pron)
          } else {
            for m in missing { unknown[m, default: 0] += 1 }
          }
        }
        kept += ok.count
        dropped += list.count - ok.count
        if !ok.isEmpty {
          data.insert(term: SFCustomLanguageModelData.CustomPronunciation(grapheme: word, phonemes: ok))
        }
      }
      info["pronunciations"] = kept
      info["droppedPronunciations"] = dropped
      info["unsupportedSymbols"] = unknown.sorted { $0.value > $1.value }.prefix(15).map { "\($0.key)×\($0.value)" }
        .joined(separator: " ")
      try await data.export(to: dataURL)
    }

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      SFSpeechLanguageModel.prepareCustomLanguageModel(
        for: dataURL, clientIdentifier: modelId, configuration: config, ignoresCache: false
      ) { error in
        if let error = error { cont.resume(throwing: error) } else { cont.resume() }
      }
    }
    return (config, "ready", info)
  }

  // MARK: Listening

  private func startListening(pauseMs: Int, maxMs: Int, contextual: [String]) throws {
    session += 1
    teardown()
    guard let recognizer = recognizer, recognizer.isAvailable else {
      throw NSError(domain: "quizinho.speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recogniser unavailable"])
    }
    let audio = AVAudioSession.sharedInstance()
    // Mode .default, not .measurement: measurement turns the speaker right
    // down, so sound effects went near-silent after the first spoken answer.
    try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
    try audio.setActive(true, options: .notifyOthersOnDeactivation)

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    req.taskHint = .search
    req.contextualStrings = contextual
    if recognizer.supportsOnDeviceRecognition {
      req.requiresOnDeviceRecognition = true
      if #available(iOS 17, *), let config = modelConfig as? SFSpeechLanguageModel.Configuration {
        req.customizedLanguageModel = config
      }
    }
    if #available(iOS 16, *) { req.addsPunctuation = false }

    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw NSError(domain: "quizinho.speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Microphone not ready"])
    }
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      req.append(buffer)
    }
    self.engine = engine
    tapped = true
    engine.prepare()
    try engine.start()
    // Another sound taking over the audio session, a call, or a route change
    // (headphones) stops the engine; finish with what was heard.
    let centre = NotificationCenter.default
    observers = [
      centre.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
        self?.endAudio()
      },
      centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
        self?.endAudio()
      },
    ]

    request = req
    finished = false
    lastAlts = []
    let id = session
    task = recognizer.recognitionTask(with: req) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self = self, id == self.session, !self.finished else { return }
        if let result = result {
          let alts = result.transcriptions.map { $0.formattedString }.filter { !$0.isEmpty }
          if !alts.isEmpty { self.lastAlts = alts }
          if result.isFinal {
            self.finish(self.lastAlts)
          } else {
            self.send(["type": "partial", "text": result.bestTranscription.formattedString])
            self.armSilence(pauseMs)
          }
        } else if error != nil {
          self.finish(self.lastAlts)
        }
      }
    }
    maxTimer = Timer.scheduledTimer(withTimeInterval: Double(maxMs) / 1000, repeats: false) { [weak self] _ in
      self?.endAudio()
    }
  }

  /// After a pause in speech, stop listening; the recogniser then sends its final result.
  private func armSilence(_ pauseMs: Int) {
    silenceTimer?.invalidate()
    silenceTimer = Timer.scheduledTimer(withTimeInterval: Double(pauseMs) / 1000, repeats: false) { [weak self] _ in
      self?.endAudio()
    }
  }

  private func endAudio() {
    silenceTimer?.invalidate()
    maxTimer?.invalidate()
    guard !finished else { return }
    stopEngine()
    request?.endAudio()
    // If no final result arrives, finish with what was heard.
    let id = session
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      guard let self = self, id == self.session else { return }
      self.finish(self.lastAlts)
    }
  }

  private func finish(_ alts: [String]) {
    guard !finished else { return }
    finished = true
    send(["type": "final", "alts": alts])
    teardown()
  }

  private func teardown() {
    silenceTimer?.invalidate()
    maxTimer?.invalidate()
    silenceTimer = nil
    maxTimer = nil
    stopEngine()
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
  }

  /// Stops and releases the engine. Never touches an input node that wasn't tapped.
  private func stopEngine() {
    for o in observers { NotificationCenter.default.removeObserver(o) }
    observers = []
    guard let engine = engine else { return }
    if engine.isRunning { engine.stop() }
    if tapped { engine.inputNode.removeTap(onBus: 0) }
    tapped = false
    self.engine = nil
  }

  private func send(_ event: [String: Any]) {
    sink?(event)
  }
}
