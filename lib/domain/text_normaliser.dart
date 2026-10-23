/// Turns "Ibrahimović", "IBRAHIMOVIC" and "ibrahimovic!" into the same key.
///
/// Dart has no built-in Unicode decomposition, so accented Latin characters
/// that appear in footballer names are folded with an explicit table.
library;

const Map<String, String> _fold = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
  'æ': 'ae',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'ď': 'd', 'đ': 'd', 'ð': 'd',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
  'ğ': 'g',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i', 'ī': 'i',
  'ł': 'l', 'ľ': 'l',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
  'œ': 'oe',
  'ř': 'r',
  'ś': 's', 'š': 's', 'ş': 's', 'ș': 's', 'ß': 'ss',
  'ť': 't', 'ț': 't', 'ţ': 't',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ž': 'z', 'ź': 'z', 'ż': 'z',
};

final RegExp _nonAlnum = RegExp(r'[^a-z0-9 ]');
final RegExp _spaces = RegExp(r'\s+');

/// Lower-case, strip accents and punctuation, collapse whitespace.
/// Hyphens and apostrophes become spaces/nothing: "Alexander-Arnold" →
/// "alexander arnold", "Eto'o" → "etoo".
String normaliseName(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == "'" || ch == '’' || ch == '.') continue;
    if (ch == '-') {
      buf.write(' ');
      continue;
    }
    buf.write(_fold[ch] ?? ch);
  }
  return buf.toString().replaceAll(_nonAlnum, ' ').replaceAll(_spaces, ' ').trim();
}

/// Classic edit distance, used for typo-tolerant and (later) speech matching.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// 1.0 = identical, 0.0 = nothing in common.
double similarity(String a, String b) {
  final longest = a.length > b.length ? a.length : b.length;
  if (longest == 0) return 1;
  return 1 - levenshtein(a, b) / longest;
}

/// A rough "how it sounds" key for matching speech-to-text output against
/// footballer names: "luiz" and "louise" → "ls"; "van dijk" and "van dyke"
/// → "vndk"; "mbappe" and "embappe" → "mbp". Input must already be
/// [normaliseName]d. Consonant skeleton only — vowels are what speech
/// recognisers get wrong most often.
String soundKey(String normalised) {
  var s = normalised.replaceAll(' ', '');
  const rules = [
    ('sch', 'sh'), ('sz', 's'), ('cz', 'ch'), ('ph', 'f'), ('ck', 'k'), ('qu', 'k'),
    ('q', 'k'), ('x', 'ks'), ('th', 't'), ('ij', 'i'), ('gh', 'g'), ('dj', 'j'), ('kh', 'k'),
  ];
  for (final (from, to) in rules) {
    s = s.replaceAll(from, to);
  }
  s = s.replaceAllMapped(RegExp(r'c(?=[eiy])'), (_) => 's');
  final buf = StringBuffer();
  String? prev;
  for (final ch in s.split('')) {
    var c = ch;
    if (c == 'c') c = 'k';
    if (c == 'z') c = 's';
    if (c == 'w') c = 'v';
    if ('aeiouyh'.contains(c)) {
      prev = null; // vowels separate doubled consonants ("anna" vs "ana" still collapse below)
      continue;
    }
    if (c == prev) continue;
    buf.write(c);
    prev = c;
  }
  return buf.toString();
}
