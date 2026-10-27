"""How players' names are *said*, written the way an English speaker would
spell it, so the app can match what the phone's speech recogniser hears.

The app always matches the plain spelling read as English ("odegaard"); this
adds a respelling of the native pronunciation ("urdegord") for players whose
names follow another language's rules, plus hand-made fixes from real voice
tests (seed/spoken_overrides.json).

Rules are per language, chosen by nationality, or by tell-tale letters when
the nationality is missing. They aim at how an English speaker approximates
the native sound, not at a perfect transcription.
"""
from __future__ import annotations

import re
import unicodedata

_LANG_BY_NAT = {
    "pl": ["POL"],
    "scand": ["NOR", "DEN", "SWE", "ISL", "FRO"],
    "fi": ["FIN"],
    "slav": ["SRB", "CRO", "BIH", "SVN", "MNE", "MKD", "YUG", "SCG"],
    "cz": ["CZE", "SVK", "CSK"],
    "pt": ["POR", "BRA", "ANG", "CPV", "MOZ", "GNB", "STP"],
    "es": ["ESP", "ARG", "MEX", "URU", "COL", "CHI", "PER", "PAR", "ECU", "VEN", "BOL", "CRC", "HON",
           "SLV", "GUA", "PAN", "CUB", "DOM", "NCA", "EQG"],
    "nl": ["NED", "SUR"],
    "de": ["GER", "AUT", "SUI", "FRG", "GDR", "LIE"],
    "fr": ["FRA", "CIV", "SEN", "CMR", "ALG", "MAR", "TUN", "MLI", "GUI", "COD", "CGO", "GAB", "BEN",
           "BFA", "TOG", "HAI", "MTQ", "GLP", "GUF", "REU", "NCL", "MAD", "COM", "LUX", "MON", "NIG", "CTA",
           "CHA", "BDI", "RWA", "DJI", "MTN"],
    "it": ["ITA", "SMR"],
    "tr": ["TUR", "AZE"],
    "hu": ["HUN"],
    "ro": ["ROU", "MDA"],
    "sq": ["ALB", "KVX", "KOS"],
}
LANG_OF = {nat: lang for lang, nats in _LANG_BY_NAT.items() for nat in nats}

# Letters that give a name's language away when nationality is missing.
_TELLS = [
    ("pl", re.compile(r"[łęąśźżń]")),
    ("cz", re.compile(r"[řěů]")),
    ("slav", re.compile(r"[ćčđ]|dž")),
    ("scand", re.compile(r"[øåæ]")),
    ("pt", re.compile(r"[ãõ]")),
    ("es", re.compile(r"ñ")),
    ("de", re.compile(r"ß")),
    ("hu", re.compile(r"[őű]")),
    ("ro", re.compile(r"[șță]")),
    ("tr", re.compile(r"[ğış]")),
]

V = "aeiouy"

# Ordered (pattern, replacement) per language; applied to one lower-case word
# that still has its accents. Upper-case letters are temporary placeholders.
RULES: dict[str, list[tuple[str, str]]] = {
    "pl": [("szcz", "Q"), ("sz", "S"), ("cz", "C"), ("rz", "Z"), ("ch", "h"), ("ł", "w"), ("ś", "S"),
           ("ć", "C"), ("[żź]", "Z"), ("dzi", "Ji"), ("ci", "Ci"), ("si", "Si"), ("zi", "Zi"), ("ń", "n"),
           ("ę", "e"), ("ą", "on"), ("ó", "u"), ("w", "v"), ("ie", "ye"), ("j", "y"), ("c", "ts"),
           ("Q", "shch"), ("S", "sh"), ("C", "ch"), ("Z", "zh"), ("J", "j")],
    "scand": [("øj", "oy"), ("ø", "ur"), ("ö", "ur"), ("å", "o"), ("aa", "o"), ("æ", "e"), ("ä", "e"),
              ("ej", "ay"), ("skj", "sh"), ("sj", "sh"), ("kj", "ch"), ("tj", "ch"), ("hj", "y"),
              ("j", "y"), ("[ðþ]", "th")],
    "fi": [("ä", "a"), ("ö", "ur"), ("y", "u"), ("j", "y"), ("aa", "ah"), ("ii", "ee"), ("uu", "oo")],
    "slav": [("dž", "j"), ("đ", "j"), ("[ćč]", "ch"), ("š", "sh"), ("ž", "zh"), ("lj", "ly"),
             ("nj", "ny"), ("j", "y"), ("c(?!h)", "ts")],
    "cz": [("ch", "H"), ("č", "ch"), ("š", "sh"), ("ž", "zh"), ("ř", "rzh"), ("ě", "ye"), ("ň", "ny"),
           ("ť", "ty"), ("ď", "dy"), ("ů", "oo"), ("j", "y"), ("c(?!h)", "ts"), ("H", "h")],
    "pt": [("ões", "oysh"), ("ão", "ow"), ("ãe", "ine"), ("ã", "an"), ("õ", "on"), ("lh", "ly"),
           ("nh", "ny"), ("ç", "s"), ("ch", "sh"), ("x", "sh"), ("j", "zh"), ("qu(?=[ei])", "k"),
           ("gu(?=[ei])", "g"), ("ou", "o"), (f"(?<=[{V}])s(?=[{V}])", "z")],
    "es": [("ñ", "ny"), ("ll", "y"), ("^x", "sh"), ("j", "h"), ("gu(?=[ei])", "G"), ("g(?=[ei])", "h"),
           ("qu", "k"), ("ü", "w"), ("G", "g")],
    "nl": [("ij", "eye"), ("ei", "eye"), ("oe", "oo"), ("ui", "ow"), ("ou", "ow"), ("aa", "ah"),
           ("ee", "ay"), ("sch", "sk"), ("j", "y"), ("w", "v")],
    "de": [("tsch", "ch"), ("sch", "sh"), ("ei", "eye"), ("ie", "ee"), ("[eä]u", "oy"), ("ü", "oo"),
           ("ö", "ur"), ("ä", "e"), ("ß", "ss"), ("v", "f"), ("w", "v"), ("tz", "ts"), ("z", "ts"), ("j", "y"),
           ("ch", "k")],
    "fr": [("eau", "o"), ("aux$", "o"), ("au", "o"), ("oi", "wa"), ("ou", "oo"), ("qu", "k"),
           ("th", "t"), ("ch", "sh"), ("gn", "ny"), ("ç", "s"), ("j", "zh"), ("g(?=[eiy])", "zh"),
           ("é", "ay"), ("[èê]", "e"), ("e[rzt]$", "ay"), (f"(?<=[{V}])[stdxz]$", ""), ("eu", "ur"),
           ("ain$", "an"), ("in$", "an"), ("^h", "")],
    "it": [("gli", "ly"), ("gn", "ny"), ("sc(?=[ei])", "sh"), ("cch", "k"), ("ch", "k"),
           ("cc(?=[ei])", "ch"), ("ci(?=[aou])", "ch"), ("c(?=[ei])", "ch"), ("gh", "G"),
           ("gi(?=[aou])", "j"), ("g(?=[ei])", "j"), ("zz", "ts"), ("z", "ts"), ("G", "g")],
    "tr": [("ç", "ch"), ("ş", "sh"), ("ğ", ""), ("ı", "i"), ("c", "j"), ("ö", "ur"), ("ü", "oo")],
    "hu": [("sz", "S"), ("cs", "ch"), ("zs", "zh"), ("s", "sh"), ("S", "s"), ("gy", "dy"), ("ly", "y"),
           ("c(?!h)", "ts"), ("[öő]", "ur"), ("[üű]", "oo"), ("á", "ah"), ("é", "ay")],
    "ro": [("[șş]", "sh"), ("[țţ]", "ts"), ("ă", "u"), ("[âî]", "i"), ("ch(?=[ei])", "K"),
           ("c(?=[ei])", "ch"), ("gh(?=[ei])", "G"), ("g(?=[ei])", "j"), ("K", "k"), ("G", "g")],
    "sq": [("xh", "j"), ("gj", "J"), ("ç", "ch"), ("q", "ch"), ("ë", ""), ("c(?!h)", "ts"), ("j", "y"),
           ("x", "dz"), ("dh", "th"), ("J", "j")],
}
_COMPILED = {lang: [(re.compile(p), r) for p, r in rules] for lang, rules in RULES.items()}

_FOLD = str.maketrans({"ł": "l", "ø": "o", "æ": "ae", "ß": "ss", "đ": "d", "ı": "i", "þ": "th",
                       "ð": "d", "œ": "oe"})


def plain(text: str) -> str:
    """Accent-free lower-case words — the same idea as the app's normaliseName."""
    t = text.lower().replace("'", "").replace("’", "").replace(".", "").replace("-", " ").translate(_FOLD)
    t = "".join(c for c in unicodedata.normalize("NFKD", t) if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^a-z0-9 ]", " ", t).split())


def language(name: str, nat: str | None) -> str | None:
    if nat and nat in LANG_OF:
        return LANG_OF[nat]
    low = name.lower()
    for lang, tell in _TELLS:
        if tell.search(low):
            return lang
    return None


def respell(name: str, lang: str) -> str:
    words = []
    for w in name.lower().replace("-", " ").split():
        w = w.replace("'", "").replace("’", "").replace(".", "")
        for pat, rep in _COMPILED[lang]:
            w = pat.sub(rep, w)
        words.append(w)
    return plain(" ".join(words))


def spoken_variants(name: str, nat: str | None, overrides: list[str] = ()) -> list[str]:
    """Extra ways the name may be heard, not counting its plain spelling."""
    base = plain(name)
    out = [plain(o) for o in overrides]
    lang = language(name, nat)
    if lang:
        out.append(respell(name, lang))
    return [v for v in dict.fromkeys(out) if v and v != base]


def selftest() -> None:
    cases = [
        ("Wojciech Szczęsny", "POL", "voychyeh shchesny"),
        ("Martin Ødegaard", "NOR", "martin urdegord"),
        ("Pierre-Emile Højbjerg", "DEN", None),
        ("Dušan Tadić", "SRB", "dushan tadich"),
        ("João Félix", "POR", "zhoow felish"),
        ("Olivier Giroud", "FRA", "oliviay zhiroo"),
        ("Dominik Szoboszlai", "HUN", "dominik soboslai"),
        ("Giorgio Chiellini", "ITA", "jorjo kiellini"),
        ("İlkay Gündoğan", "GER", None),
    ]
    for name, nat, want in cases:
        got = respell(name, language(name, nat))
        assert want is None or got == want, f"{name}: {got!r} != {want!r}"
    assert spoken_variants("Harry Kane", "ENG") == []
    assert "urdegord" in spoken_variants("Martin Ødegaard", None)[0]  # language from the ø alone


if __name__ == "__main__":
    selftest()
    for n, nat in [("Wojciech Szczęsny", "POL"), ("Martin Ødegaard", "NOR"), ("Pierre-Emile Højbjerg", "DEN"),
                   ("Kylian Mbappé", "FRA"), ("Xabi Alonso", "ESP"), ("Bastian Schweinsteiger", "GER"),
                   ("Ruud van Nistelrooy", "NED"), ("Luka Modrić", "CRO"), ("Tomáš Rosický", "CZE")]:
        print(n, "→", spoken_variants(n, nat))
    print("ok")
