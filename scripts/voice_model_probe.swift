// Builds the player-name speech model on a Mac, exactly as the iPhone app
// does, and reports how big and how slow it is and which pronunciation
// symbols Apple accepts. Run in CI:  swift scripts/voice_model_probe.swift
import Foundation
import Speech

func now() -> Double { Date().timeIntervalSince1970 }

let vocabPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/voice/vocab.json"
let doc = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: vocabPath))) as! [String: Any]
let phrases = doc["phrases"] as! [[Any]]
let prons = doc["pronunciations"] as! [String: [String]]
let locale = Locale(identifier: doc["locale"] as? String ?? "en-GB")

let supported = SFCustomLanguageModelData.supportedPhonemes(locale: locale)
print("supported phonemes (\(supported.count)): \(supported.joined(separator: " "))")
let allowed = Set(supported)

let t0 = now()
let data = SFCustomLanguageModelData(locale: locale, identifier: "com.littlefortstudios.quizinho.players",
                                     version: doc["version"] as? String ?? "probe")
for p in phrases {
  guard p.count == 2, let text = p[0] as? String, let count = p[1] as? Int else { continue }
  data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: text, count: count))
}
var kept = 0, dropped = 0
var unknown: [String: Int] = [:]
for (word, list) in prons {
  var ok: [String] = []
  for pron in list {
    let missing = pron.split(separator: " ").map(String.init).filter { !allowed.isEmpty && !allowed.contains($0) }
    if missing.isEmpty { ok.append(pron) } else { for m in missing { unknown[m, default: 0] += 1 } }
  }
  kept += ok.count
  dropped += list.count - ok.count
  if !ok.isEmpty { data.insert(term: SFCustomLanguageModelData.CustomPronunciation(grapheme: word, phonemes: ok)) }
}
print("phrases: \(phrases.count)  pronunciations kept: \(kept)  dropped: \(dropped)")
print("unsupported symbols: \(unknown.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))")

let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quizinho-lm-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let bin = dir.appendingPathComponent("data.bin")
try await data.export(to: bin)
let t1 = now()
let size = (try FileManager.default.attributesOfItem(atPath: bin.path)[.size] as? NSNumber)?.intValue ?? 0
print(String(format: "export: %.1fs, %.2f MB", t1 - t0, Double(size) / 1_048_576))

let config = SFSpeechLanguageModel.Configuration(languageModel: dir.appendingPathComponent("lm"),
                                                 vocabulary: dir.appendingPathComponent("vocab"))
do {
  try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
    SFSpeechLanguageModel.prepareCustomLanguageModel(for: bin, clientIdentifier: "com.littlefortstudios.quizinho.players",
                                                     configuration: config, ignoresCache: true) { error in
      if let error = error { cont.resume(throwing: error) } else { cont.resume() }
    }
  }
  let t2 = now()
  var total = 0
  for case let f as URL in FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])! {
    total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  }
  print(String(format: "prepare: %.1fs, model on disk %.2f MB", t2 - t1, Double(total) / 1_048_576))
} catch {
  print("prepare failed: \(error)")
}
