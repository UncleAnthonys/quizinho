"""Turn the raw Wikidata dump into Quizinho's seed files.

    python3 data_pipeline/normalise.py            # writes seed/players.json + seed/clubs.json
    python3 data_pipeline/normalise.py --report   # stats only, writes nothing

Reads data_pipeline/raw/*.json.gz (from wikidata_fetch.py). The output uses
the same format as the hand-written demo seed, so build_db.py works unchanged.

Rules for "played for a club" (see README):
  * senior first teams only — national teams, youth, reserve and B sides,
    women's sides and futsal are dropped
  * spells recorded with 0 matches played are dropped (signed, never played)
  * spells with no start date are dropped (can't place them in a career)
  * loans are kept and flagged
"""

from __future__ import annotations

import argparse
import gzip
import json
import pathlib
import re
import sys
import unicodedata
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parent
RAW = ROOT / "raw"
SEED = ROOT / "seed"

# Team types (P31) that are never a senior men's club side. Checked against the
# real dump — several plausible-looking codes turned out to be attached to
# Juventus, Barcelona etc., so only verified codes are listed here.
EXCLUDE_TYPES = {
    "Q6979593", "Q135408445", "Q23905105", "Q23759293", "Q45053817",  # national / olympic / national B
    "Q23901123", "Q23904672", "Q23904673", "Q21945604",  # youth national teams
    "Q2412834",  # reserve team (Barça Atlètic, Castilla, Jong Ajax, Bayern II)
    "Q18558301", "Q2367225",  # university / college teams
    "Q13393265", "Q4498974", "Q17156793", "Q17376093",  # basketball, ice hockey, NFL, cricket
}
NON_SENIOR_LABEL = re.compile(
    r"(\bU-?\d{2}\b|\bunder[- ]?\d{2}\b|\byouth\b|\bacademy\b|\breserves?\b|\bjuvenil\b|\bprimavera\b"
    r"|\bjong\b|\bcastilla\b|\batl[eè]tic\b"
    r"|\bfutsal\b|\bnational\b|\bolympic\b|\bstatistics\b| B$| II$| III$| C$|\bB team\b| Sub-\d\d\b)",
    re.IGNORECASE,
)
# Women's teams are kept (the women's game is its own pool, never mixed into
# men's questions). Known by type, or by the label when the type is missing.
WOMEN_TYPES = {"Q28140340", "Q51481377"}  # women's association football club / team
WOMEN_LABEL = re.compile(
    r"(\bwomen\b|\bladies\b|\bfemen[ií]\w*|\bf[ée]minin\w*|\bfrauen\b|\bdamen\b|\bvrouwen\b"
    r"|\bkvinner\b|\bdam\b|\bW\.?F\.?C\.?$)",
    re.IGNORECASE,
)


def womens_club(c: dict) -> bool:
    return bool(set(c.get("types", [])) & WOMEN_TYPES) or bool(WOMEN_LABEL.search(c.get("name") or ""))


# A team must carry at least one of these types — this is what keeps out the
# cities and countries that bad P54 statements point at ("Brazil", "Messina").
CLUB_TYPES = {
    "Q476028", "Q847017", "Q94579592", "Q15944511", "Q28140340", "Q51481377", "Q13580678",
    "Q103229495", "Q14752149", "Q12973014", "Q10517054", "Q20639856", "Q163740", "Q4830453",
}
# FIFA codes where Wikidata only gives ISO codes (or nothing, for the home nations).
FIFA = {
    "Q21": "ENG", "Q22": "SCO", "Q25": "WAL", "Q26": "NIR", "Q55": "NED",
    "PRT": "POR", "DEU": "GER", "NLD": "NED", "CHE": "SUI", "HRV": "CRO", "DNK": "DEN", "GRC": "GRE",
    "URY": "URU", "CHL": "CHI", "ZAF": "RSA", "PRY": "PAR", "BGR": "BUL", "SVN": "SVN", "IRN": "IRN",
    "NGA": "NGA", "CIV": "CIV", "DZA": "ALG", "MAR": "MAR", "TUN": "TUN", "SAU": "KSA", "ARE": "UAE",
    "PHL": "PHI", "IDN": "IDN", "MYS": "MAS", "LVA": "LVA", "IRL": "IRL", "TGO": "TOG", "GMB": "GAM",
    "ZWE": "ZIM", "ZMB": "ZAM", "AGO": "ANG", "MDG": "MAD", "HND": "HON", "SLV": "SLV", "GTM": "GUA",
    "CRI": "CRC", "HTI": "HAI", "TTO": "TRI", "VCT": "VIN", "KNA": "SKN", "LKA": "SRI", "NPL": "NEP",
}
LOAN = {"Q2914547"}  # loan (19,700 uses in the dump; other acquisition codes are transfers)
# Formal bits to strip from club names for display ("AFC Ajax" -> "Ajax").
CLUB_PREFIX = re.compile(r"^(F\.?C\.?|A\.?F\.?C\.?|C\.?F\.?|S\.?L\.?|SV|S\.?S\.?C\.?|R\.?C\.?D\.?|K\.?R\.?C\.?|E\.?C\.?|S\.?C\.?) ")
CLUB_SUFFIX = re.compile(r" (F\.?C\.?|A\.?F\.?C\.?|C\.?F\.?|S\.?C\.?|E\.?C\.?|FBPA|Club de F[úu]tbol|Football Club|K\.?V\.?|S\.?A\.?D\.?)$")
POSITION_CODES = [
    ("goalkeeper", "GK"), ("centre-back", "CB"), ("center back", "CB"), ("full-back", "FB"), ("fullback", "FB"),
    ("wing-back", "WB"), ("defender", "DF"), ("defensive midfielder", "DM"), ("attacking midfielder", "AM"),
    ("winger", "W"), ("midfielder", "MF"), ("centre-forward", "ST"), ("striker", "ST"), ("forward", "FW"),
]


def load(name: str):
    with gzip.open(RAW / f"{name}.json.gz", "rt", encoding="utf-8") as f:
        return json.load(f)


def slug(text: str) -> str:
    t = unicodedata.normalize("NFKD", text.replace("'", "").replace("’", ""))
    t = "".join(c for c in t if not unicodedata.combining(c)).lower()
    t = t.replace("ø", "o").replace("ß", "ss").replace("ł", "l").replace("đ", "d").replace("ı", "i").replace("æ", "ae")
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")


def year(date: str | None) -> int | None:
    if not date:
        return None
    m = re.match(r"^-?(\d{4})", date)
    return int(m.group(1)) if m else None


def player_fame(sitelinks: int, women: bool = False) -> int:
    if women:  # women's players have far fewer Wikipedia pages at the same standing
        return 5 if sitelinks >= 45 else 4 if sitelinks >= 32 else 3 if sitelinks >= 20 else 2 if sitelinks >= 11 else 1
    # calibrated on the dump: ~90 at 5, ~450 at 4+, ~2,500 at 3+
    return 5 if sitelinks >= 85 else 4 if sitelinks >= 60 else 3 if sitelinks >= 42 else 2 if sitelinks >= 28 else 1


def club_fame(sitelinks: int) -> int:
    # ~50 clubs at 5, ~200 at 4+, ~650 at 3+
    return 5 if sitelinks >= 95 else 4 if sitelinks >= 70 else 3 if sitelinks >= 48 else 2 if sitelinks >= 30 else 1


def position_code(labels: list[str]) -> str | None:
    for label in labels:
        low = label.lower()
        for key, code in POSITION_CODES:
            if key in low:
                return code
    return None


def clean_name(name: str | None) -> str | None:
    """Drop disambiguation like 'Pedro (footballer, born 1987)'."""
    if not name or re.fullmatch(r"Q\d+", name):
        return None
    return re.sub(r"\s*\(.*?\)\s*$", "", name).strip() or None


def good_alias(alias: str, name: str) -> bool:
    """Keep short nicknames/surname forms; drop full legal names and junk."""
    if alias == name or len(alias) < 2 or len(alias) > 28 or re.search(r"[\d()\[\],/]", alias):
        return False
    return len(alias.split()) <= 3


def senior_club(c: dict) -> bool:
    types = set(c.get("types", []))
    if types & EXCLUDE_TYPES or not types & CLUB_TYPES:
        return False
    return not NON_SENIOR_LABEL.search(c.get("name") or "")


def display_club_name(name: str, aliases: list[str]) -> str:
    """Everyday name: the shortest alias found inside the formal label
    ("Clube de Regatas do Flamengo" -> "Flamengo"), then strip FC/AFC etc."""
    out = name
    for _ in range(2):
        out = CLUB_SUFFIX.sub("", CLUB_PREFIX.sub("", out)).strip()
    if len(out) > 22:
        # still long ("Clube de Regatas do Flamengo"): use the longest alias that
        # appears inside it, so "Bayern Munich" never shrinks to "Munich"
        words = f" {out.lower()} "
        inside = [a for a in aliases if len(a) >= 5 and f" {a.lower()} " in words and len(a) < len(out)]
        if inside:
            out = max(inside, key=len)
    return out or name


def country_code(qid: str, countries: dict) -> str | None:
    if qid in FIFA:
        return FIFA[qid]
    c = countries.get(qid, {})
    code = c.get("fifa") or c.get("iso3")
    return FIFA.get(code, code) if code else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--min-club-sitelinks", type=int, default=10, help="drop very obscure clubs")
    args = ap.parse_args()

    players_raw = load("players")
    spells_raw = load("spells")
    clubs_raw = {c["id"]: c for c in load("clubs")}
    countries = {c["id"]: c for c in load("countries")} if (RAW / "countries.json.gz").exists() else {}
    stats: Counter = Counter()

    # ---- clubs ------------------------------------------------------------
    keep_clubs: dict[str, dict] = {}
    for cid, c in clubs_raw.items():
        name = clean_name(c.get("name"))
        if not name:
            stats["club_no_name"] += 1
            continue
        if not senior_club({**c, "name": name}):
            stats["club_not_senior"] += 1
            continue
        if c.get("sitelinks", 0) < args.min_club_sitelinks:
            stats["club_too_obscure"] += 1
            continue
        women = womens_club({**c, "name": name})
        base = WOMEN_LABEL.sub("", name).strip(" -–,") if women else name
        # US/Canadian club names are mostly city + FC ("Los Angeles FC") — keep them whole
        short = base if c.get("country") in ("Q30", "Q16") else display_club_name(base, c.get("aliases", []))
        if women:
            short = f"{short} Women"  # "Arsenal W.F.C." -> "Arsenal Women", never just "Arsenal"
        keep_clubs[cid] = {**c, "name": short, "formal": name, "women": women}

    # ---- spells -----------------------------------------------------------
    by_player: dict[str, list[dict]] = defaultdict(list)
    for s in spells_raw:
        if s["team"] not in keep_clubs:
            stats["spell_dropped_club"] += 1
            continue
        if s.get("apps") == 0:
            stats["spell_zero_apps"] += 1
            continue
        start = year(s.get("start"))
        if start is None:
            stats["spell_no_start"] += 1
            continue
        end = year(s.get("end"))
        if end is not None and end < start:
            end = start
        by_player[s["player"]].append({
            "club": s["team"], "start": start, "end": end,
            "loan": bool(set(s.get("acq", [])) & LOAN), "raw_start": s.get("start") or "",
            "apps": s.get("apps"), "goals": s.get("goals"),
        })

    # ---- players ----------------------------------------------------------
    out_players = []
    used_slugs: dict[str, str] = {}
    used_clubs: set[str] = set()
    # most famous first, so they get the plain slug ("pedro" = the famous Pedro)
    for p in sorted(players_raw, key=lambda p: -p.get("sitelinks", 0)):
        name = clean_name(p.get("name"))
        spells = by_player.get(p["id"], [])
        # Women's game if recorded female, or if the career was mostly at
        # women's clubs (covers players whose recorded gender isn't female but
        # who played in the women's game). A woman's spell logged against a
        # men's club item is a data slip, and dropped below.
        in_womens = sum(1 for s in spells if keep_clubs[s["club"]]["women"])
        women = p.get("sex") == "f" or (bool(spells) and in_womens * 2 > len(spells))
        # never mix: a men's player's stray women's-team spell (data error) and vice versa
        spells = [s for s in spells if keep_clubs[s["club"]]["women"] == women]
        if not spells:
            stats["spell_wrong_gender"] += len(by_player.get(p["id"], []))
        spells = sorted(spells, key=lambda s: (s["raw_start"], s["loan"]))
        if not name or not spells:
            stats["player_no_career" if name else "player_no_name"] += 1
            continue
        # merge back-to-back spells at the same club (a loan logged inside a
        # permanent spell, or one spell split in two) so a club never shows twice in a row
        career: list[dict] = []
        for s in spells:
            prev = career[-1] if career else None
            if prev and prev["club"] == s["club"]:
                prev["end"] = None if None in (prev["end"], s["end"]) else max(prev["end"], s["end"])
                prev["loan"] = prev["loan"] and s["loan"]
                continue
            career.append(dict(s))
        pid = slug(name)
        if pid in used_slugs:
            pid = f"{pid}-{year(p.get('dob')) or p['id'].lower()}"
            if pid in used_slugs:
                pid = f"{slug(name)}-{p['id'].lower()}"
        used_slugs[pid] = p["id"]
        nat = next((code for n in p.get("nationalities", []) if (code := country_code(n, countries))), None)
        aliases = [a for a in p.get("aliases", []) if good_alias(a, name)][:6]
        for fam in p.get("family_names", [])[:1]:
            if fam and fam not in aliases and fam.lower() not in name.lower().split()[-1:]:
                aliases.append(fam)
        used_clubs.update(s["club"] for s in career)
        # League apps + goals per club (Football 501), summed over every spell
        # there — only when every spell has numbers, so a total never undercounts.
        club_stats: dict[str, list[int]] = {}
        for cid in {s["club"] for s in spells}:
            at = [s for s in spells if s["club"] == cid]
            if all(s["apps"] is not None and s["goals"] is not None for s in at):
                club_stats[cid] = [sum(s["apps"] for s in at), sum(s["goals"] for s in at)]
        out_players.append({
            "id": pid, "wikidata": p["id"], "name": name, "nat": nat,
            "pos": position_code(p.get("positions", [])), "fame": player_fame(p.get("sitelinks", 0), women),
            "reach": p.get("sitelinks", 0), **({"g": "w"} if women else {}),
            "aliases": aliases,
            "career": [[s["club"], s["start"], s["end"]] + (["loan"] if s["loan"] else []) for s in career],
            **({"stats": club_stats} if club_stats else {}),
        })

    # Club fame = how many well-known players played there (Wikipedia coverage
    # alone ranks Kuban Krasnodar above Arsenal). Ranked into 5 bands.
    # Women's clubs are ranked among women's clubs (a far smaller pool).
    weight = {5: 8, 4: 4, 3: 2, 2: 1}
    score: Counter = Counter()
    for p in out_players:
        for cid in {c[0] for c in p["career"]}:
            score[cid] += weight.get(p["fame"], 0)
    band: dict[str, int] = {}
    cuts = {False: (40, 150, 450, 1200), True: (12, 40, 100, 250)}
    for women in (False, True):
        ranked = [cid for cid, _ in score.most_common() if keep_clubs[cid]["women"] == women]
        c5, c4, c3, c2 = cuts[women]
        band.update({cid: 5 if i < c5 else 4 if i < c4 else 3 if i < c3 else 2 if i < c2 else 1
                     for i, cid in enumerate(ranked)})

    out_clubs = []
    for cid in sorted(used_clubs):
        c = keep_clubs[cid]
        country_qid = c.get("country") or ""
        aliases = [a for a in [c["formal"], *c.get("aliases", [])] if good_alias(a, c["name"])
                   # a women's team's nickname must say so ("Arsenal Ladies"), never the men's name
                   and (not c["women"] or WOMEN_LABEL.search(a))][:6]
        out_clubs.append([cid, c["name"], country_code(country_qid, countries), band.get(cid, 1), aliases,
                          c.get("sitelinks", 0), "w" if c["women"] else "m"])

    fame = Counter(p["fame"] for p in out_players)
    print(f"players kept: {len(out_players)} of {len(players_raw)}  fame: {dict(sorted(fame.items()))}"
          f"  women: {sum(1 for p in out_players if p.get('g') == 'w')}")
    print(f"clubs kept: {len(out_clubs)} of {len(clubs_raw)}")
    print("dropped:", dict(stats))
    if args.report:
        return 0

    SEED.mkdir(exist_ok=True)
    note = "GENERATED by normalise.py from Wikidata (CC0). Do not edit by hand — edit overrides.json instead."
    (SEED / "clubs.json").write_text(json.dumps({"_note": note, "clubs": out_clubs}, ensure_ascii=False, indent=0), encoding="utf-8")
    (SEED / "players.json").write_text(json.dumps({"_note": note, "players": out_players}, ensure_ascii=False, indent=0), encoding="utf-8")
    names = {"ENG": "England", "SCO": "Scotland", "WAL": "Wales", "NIR": "Northern Ireland", "NED": "the Netherlands"}
    for qid, c in countries.items():
        code = country_code(qid, countries)
        if code and c.get("name") and code not in names:
            names[code] = c["name"]
    (SEED / "countries.json").write_text(json.dumps({"_note": note, "countries": names}, ensure_ascii=False, indent=0), encoding="utf-8")
    print("wrote seed/clubs.json, seed/players.json and seed/countries.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
