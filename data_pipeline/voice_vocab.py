"""Builds the app's own speech vocabulary: every player's name, weighted by
fame, with pronunciations for every name word — how an English speaker reads
it, and how it's said at home approximated with English sounds — in X-SAMPA,
the phonetic alphabet Apple's custom language models take (iOS 17+).

    pip install --break-system-packages espeakng-loader phonemizer
    python3 data_pipeline/voice_vocab.py     # after build_db.py

Reads assets/db/football.json, writes assets/voice/vocab.json. Pronunciations
come from espeak-ng (open-source, rules for ~100 languages); fixes from real
voice tests go in seed/pronunciation_overrides.json.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import unicodedata
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "db" / "football.json"
OUT = ROOT / "assets" / "voice" / "vocab.json"
OVERRIDES = ROOT / "data_pipeline" / "seed" / "pronunciation_overrides.json"

# espeak-ng voice for a nationality's native pronunciation. Nationalities not
# listed (English-speaking, or names written in a script espeak can't read in
# Latin letters) only get the English reading.
VOICE = {
    "POL": "pl", "NOR": "nb", "DEN": "da", "SWE": "sv", "ISL": "is", "FIN": "fi", "FRO": "da",
    "SRB": "sr", "MNE": "sr", "BIH": "bs", "CRO": "hr", "SVN": "sl", "MKD": "mk",
    "CZE": "cs", "SVK": "sk", "CSK": "cs", "POR": "pt", "BRA": "pt-br", "ANG": "pt", "CPV": "pt",
    "MOZ": "pt", "GNB": "pt", "ESP": "es", "NED": "nl", "SUR": "nl", "BEL": "nl",
    "GER": "de", "AUT": "de", "SUI": "de", "DDR": "de", "FRA": "fr-fr", "CIV": "fr-fr", "SEN": "fr-fr",
    "CMR": "fr-fr", "ALG": "fr-fr", "MAR": "fr-fr", "TUN": "fr-fr", "MLI": "fr-fr", "GIN": "fr-fr",
    "COD": "fr-fr", "COG": "fr-fr", "GAB": "fr-fr", "BEN": "fr-fr", "BFA": "fr-fr", "TOG": "fr-fr",
    "HAI": "fr-fr", "MTQ": "fr-fr", "GLP": "fr-fr", "GUF": "fr-fr", "NCL": "fr-fr", "MAD": "fr-fr",
    "LUX": "fr-fr", "ITA": "it", "SMR": "it", "TUR": "tr", "AZE": "az", "HUN": "hu", "ROU": "ro",
    "MDA": "ro", "ALB": "sq", "XKS": "sq", "EST": "et", "LVA": "lv", "LTU": "lt",
}
for _n in ("ARG", "MEX", "URU", "COL", "CHI", "PER", "PAR", "ECU", "VEN", "BOL", "CRC", "HON", "SLV",
           "GUA", "PAN", "CUB", "DOM", "GNQ"):
    VOICE[_n] = "es-419"

# IPA (as espeak writes it) -> X-SAMPA, folded into the English sound set so a
# British English model can use it: "Szczęsny" is said the way an English
# speaker approximates the Polish. Longest match first.
_IPA = {
    # affricates and two-letter consonants
    "t͡ʃ": "tS", "tʃ": "tS", "d͡ʒ": "dZ", "dʒ": "dZ", "t͡ɕ": "tS", "tɕ": "tS", "d͡ʑ": "dZ", "dʑ": "dZ",
    "t͡s": "t s", "ts": "t s", "d͡z": "d z", "dz": "d z", "tʂ": "tS", "dʐ": "dZ",
    # diphthongs
    "eɪ": "eI", "aɪ": "aI", "ɔɪ": "OI", "əʊ": "@U", "oʊ": "@U", "aʊ": "aU", "ɪə": "I@", "eə": "e@",
    "ʊə": "U@", "ɛɪ": "eI", "ɛi": "eI", "ei": "eI", "œy": "aU", "ʌu": "aU", "ɑi": "aI", "ai": "aI",
    "au": "aU", "ɑu": "aU", "oi": "OI", "ɔj": "OI", "aj": "aI", "ej": "eI", "ʌj": "aI",
    # long vowels
    "iː": "i:", "uː": "u:", "ɑː": "A:", "ɔː": "O:", "ɜː": "3:", "aː": "A:", "eː": "eI", "oː": "@U",
    "ɛː": "e@", "yː": "u:", "øː": "3:", "æː": "{",
    # vowels
    "i": "i:", "ɪ": "I", "e": "e", "ɛ": "e", "æ": "{", "a": "{", "ɑ": "A:", "ɒ": "Q", "ɔ": "Q",
    "o": "@U", "ʊ": "U", "u": "u:", "ʌ": "V", "ə": "@", "ɜ": "3:", "ɐ": "V", "ɨ": "I", "y": "u:",
    "ʏ": "U", "ø": "3:", "œ": "3:", "ɵ": "3:", "ɘ": "@", "ɯ": "U", "ɤ": "@", "ᵻ": "I", "ɚ": "@", "ʉ": "u:", "ε": "e",
    # consonants
    "p": "p", "b": "b", "t": "t", "d": "d", "k": "k", "g": "g", "ɡ": "g", "f": "f", "v": "v",
    "θ": "T", "ð": "D", "s": "s", "z": "z", "ʃ": "S", "ʒ": "Z", "h": "h", "m": "m", "n": "n",
    "ŋ": "N", "l": "l", "ɹ": "r", "r": "r", "ɾ": "r", "ʁ": "r", "ʀ": "r", "ɻ": "r", "j": "j", "w": "w",
    "x": "h", "χ": "h", "ɣ": "g", "ç": "S", "ɕ": "S", "ʑ": "Z", "ʂ": "S", "ʐ": "Z", "ɲ": "n j",
    "ʎ": "l j", "ɟ": "g", "c": "k", "ɫ": "l", "ɱ": "m", "ʋ": "v", "β": "b", "ɦ": "h", "ħ": "h",
    "q": "k", "ʝ": "j", "ɬ": "l", "ɭ": "l", "ɳ": "n", "ʈ": "t", "ɖ": "d", "ɰ": "w", "ɥ": "w",
}
_KEYS = sorted(_IPA, key=len, reverse=True)

# Apple's en-GB set (SFCustomLanguageModelData.supportedPhonemes, read on a
# Mac by scripts/voice_model_probe.swift): no length marks, E for e, r\ for r.
APPLE_EN_GB = {"i:": "i", "u:": "u", "A:": "A", "O:": "O", "3:": "3", "e": "E", "e@": "E@", "r": "r\\"}
APPLE_EN_GB_SET = set(
    ". Z j w v @ V 3 S n k l I h g f E i d b O Q A I@ m= z N aU OI @U dZ @r eI U@ E@ U tS T m { D l= n= aI "
    "s u p t r\\".split())
_DROP = set("ˈˌ.ʔ‿-ː̯͡ˑ̩ʰʲʷ̪̥̬ˠ ?#^") | {"̃", "̧", "̝", "̊"}


def ipa_to_xsampa(ipa: str, voice: str = "") -> tuple[str, set[str]]:
    """X-SAMPA phonemes separated by spaces, plus any IPA symbols it didn't know."""
    s = unicodedata.normalize("NFD", re.sub(r"\([a-z-]+\)", "", ipa))
    out, unknown, i = [], set(), 0
    while i < len(s):
        for k in _KEYS:
            if s.startswith(k, i):
                out.append(_IPA[k])
                i += len(k)
                # nasal vowel ("ę", "ão"): an English speaker adds an n
                if i < len(s) and s[i] == "̃":
                    out.append("n")
                    i += 1
                break
        else:
            if s[i] not in _DROP:
                unknown.add(s[i])
            i += 1
    out = [APPLE_EN_GB.get(x, x) for x in " ".join(out).split()]
    if voice == "de":  # German ch: English speakers say k ("Bach")
        out = ["k" if x == "h" and i > 0 else x for i, x in enumerate(out)]
    # one sound, not two: "nn" from a nasal vowel before n, "ss" from espeak's doubled letters
    out = [x for i, x in enumerate(out) if i == 0 or x != out[i - 1]]
    unknown |= {x for x in out if x not in APPLE_EN_GB_SET}
    return " ".join(out), unknown


def _espeak():
    import espeakng_loader
    from phonemizer.backend.espeak.wrapper import EspeakWrapper

    EspeakWrapper.set_library(espeakng_loader.get_library_path())
    EspeakWrapper.set_data_path(espeakng_loader.get_data_path())
    from phonemizer import phonemize

    return phonemize


def words_of(name: str) -> list[str]:
    return [w for w in re.split(r"[\s\-]+", name.replace(".", "")) if len(w) >= 2]


COUNT_BY_FAME = {5: 100, 4: 50, 3: 20, 2: 8, 1: 3}


def main() -> int:
    phonemize = _espeak()
    doc = json.loads(SRC.read_text(encoding="utf-8"))
    players = [p for p in doc["players"] if p.get("g") != "w"] + [p for p in doc["players"] if p.get("g") == "w"]

    phrases: dict[str, int] = defaultdict(int)
    by_voice: dict[str, set[str]] = defaultdict(set)
    for p in players:
        name, fame = p["name"], p.get("fame", 1)
        count = COUNT_BY_FAME.get(fame, 3)
        phrases[name] = max(phrases[name], count)
        ws = words_of(name)
        if len(ws) >= 2:  # the surname alone is what people often shout
            surname = " ".join(ws[1:])
            phrases[surname] = max(phrases[surname], count // 2 or 1)
        for a in p.get("aliases", []):
            if len(a) >= 3 and fame >= 3:
                phrases[a] = max(phrases[a], count // 2 or 1)
        for w in ws:
            by_voice["en-gb"].add(w)
            if (v := VOICE.get(p.get("nat") or "")):
                by_voice[v].add(w)

    prons: dict[str, set[str]] = defaultdict(set)
    unknown: dict[str, int] = defaultdict(int)
    for voice, words in sorted(by_voice.items()):
        words = sorted(words)
        print(f"{voice}: {len(words)} words", flush=True)
        ipas = phonemize(words, language=voice, backend="espeak", strip=True, njobs=1,
                         language_switch="remove-flags")
        for w, ipa in zip(words, ipas):
            xs, unk = ipa_to_xsampa(ipa, voice)
            for u in unk:
                unknown[u] += 1
            if xs:
                prons[w].add(xs)

    if OVERRIDES.exists():
        for w, extra in json.loads(OVERRIDES.read_text(encoding="utf-8"))["words"].items():
            for x in extra:
                bad = [t for t in x.split() if t not in APPLE_EN_GB_SET]
                if bad:
                    raise SystemExit(f"pronunciation_overrides: {w} {x!r} has symbols Apple won't take: {bad}")
            if w not in by_voice["en-gb"]:
                print(f"pronunciation_overrides: {w} isn't in any player's name (ignored)")
                continue
            prons[w].update(extra)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    body = {
        "phrases": sorted(([k, v] for k, v in phrases.items()), key=lambda kv: (-kv[1], kv[0])),
        "pronunciations": {w: sorted(v) for w, v in sorted(prons.items())},
    }
    version = hashlib.sha256(json.dumps(body, ensure_ascii=False).encode()).hexdigest()[:12]
    out = {
        "locale": "en-GB",
        "version": version,
        "about": "Generated by data_pipeline/voice_vocab.py — player names (with counts) and X-SAMPA pronunciations.",
        **body,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"phrases={len(out['phrases'])} words={len(prons)} "
          f"pronunciations={sum(len(v) for v in prons.values())} size={OUT.stat().st_size // 1024}KB")
    if unknown:
        print("unmapped IPA:", dict(sorted(unknown.items(), key=lambda kv: -kv[1])[:20]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
