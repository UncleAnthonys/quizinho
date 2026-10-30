/// Not a browser: never used (apps have their own recognisers).
class HintedSpeech {
  static Future<bool> ready() async => false;

  bool listen({
    required List<String> hints,
    required void Function(String words) onWords,
    required void Function(List<String> alternatives) onDone,
  }) =>
      false;

  void stop() {}
}
