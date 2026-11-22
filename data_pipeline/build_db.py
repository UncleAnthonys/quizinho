"""Build Quizinho's bundled football database.

    python3 data_pipeline/build_db.py            # build from seed/
    python3 data_pipeline/build_db.py --check    # validate only

Reads data_pipeline/seed/*.json, validates it, generates Club Connections
and Career Path challenges, and writes:

    assets/db/football.db               SQLite, opened read-only by the app
    assets/db/football_db_version.txt   integer; app re-copies the DB when it changes

Rules for "played for a club" (applied here, so every game mode agrees):
  * Only senior first-team spells are stored. Youth, academy and B teams
    are never entered, so they can never count.
  * Loan spells count (they are real first-team football) and are flagged.
  * Signed-but-never-played transfers must not be entered.
  * A spell is game-eligible only if its source is verified, OR the build is
    run with --allow-unverified (the default while we are on demo data).
"""

from __future__ import annotations

import argparse
import datetime as dt
import itertools
import json
import math
import pathlib
import re
import sqlite3
import sys
import unicodedata
import unicodedata

import spoken  # noqa: E402 — sibling module (run as data_pipeline/build_db.py)

ROOT = pathlib.Path(__file__).resolve().parent
SEED = ROOT / "seed"
ASSETS = ROOT.parent / "assets" / "db"

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE clubs (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, country TEXT, fame INTEGER NOT NULL,
  wikidata_id TEXT, women INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE club_aliases (club_id TEXT NOT NULL REFERENCES clubs(id), alias TEXT NOT NULL);
CREATE TABLE players (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, nationality TEXT, position TEXT,
  fame INTEGER NOT NULL, verified INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL,
  wikidata_id TEXT, women INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE player_aliases (player_id TEXT NOT NULL REFERENCES players(id), alias TEXT NOT NULL);
-- How a name may sound when spoken, spelt the English way (voice answers only).
CREATE TABLE player_spoken (player_id TEXT NOT NULL REFERENCES players(id), spoken TEXT NOT NULL);
CREATE TABLE career_spells (
  player_id TEXT NOT NULL REFERENCES players(id), seq INTEGER NOT NULL,
  club_id TEXT NOT NULL REFERENCES clubs(id), start_year INTEGER, end_year INTEGER,
  is_loan INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (player_id, seq)
);
CREATE TABLE matches (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, competition TEXT, match_date TEXT,
  home TEXT NOT NULL, away TEXT NOT NULL, score TEXT, target_team TEXT NOT NULL,
  fame INTEGER NOT NULL, difficulty INTEGER NOT NULL,
  verified INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL,
  eras INTEGER NOT NULL,
  weight REAL NOT NULL DEFAULT 1  -- how often it comes up: classics 1, newer 0.5, obscure 0.2
);
CREATE TABLE lineup_slots (
  match_id TEXT NOT NULL REFERENCES matches(id), slot INTEGER NOT NULL,
  player_id TEXT NOT NULL REFERENCES players(id), position TEXT NOT NULL,
  PRIMARY KEY (match_id, slot)
);
CREATE TABLE club_connections (
  id TEXT PRIMARY KEY, club_a TEXT NOT NULL, club_b TEXT NOT NULL,
  answer_count INTEGER NOT NULL, best_fame INTEGER NOT NULL, difficulty INTEGER NOT NULL,
  eras INTEGER NOT NULL
);
CREATE TABLE connection_answers (
  connection_id TEXT NOT NULL REFERENCES club_connections(id),
  player_id TEXT NOT NULL REFERENCES players(id)
);
CREATE TABLE career_challenges (
  player_id TEXT PRIMARY KEY REFERENCES players(id), clue_count INTEGER NOT NULL,
  difficulty INTEGER NOT NULL, eras INTEGER NOT NULL
);
CREATE INDEX idx_conn_diff ON club_connections(difficulty);
CREATE INDEX idx_ans_conn ON connection_answers(connection_id);
CREATE INDEX idx_career_diff ON career_challenges(difficulty);
-- Noughts & Crosses rows and columns besides clubs (a nation, a star's
-- teammates, a manager's players), and per club the players who fit both.
-- players: comma-separated ids.
CREATE TABLE grid_categories (id TEXT PRIMARY KEY, label TEXT NOT NULL, kind TEXT NOT NULL);
CREATE TABLE category_rosters (
  category_id TEXT NOT NULL REFERENCES grid_categories(id), club_id TEXT NOT NULL REFERENCES clubs(id),
  eras INTEGER NOT NULL, players TEXT NOT NULL, PRIMARY KEY (category_id, club_id)
);
CREATE TABLE bidding_categories (
  id TEXT PRIMARY KEY, prompt TEXT NOT NULL, kind TEXT NOT NULL,
  answer_count INTEGER NOT NULL, difficulty INTEGER NOT NULL, eras INTEGER NOT NULL,
  women INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE bidding_answers (
  category_id TEXT NOT NULL REFERENCES bidding_categories(id),
  player_id TEXT NOT NULL,
  score INTEGER
);
CREATE INDEX idx_match_diff ON matches(difficulty);
CREATE INDEX idx_bid_ans ON bidding_answers(category_id);
CREATE TABLE checkout_categories (
  id TEXT PRIMARY KEY, prompt TEXT NOT NULL, club_id TEXT NOT NULL,
  difficulty INTEGER NOT NULL, eras INTEGER NOT NULL, women INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE checkout_answers (
  category_id TEXT NOT NULL REFERENCES checkout_categories(id),
  player_id TEXT NOT NULL,
  apps INTEGER, goals INTEGER  -- NULL = played there, but no numbers on record
);
CREATE INDEX idx_co_ans ON checkout_answers(category_id);
"""

POSITIONS = {"GK", "RB", "CB", "LB", "RWB", "LWB", "DM", "CM", "AM", "RM", "LM", "RW", "LW", "ST"}


def load(name: str) -> dict:
    return json.loads((SEED / name).read_text(encoding="utf-8"))


NAME_PARTICLES = {"van", "von", "de", "der", "den", "da", "dos", "das", "do", "di", "del", "della", "la", "le",
                  "ter", "ten", "af", "al", "el", "bin", "ben", "y", "e", "zu", "of", "du", "des", "dal", "'t",
                  "los", "las", "te", "i", "á"}
# The four leagues a UK group knows best. Easy connections stay inside them:
# Feyenoord + Ajax is two big clubs, but not an easy question here.
BIG4 = {"GBR", "ENG", "ESP", "ITA", "GER"}
# Rivals everyone links: Easy as long as two answers are well known. (Liverpool +
# Everton, Celtic + Rangers and Newcastle + Sunderland have hardly any
# crossovers people know — Beardsley, Kenny Miller — so the data leaves them hard.)
EASY_PAIRS = {frozenset(p) for p in [
    ("Q9617", "Q18741"),    # Arsenal, Tottenham
    ("Q18656", "Q50602"),   # Man United, Man City
    ("Q18656", "Q1130849"), # Man United, Liverpool
    ("Q7156", "Q8682"),     # Barcelona, Real Madrid
    ("Q8682", "Q8701"),     # Real Madrid, Atlético
    ("Q1543", "Q631"),      # AC Milan, Inter
    ("Q1422", "Q631"),      # Juventus, Inter
    ("Q15789", "Q41420"),   # Bayern, Dortmund
]}


# European giants: two of these make an Easy pair without an English club.
GIANTS = {"Q7156", "Q8682", "Q8701", "Q1422", "Q1543", "Q631", "Q2739", "Q15789", "Q41420"}
# Foreign clubs a UK group knows well enough for a Medium pair: the giants and PSG.
# Not Ajax, PSV, Benfica, Fenerbahçe… (big, but few recent players people know).
WELL_KNOWN = GIANTS | {"Q483020"}


def memorable_spell(player: dict, club: str) -> bool:
    """Would people link this player with this club? A loan, a handful of
    games, or a short late cameo at a smaller club doesn't count (Lampard's
    teenage loan at Swansea, Balotelli at Monza, Özil at Başakşehir)."""
    spells = [s for s in player["spells"] if s["club"] == club]
    if spells and all(s["loan"] for s in spells):
        return False
    apps = (player.get("stats") or {}).get(club, [None])[0]
    if apps is None:  # no numbers: trust a permanent spell
        return True
    return apps >= 50 or (apps >= 20 and CLUB_FAME[club] >= 4)  # Cantona's Leeds counts


CLUB_FAME: dict[str, int] = {}


def connection_difficulty(a: str, b: str, shared: list[str], clubs, players) -> int:
    """1 easy .. 4 expert, from how many answers people would actually think of
    (famous players with real spells at both clubs), how many answers there are
    in all, and how big and familiar the two clubs are."""
    def solid(pid: str) -> bool:
        return memorable_spell(players[pid], a) and memorable_spell(players[pid], b)

    fame = {pid: players[pid]["fame"] for pid in shared}
    stars = sum(1 for pid in shared if fame[pid] >= 5 and solid(pid))   # Rooney, Ronaldo
    strong = sum(1 for pid in shared if fame[pid] >= 4 and solid(pid))  # Ashley Young
    known = sum(1 for pid in shared if fame[pid] >= 3 and solid(pid))
    total = len(shared)
    ca, cb = clubs[a], clubs[b]
    big4 = ca["country"] in BIG4 and cb["country"] in BIG4
    one_big4 = ca["country"] in BIG4 or cb["country"] in BIG4
    top5 = ca["country"] in TOP5 and cb["country"] in TOP5
    known_leagues = ca["country"] in KNOWN_LEAGUES and cb["country"] in KNOWN_LEAGUES

    if not known_leagues:
        return 4
    if frozenset((a, b)) in EASY_PAIRS and known >= 2:
        return 1
    # Easy: big clubs a UK group knows (at least one English, or two European
    # giants) and two or more answers that come straight to mind.
    familiar = ca["country"] in ("GBR", "ENG") or cb["country"] in ("GBR", "ENG") or {a, b} <= GIANTS
    if big4 and familiar and min(ca["fame"], cb["fame"]) >= 4 and max(ca["fame"], cb["fame"]) >= 5 \
            and (stars >= 2 and total >= 5 or stars >= 1 and strong >= 2 and total >= 8
                 or strong >= 2 and total >= 12):
        return 1
    # Medium is the main game, so it takes a wide batch — but only pairs a UK
    # group recognises at once: an English club, or two of Europe's biggest
    # (Juve + PSG, not Ajax + Benfica). Hertha + Köln or Sevilla + Málaga are Hard. Two clubs from
    # smaller leagues (Porto + Vitória) only with a real star (Cruyff for Ajax + Feyenoord).
    def english(c: str) -> bool:
        return clubs[c]["country"] in ("GBR", "ENG")

    # Partner for an English club: English too, or a big name (Everton + Barcelona,
    # Chelsea + Marseille) — not Rennes or Lyon (Arsenal + Rennes: four obscure answers).
    def big_name(c: str) -> bool:
        return english(c) or c in WELL_KNOWN or clubs[c]["fame"] >= 5 and clubs[c]["country"] in TOP5

    big_pair = (english(a) or english(b)) and big_name(a) and big_name(b) or {a, b} <= WELL_KNOWN
    if big_pair and total >= 5 and (strong >= 1 or known >= 3 or stars >= 1):
        return 2
    if known >= 1 or any(f >= 4 for f in fame.values()) or big4 and any(f >= 3 for f in fame.values()):
        return 3
    return 4


# Wikipedias covering a player — above this, a household name worldwide.
ICON_REACH = 100


def career_difficulty(p: dict, clubs) -> int:
    """How fast a group would get the player from the list of clubs: their fame,
    and how many real spells (not loans or cameos) at big, well-known clubs the
    path shows. Davids (Ajax, Juventus, Spurs) is gettable even though his fame
    rating is only 3; a star whose path is mostly obscure clubs is not Easy."""
    big = {s["club"] for s in p["spells"]
           if clubs[s["club"]]["fame"] >= 5 and clubs[s["club"]]["country"] in KNOWN_LEAGUES
           and memorable_spell(p, s["club"])}
    english = any(clubs[c]["country"] in ("GBR", "ENG") for c in big)
    # A real spell in England: a UK group's go-to (Stanković or Hagi never played here).
    played_here = any(clubs[s["club"]]["country"] in ("GBR", "ENG") and memorable_spell(p, s["club"])
                      for s in p["spells"])
    fame = p["fame"]
    icon = fame >= 5 and (p.get("reach") or 0) >= ICON_REACH  # Messi, Zidane, R9 — everyone knows them
    if (fame >= 5 and len(big) >= 2 or fame >= 4 and len(big) >= 3 and english) and (played_here or icon):
        return 1
    if (fame >= 4 or fame >= 3 and len(big) >= 2) and (played_here or fame >= 5):
        return 2
    if fame >= 3 or len(big) >= 1:
        return 3
    return 4


def match_difficulty(fame: int) -> int:
    return {5: 1, 4: 2, 3: 3}.get(fame, 4)


class Problems:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)


def norm(text: str) -> str:
    t = unicodedata.normalize("NFKD", text.replace("'", "").replace("’", "")).lower()
    return " ".join("".join(c if c.isalnum() else " " for c in t if not unicodedata.combining(c)).split())


def validate_and_collect(problems: Problems):
    clubs_raw = load("clubs.json")["clubs"]
    players_raw = load("players.json")["players"]
    # League apps/goals from Wikipedia infoboxes, only where Wikidata has none
    # (data_pipeline/wiki_stats_fetch.py).
    wiki_stats = load("wiki_stats.json")["players"] if (SEED / "wiki_stats.json").exists() else {}
    # The name each player is known by (English Wikipedia title): "Alex", not
    # "Alex Rodrigo Dias da Costa". Shown in the game; the full name stays an alias.
    wiki_names = load("wiki_names.json")["players"] if (SEED / "wiki_names.json").exists() else {}
    matches_doc = load("matches.json")

    clubs = {}
    for row in clubs_raw:
        # [id, name, country, fame, aliases, reach?, "w"/"m"?] — later fields optional
        cid, name, country, fame, aliases = row[:5]
        reach = row[5] if len(row) > 5 else None
        women = len(row) > 6 and row[6] == "w"
        if cid in clubs:
            problems.error(f"duplicate club id {cid}")
        if not 1 <= fame <= 5:
            problems.error(f"club {cid} fame out of range")
        clubs[cid] = {"name": name, "country": country, "fame": fame, "aliases": aliases, "reach": reach, "women": women}

    def plausible(name: str) -> bool:
        return not (re.search(r"\d|[a-zà-ÿ][A-Z](?:\s|$)", name)
                    or re.search(r"[A-Za-z]", name) and re.search(r"[Ͱ-ӿ]", name)
                    or any(w[0].islower() and w not in NAME_PARTICLES for w in name.split()))

    players = {}
    for p in players_raw:
        pid = p["id"]
        if pid in players:
            problems.error(f"duplicate player id {pid}")
        known = wiki_names.get(pid)
        if known and known != p["name"] and plausible(known):
            p = {**p, "name": known, "aliases": list(dict.fromkeys([p["name"], *p.get("aliases", [])]))}
        # Typos/vandalism in source labels: digits, or Greek/Cyrillic letters in a Latin name
        # ...or a capital stuck on the end of a word ("RodríguezF")
        if re.search(r"\d|[a-zà-ÿ][A-Z](?:\s|$)", p["name"]) or (re.search(r"[A-Za-z]", p["name"]) and re.search(r"[Ͱ-ӿ]", p["name"])):
            problems.error(f"{pid}: suspicious name {p['name']!r} — fix in normalise.py NAME_FIXES")
        # ...or a lower-case word that isn't a name particle ("Walter Ivan alexis
        # Montoya"): capitalised here rather than stopping the whole rebuild.
        if any(w[0].islower() and w not in NAME_PARTICLES for w in p["name"].split()):
            fixed = " ".join(w[0].upper() + w[1:] if w[0].islower() and w not in NAME_PARTICLES else w
                             for w in p["name"].split())
            problems.warn(f"{pid}: lower-case word in {p['name']!r}, shown as {fixed!r}")
            p = {**p, "name": fixed}
        spells = []
        for i, entry in enumerate(p.get("career", [])):
            club_id, start, end = entry[0], entry[1], entry[2]
            loan = len(entry) > 3 and entry[3] == "loan"
            if club_id not in clubs:
                problems.error(f"{pid}: unknown club '{club_id}'")
            if start and end and end < start:
                problems.error(f"{pid}: spell at {club_id} ends before it starts")
            spells.append({"seq": i, "club": club_id, "start": start, "end": end, "loan": loan})
        players[pid] = {
            "name": p["name"], "nat": p.get("nat"), "pos": p.get("pos"), "fame": p["fame"], "reach": p.get("reach"),
            "women": p.get("g") == "w",
            "stats": {**wiki_stats.get(pid, {}), **p.get("stats", {})},
            "aliases": p.get("aliases", []), "spells": spells,
        }

    # Line-ups name players by hand-written ids ("xavi"); the generated seed uses
    # Wikidata names ("xavi-hernandez"). Resolve by id, then by name/alias.
    by_name: dict[str, str] = {}
    for pid, p in sorted(players.items(), key=lambda kv: kv[1]["fame"]):  # most famous wins
        for n in [p["name"], *p["aliases"]]:
            by_name[norm(n)] = pid

    def resolve(pid: str, name: str) -> str | None:
        if pid in players:
            return pid
        return by_name.get(norm(name)) or by_name.get(norm(pid.replace("-", " ")))

    extra_aliases = matches_doc.get("extra_aliases", {})
    matches = []
    for m in matches_doc["matches"]:
        xi = m["xi"]
        ids = [s[0] for s in xi]
        if len(xi) != 11:
            problems.error(f"match {m['id']}: {len(xi)} players, need 11")
        if len(set(ids)) != len(ids):
            problems.error(f"match {m['id']}: duplicate player in XI")
        if sum(1 for s in xi if s[2] == "GK") != 1:
            problems.error(f"match {m['id']}: needs exactly one GK")
        resolved_xi = []
        for pid, name, pos in xi:
            if pos not in POSITIONS:
                problems.error(f"match {m['id']}: bad position {pos}")
            real = resolve(pid, name)
            if real == pid and norm(players[real]["name"]) != norm(name):
                # Pinned id whose data label is clunky ("Mikel John Obi"):
                # show the name people know, keep the label as an alias.
                p = players[real]
                p["aliases"] = list(dict.fromkeys([p["name"], *p["aliases"]]))
                p["name"] = name
                by_name[norm(name)] = real
            if real is None:
                # not in the career data: create a line-up-only player
                real = pid
                players[pid] = {"name": name, "nat": None, "pos": pos, "fame": 3, "aliases": [], "spells": [], "women": False}
                by_name[norm(name)] = pid
            resolved_xi.append([real, players[real]["name"], pos])
        if len({r[0] for r in resolved_xi}) != 11:
            problems.error(f"match {m['id']}: two line-up names resolved to the same player")
        matches.append({**m, "xi": resolved_xi})

    for pid, aliases in extra_aliases.items():
        real = resolve(pid, pid.replace("-", " "))
        if real is None:
            problems.warn(f"extra_aliases: unknown player {pid}")
        else:
            players[real]["aliases"] = list(dict.fromkeys(players[real]["aliases"] + aliases))

    return clubs, players, matches


# Era bit flags — must match lib/domain/era.dart.
ERAS = [(1, 0, 1991), (2, 1992, 1999), (4, 2000, 2009), (8, 2010, 2019), (16, 2020, 9999)]
CURRENT_YEAR = dt.date.today().year


def era_mask(start: int | None, end: int | None) -> int:
    """Bit flags of every era the years [start, end] touch (end None = still going)."""
    if start is None:
        return 0
    end = CURRENT_YEAR if end is None else end
    return sum(bit for bit, lo, hi in ERAS if start <= hi and end >= lo)


def spells_mask(spells) -> int:
    m = 0
    for s in spells:
        m |= era_mask(s["start"], s["end"])
    return m


def career_mask(spells) -> int:
    """Eras a career mostly belongs to: each era holding at least a third of
    its years (Hagi, 1982-2001, is 80s/90s — not 2000s for one last season)."""
    years: set[int] = set()
    for s in spells:
        if s["start"] is not None:
            years.update(range(s["start"], (CURRENT_YEAR if s["end"] is None else s["end"]) + 1))
    if not years:
        return 0
    per = {bit: sum(1 for y in years if lo <= y <= hi) for bit, lo, hi in ERAS}
    m = sum(bit for bit, n in per.items() if n * 3 >= len(years))
    return m or max(per, key=per.get)


# Club Connections / Tic-Tac-Toe only use clubs at least this well known, and
# a pair needs at least one answer at least this famous — technically valid but
# unguessable pairs ("Kauno Žalgiris + Vegalta Sendai") are no fun.
CONNECTION_MIN_CLUB_FAME = 3
# Leagues normal play sticks to. Anything outside is Expert-only (difficulty 4),
# so a random Peruvian or youth-era Brazilian club never turns up on Medium.
TOP5 = {"GBR", "ENG", "ESP", "ITA", "GER", "FRA", "MCO"}
KNOWN_LEAGUES = TOP5 | {"NED", "POR", "SCO", "TUR", "BEL", "USA", "KSA"}
# European leagues: an Expert career path is mostly played in Europe.
EUROPE = TOP5 | {
    "NED", "POR", "SCO", "WAL", "NIR", "IRL", "TUR", "BEL", "RUS", "SWE", "ROU", "POL", "SRB", "NOR", "AUT",
    "DEN", "UKR", "SUI", "BUL", "GRE", "HUN", "CZE", "CRO", "SVN", "FIN", "LTU", "LVA", "EST", "CYP", "BLR",
    "ISR", "BIH", "SVK", "ISL", "LUX", "KAZ", "GEO", "AZE", "ALB", "MKD", "MNE", "MDA", "ARM", "MLT", "FRO",
    "AND", "SMR", "KOS", "GIB", "LIE",
}
# Generated from Wikidata by normalise.py, or the old hand-written demo seed.
DATA_STATUS = "wikidata" if "GENERATED" in (SEED / "players.json").read_text(encoding="utf-8")[:300] else "demo_unverified"
CONNECTION_MIN_ANSWER_FAME = 2
CAREER_MIN_FAME = 2
# Career Path, Hard and Expert: Wikipedias covering the player, plus a lift for
# a real spell in Britain. Below the Expert line, nobody would get them.
# Career Path, Easy: Wikipedias covering the player, clubs, and still playing
# in or after this year.
CAREER_EASY_REACH = 75
CAREER_EASY_CLUBS = 4
CAREER_EASY_SINCE = 1990
CAREER_BRITISH_LIFT = 18
# Hard and Expert need a spell in one of these (England's top clubs, Spain,
# Germany); Celtic, Rangers and Hibs share England's country code.
BIG_THREE = {"GBR", "ENG", "ESP", "GER"}
SCOTTISH = {"Q19593", "Q19597", "Q192597"}
CAREER_BIG_THREE_APPS = 50
CAREER_MIN_CLUBS_HARD = 4
# The biggest clubs in the world: a recent move to one makes a player Medium.
GIANTS = {
    "Q1130849", "Q18552", "Q18656", "Q9617", "Q9616", "Q50602", "Q18741",  # Liverpool, Man Utd, Arsenal, Chelsea, City, Spurs
    "Q8682", "Q7156", "Q8701", "Q15789", "Q41420",  # Real, Barça, Atlético, Bayern, Dortmund
    "Q1422", "Q1543", "Q631", "Q483020",  # Juventus, Milan, Inter, PSG
}
CAREER_HARD_SCORE = 56
CAREER_EXPERT_SCORE = 48


def generate_connections(clubs, players):
    """Pairs built from each player's own clubs (fast at 20k+ players)."""
    CLUB_FAME.update({cid: c["fame"] for cid, c in clubs.items()})
    pairs: dict[tuple[str, str], set[str]] = {}
    for pid, p in players.items():
        own = sorted({s["club"] for s in p["spells"] if clubs[s["club"]]["fame"] >= CONNECTION_MIN_CLUB_FAME})
        for a, b in itertools.combinations(own, 2):
            pairs.setdefault((a, b), set()).add(pid)
    out = []
    for (a, b), shared in sorted(pairs.items()):
        best = max(players[pid]["fame"] for pid in shared)
        if best < CONNECTION_MIN_ANSWER_FAME:
            continue  # nobody guessable
        diff = connection_difficulty(a, b, sorted(shared), clubs, players)
        eras = 0
        for pid in shared:
            eras |= spells_mask([s for s in players[pid]["spells"] if s["club"] in (a, b)])
        out.append({"id": f"{a}|{b}", "a": a, "b": b, "answers": sorted(shared), "best": best,
                    "difficulty": diff, "eras": eras or 31})
    return out


# ---- grid categories -----------------------------------------------------
# Rows and columns for Noughts & Crosses besides clubs: a nation ("Wales"), a
# star's teammates ("Played with Messi"), a manager's players ("Managed by
# Ferguson"). Each comes with, per club, the players who fit both.
GRID_NATIONS = {
    "ENG": "England", "SCO": "Scotland", "WAL": "Wales", "IRL": "Republic of Ireland",
    "NIR": "Northern Ireland", "FRA": "France", "ESP": "Spain", "ITA": "Italy", "GER": "Germany",
    "NED": "Netherlands", "POR": "Portugal", "BEL": "Belgium", "DEN": "Denmark", "SWE": "Sweden",
    "NOR": "Norway", "CRO": "Croatia", "SRB": "Serbia", "BRA": "Brazil", "ARG": "Argentina",
    "URU": "Uruguay", "COL": "Colombia", "USA": "USA", "NGA": "Nigeria", "CIV": "Ivory Coast",
    "SEN": "Senegal", "GHA": "Ghana", "CMR": "Cameroon", "MAR": "Morocco", "AUS": "Australia",
    "KOR": "South Korea",
}
# Stars whose club teammates make a category, with the name the grid shows.
GRID_STARS = {
    "lionel-messi": "Messi", "cristiano-ronaldo": "Cristiano Ronaldo", "david-beckham": "Beckham",
    "steven-gerrard": "Gerrard", "zinedine-zidane": "Zidane", "gianluigi-buffon": "Buffon",
    "zlatan-ibrahimovic": "Ibrahimović", "thierry-henry": "Henry", "wayne-rooney": "Rooney",
    "frank-lampard": "Lampard", "john-terry": "Terry", "didier-drogba": "Drogba", "ronaldinho": "Ronaldinho",
    "kaka": "Kaká", "xavi-hernandez": "Xavi", "andres-iniesta": "Iniesta", "neymar": "Neymar",
    "mohamed-salah": "Salah", "harry-kane": "Kane", "kevin-de-bruyne": "De Bruyne",
    "robert-lewandowski": "Lewandowski", "kylian-mbappe": "Mbappé", "karim-benzema": "Benzema",
    "luka-modric": "Modrić", "andrea-pirlo": "Pirlo", "francesco-totti": "Totti", "paolo-maldini": "Maldini",
    "ronaldo": "Ronaldo (R9)", "paul-scholes": "Scholes", "ryan-giggs": "Giggs", "robin-van-persie": "Van Persie",
    "sergio-aguero": "Agüero", "luis-suarez": "Suárez", "erling-haaland": "Haaland", "gareth-bale": "Bale",
    "alan-shearer": "Shearer", "eric-cantona": "Cantona", "dennis-bergkamp": "Bergkamp", "roy-keane": "Roy Keane",
    "michael-owen": "Owen", "fernando-torres": "Torres", "sergio-ramos": "Ramos", "luis-figo": "Figo",
    "raul": "Raúl", "patrick-vieira": "Vieira", "cesc-fabregas": "Fàbregas", "yaya-toure": "Yaya Touré",
    "vincent-kompany": "Kompany", "son-heung-min": "Son", "virgil-van-dijk": "Van Dijk",
}


# Cups whose winners make a category: anyone in the winning side on the day
# of a final (seed/final_winners.json), at any club.
GRID_CUPS = {
    "cl": "Champions League winner", "uel": "Europa League winner", "wc": "World Cup winner",
    "euro": "Euros winner", "fac": "FA Cup winner",
}


def _overlap(s1: int, e1: int, s2: int, e2: int) -> bool:
    """Spells (in years) that shared at least one season. A year-only overlap
    at the edges (one left in 2008, the other arrived in 2008) isn't enough,
    but a short spell inside the other one counts: a half-season loan in 2008
    while the other was there 2005-2010."""
    if max(s1, s2) < min(e1, e2):
        return True
    return (s1 == e1 and s2 < s1 < e2) or (s2 == e2 and s1 < s2 < e1)


def _years(spell) -> tuple[int, int] | None:
    if spell["start"] is None:
        return None
    return spell["start"], spell["end"] or dt.date.today().year


def generate_grid_categories(clubs, players):
    """([{id, label, kind}], [{category, club, answers, eras}]): who fits each
    category, then per club the ones who played there. A category is never
    paired with its own clubs: Spain x Barcelona, Messi's teammates x
    Barcelona, Ferguson's players x Man United would be too easy."""
    members: dict[str, set[str]] = {}
    own: dict[str, set[str]] = {}  # clubs a category isn't paired with
    # A teammate or manager category belongs to that star's or manager's
    # time, whatever clubs the players went on to: Cantona's teammates who
    # later joined Man City are still a 90s question, not a 2000s one.
    era_of: dict[str, int] = {}
    cats = []
    for code, label in GRID_NATIONS.items():
        cid = f"nat:{code}"
        cats.append({"id": cid, "label": label, "kind": "nation"})
        members[cid] = {pid for pid, p in players.items() if p["nat"] == code}
        own[cid] = {c for c, club in clubs.items()
                    if club["country"] == code or (code == "ENG" and club["country"] in ("GBR", "ENG"))}
    for star, label in GRID_STARS.items():
        if star not in players:
            continue
        cid = f"with:{star}"
        cats.append({"id": cid, "label": f"Club teammate of {label}", "kind": "teammate"})
        theirs = [(s["club"], y) for s in players[star]["spells"] if (y := _years(s))]
        era_of[cid] = career_mask(players[star]["spells"])
        own[cid] = {c for c, _ in theirs}
        members[cid] = {
            pid for pid, p in players.items() if pid != star and any(
                s["club"] == c and (y := _years(s)) and _overlap(*y, *ys) for s in p["spells"] for c, ys in theirs)
        }
    managers = json.loads((SEED / "grid_managers.json").read_text(encoding="utf-8"))["managers"]
    for m in managers:
        cid = f"mgr:{slug_id(m['name'])}"
        cats.append({"id": cid, "label": f"Managed by {m['short']}" + (" (club)" if m.get("national") else ""), "kind": "manager"})
        jobs = [(c, int(a[:4]), int(b[:4]) if b else dt.date.today().year) for c, a, b in m["spells"]]
        era_of[cid] = 0
        for _, a, b in jobs:
            era_of[cid] |= era_mask(a, b)
        own[cid] = {c for c, _, _ in jobs}
        members[cid] = {
            pid for pid, p in players.items() if any(
                s["club"] == c and (y := _years(s)) and _overlap(*y, a, b) for s in p["spells"] for c, a, b in jobs)
        }
    # Cup winners: in the winning side's line-up on the day of the final
    # (starters and substitutes; finals_squads.py reads them from Wikipedia).
    winners_path = SEED / "final_winners.json"
    if winners_path.exists():
        finals = json.loads(winners_path.read_text(encoding="utf-8"))["finals"]
        by_qid = {p["wikidata"]: p["id"] for p in json.loads((SEED / "players.json").read_text(encoding="utf-8"))["players"]}
        for comp, label in GRID_CUPS.items():
            cid = f"cup:{comp}"
            cats.append({"id": cid, "label": label, "kind": "cup"})
            own[cid] = set()
            members[cid] = {by_qid[q] for f in finals.get(comp, {}).values() for q in f["players"]
                            if q in by_qid and by_qid[q] in players}
    rosters = []
    for cat in cats:
        cid = cat["id"]
        by_club: dict[str, set[str]] = {}
        for pid in members[cid]:
            for s in players[pid]["spells"]:
                c = s["club"]
                if c not in own[cid] and clubs[c]["fame"] >= CONNECTION_MIN_CLUB_FAME:
                    by_club.setdefault(c, set()).add(pid)
        for c, ids in sorted(by_club.items()):
            if max(players[pid]["fame"] for pid in ids) < CONNECTION_MIN_ANSWER_FAME:
                continue
            eras = 0
            for pid in ids:
                eras |= spells_mask([s for s in players[pid]["spells"] if s["club"] == c])
            if era_of.get(cid):
                eras = (eras & era_of[cid]) or era_of[cid]
            rosters.append({"category": cid, "club": c, "answers": sorted(ids), "eras": eras or 31})
    return cats, rosters


def slug_id(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()).strip("-")


def generate_career_challenges(players, clubs):
    career_levels = load("career_levels.json")["levels"]
    out = []
    for pid, p in players.items():
        distinct = {s["club"] for s in p["spells"]}
        if p["fame"] >= CAREER_MIN_FAME and len(p["spells"]) >= 3 and len(distinct) >= 3:
            diff = career_difficulty(p, clubs)
            # normal play needs a career mostly in leagues people watch:
            # at least two top-five-league clubs (Kanté: Caen, Leicester, Chelsea ✓)
            top5_clubs = {s["club"] for s in p["spells"] if clubs[s["club"]]["country"] in TOP5}
            known = sum(1 for s in p["spells"] if clubs[s["club"]]["country"] in KNOWN_LEAGUES)
            if len(top5_clubs) < 2 or known * 2 < len(p["spells"]):  # and most of the career
                # A star with a real spell at a big European club stays at
                # their level (Iniesta, Haaland, Maradona), whatever came after.
                big_europe = any(clubs[s["club"]]["fame"] >= 4 and clubs[s["club"]]["country"] in KNOWN_LEAGUES
                                 and memorable_spell(p, s["club"]) for s in p["spells"])
                europe = sum(1 for s in p["spells"] if clubs[s["club"]]["country"] in EUROPE)
                if p["fame"] >= 4 and big_europe:
                    pass
                # Expert: lesser-known, but mostly in Europe, and somewhere a
                # UK group follows. A career away from Europe (Costa Rica,
                # the J-League) isn't a career path at all.
                elif europe * 2 >= len(p["spells"]) and known:
                    diff = 4
                else:
                    continue
            # Easy: the biggest names, with a proper journey (4+ clubs) and a
            # career people remember - not the old-era legends whose paths run
            # through 1970s American sides. The rest of the old Easy is Medium.
            if diff <= 2 and not p.get("women"):
                years = [y for sp in p["spells"] for y in (sp["start"], sp["end"]) if y is not None]
                if ((p.get("reach") or 0) >= CAREER_EASY_REACH and len(distinct) >= CAREER_EASY_CLUBS
                        and years and max(years) >= CAREER_EASY_SINCE):
                    diff = 1
                elif diff == 1:
                    diff = 2
            # Hard and Expert: still players people know. How widely they're
            # covered (Wikipedias), with a lift for a real spell in Britain -
            # Pennant or Rickie Lambert over a Hungarian journeyman.
            # (Women's football is covered less widely: its pool stays as it was.)
            if diff >= 3 and not p.get("women"):
                # Enough clues: four clubs or more (Tel's three is over too fast),
                # and a career mostly in Europe (not Japan, then Marseille, then back).
                europe = sum(1 for sp in p["spells"] if clubs[sp["club"]]["country"] in EUROPE)
                # A recent big move to one of the giants (Eze, Palace to Arsenal;
                # Mbeumo, Brentford to United): everyone's heard of it - Medium.
                if any(sp["club"] in GIANTS and sp["end"] is None and (sp["start"] or 0) >= CURRENT_YEAR - 6
                       and not sp["loan"] for sp in p["spells"]) and europe * 2 >= len(p["spells"]):
                    diff = 2
                elif len(distinct) < CAREER_MIN_CLUBS_HARD or europe * 2 < len(p["spells"]):
                    continue
            if diff >= 3 and not p.get("women"):
                british = any(clubs[s["club"]]["country"] in ("GBR", "ENG", "SCO", "WAL") and memorable_spell(p, s["club"])
                              for s in p["spells"])
                # A real spell in the Premier League, La Liga or the Bundesliga:
                # a career all in Italy (Bonaventura) is remembered for one club,
                # not the path.
                # Counted in league games where we have them: a squad place with
                # no games (Hein at Arsenal) or a youth contract isn't a spell.
                big_three_clubs = {sp["club"] for sp in p["spells"]
                                   if clubs[sp["club"]]["country"] in BIG_THREE and clubs[sp["club"]]["fame"] >= 3
                                   and sp["club"] not in SCOTTISH}
                stats = p.get("stats") or {}
                if stats:
                    big_three = sum(stats.get(c, [0])[0] for c in big_three_clubs) >= CAREER_BIG_THREE_APPS
                else:
                    big_three = any(memorable_spell(p, c) for c in big_three_clubs)
                if not big_three:
                    continue
                score = (p.get("reach") or 0) + (CAREER_BRITISH_LIFT if british else 0)
                if score >= CAREER_HARD_SCORE:
                    diff = 3
                elif score >= CAREER_EXPERT_SCORE:
                    diff = 4
                else:
                    continue
            diff = career_levels.get(pid, diff)
            out.append({"player": pid, "clues": len(p["spells"]), "difficulty": diff,
                        "eras": career_mask(p["spells"]) or 31})
    return out


# Bidding War: categories whose COMPLETE answer set is known from the data.
BID_MIN_ANSWERS = 5
BID_MAX_ANSWERS = 35
BID_MIN_CLUB_FAME = 4
# Leagues a UK group will know; keeps out e.g. J-League pairs.
BID_COUNTRIES = {"GBR", "ENG", "SCO", "ESP", "ITA", "GER", "FRA", "NED", "POR", "TUR", "BEL", "MCO"}


# Bidding only works if a team can realistically get a few: a
# category needs this many solid answers (known players with a real spell at
# the club — not a loan or a cameo) or it isn't used at all.
BID_MIN_SOLID = 3


def answers_mask(answers, players, club_ids) -> int:
    """Eras a list of answers mostly belongs to: each era that at least half of
    the recognisable answers (fame 2+, or all if none are) played in at these
    clubs. One 2000s cameo no longer makes a list of 90s players count as
    2000s, so ticking 2000s+ gets lists that are mostly 2000s+ players."""
    pool = [pid for pid in answers if players[pid]["fame"] >= 2] or list(answers)
    masks = [spells_mask([s for s in players[pid]["spells"] if s["club"] in club_ids]) for pid in pool]
    masks = [m for m in masks if m]
    if not masks:
        return 0
    per = {bit: sum(1 for m in masks if m & bit) for bit, _, _ in ERAS}
    m = sum(bit for bit, n in per.items() if n * 2 >= len(masks))
    return m or max(per, key=per.get)


def bidding_difficulty(answers: list[str], players, club_ids=()) -> int | None:
    """Easy needs lots of recognisable answers; a category with 25 valid
    answers that nobody would know is rejected rather than called 'hard'.
    Málaga + Real Sociedad, with one or two names anyone knows, is rejected."""
    def solid(pid: str) -> bool:
        return players[pid]["fame"] >= 3 and all(memorable_spell(players[pid], c) for c in club_ids)

    known = sum(1 for pid in answers if solid(pid))
    guessable = sum(1 for pid in answers if players[pid]["fame"] >= 2)
    if guessable < BID_MIN_ANSWERS or known < BID_MIN_SOLID:
        return None
    return 1 if known >= 10 else 2 if known >= 5 else 3


def generate_bidding(clubs, players, connections, countries):
    out = []

    def add(cid, prompt, kind, answers, club_ids, floor=1):
        if any(clubs[c]["country"] not in BID_COUNTRIES for c in club_ids):
            return
        answers = sorted(answers)
        if not BID_MIN_ANSWERS <= len(answers) <= BID_MAX_ANSWERS:
            return
        diff = bidding_difficulty(answers, players, club_ids)
        if diff is None:
            return
        diff = max(diff, floor)
        eras = answers_mask(answers, players, club_ids)
        out.append({"id": cid, "prompt": prompt, "kind": kind, "answers": answers, "difficulty": diff, "eras": eras or 31})

    # 1. Played for both clubs
    for c in connections:
        if clubs[c["a"]]["fame"] >= BID_MIN_CLUB_FAME and clubs[c["b"]]["fame"] >= BID_MIN_CLUB_FAME:
            add(f"pair:{c['id']}", f"Players who have played for both {clubs[c['a']]['name']} and {clubs[c['b']]['name']}",
                "pair", c["answers"], {c["a"], c["b"]}, floor=c["difficulty"])  # no easier than the connection

    # 2. Nationality at a club ("Brazilians who played for Chelsea")
    by_club_nat: dict[tuple[str, str], set[str]] = {}
    for pid, p in players.items():
        if not p["nat"]:
            continue
        for cid in {s["club"] for s in p["spells"]}:
            if clubs[cid]["fame"] >= BID_MIN_CLUB_FAME and p["nat"] != clubs[cid]["country"]:
                by_club_nat.setdefault((cid, p["nat"]), set()).add(pid)
    for (cid, nat), answers in sorted(by_club_nat.items()):
        country = countries.get(nat)
        if country:
            # Medium only at clubs a UK group knows (Brazilians at Chelsea, not Colombians at Porto)
            familiar = clubs[cid]["country"] in ("GBR", "ENG") or cid in WELL_KNOWN
            add(f"nat:{cid}:{nat}", f"Players from {country} who have played for {clubs[cid]['name']}", "nationality", answers, {cid},
                floor=1 if familiar else 3)
    return out


# Club-type words a name can be written with or without ("PFC CSKA Moscow").
CLUB_WORDS = {"fc", "pfc", "afc", "cf", "sc", "fk", "sk", "ac", "as", "ss", "ssc", "cd", "ud", "sv", "rc", "rcd"}

# Lists can be long: Under the Radar is best with plenty of obscure right
# answers, and Bidding War just asks how many a team can name.
CURATED_MAX_ANSWERS = 250


def load_curated_bidding(players, clubs, problems: Problems) -> list[dict]:
    """Hand-made categories (records, awards, managers, clubs) from
    seed/bidding_curated.json. Answers are names, pinned with 'Name|id' where a
    name is ambiguous; 'Name|new' adds a person the career data lacks (e.g. a
    manager who never played at this level). "answers_are": "clubs" takes club
    names instead. Every answer must resolve, so the answer set stays complete.
    The curated name becomes an alias, so the common spelling can be typed
    ("Juan Mata"); club_aliases adds nicknames ("Spurs")."""
    path = SEED / "bidding_curated.json"
    if not path.exists():
        return []
    doc = json.loads(path.read_text(encoding="utf-8"))
    # The big lists radar_build.py makes from the raw data, read the same way.
    generated = SEED / "bidding_generated.json"
    if generated.exists():
        doc["categories"] = doc["categories"] + json.loads(generated.read_text(encoding="utf-8"))["categories"]

    def index(items) -> dict[str, str]:
        by_name: dict[str, str] = {}
        for key, item in sorted(items.items(), key=lambda kv: kv[1]["fame"]):  # most famous wins
            for n in [item["name"], *item["aliases"]]:
                by_name[norm(n)] = key
        return by_name

    # Hand-made categories are men's football: never resolve a name to the
    # women's side ("VfL Wolfsburg" must be the men's club, not Wolfsburg Women).
    def mens(items):
        return {k: v for k, v in items.items() if not v.get("women")}

    player_names, club_names = index(mens(players)), index(mens(clubs))

    # Club names also match without FC/PFC/AFC etc. ("CSKA Moscow" finds
    # "PFC CSKA Moscow" when a source starts using the full name).
    def core(n: str) -> str:
        return " ".join(w for w in norm(n).split() if w not in CLUB_WORDS)

    def resolve_club(raw: str) -> str | None:
        name, _, pin = raw.partition("|")
        if pin:
            return pin if pin in clubs else None
        return club_names.get(norm(name)) or club_cores.get(core(name))

    club_cores = {core(n): k for n, k in club_names.items()}
    for name, aliases in doc.get("club_aliases", {}).items():
        cid = resolve_club(name)
        if cid is None:
            problems.error(f"club_aliases: unknown club '{name}'")
            continue
        clubs[cid]["aliases"] = list(dict.fromkeys(clubs[cid]["aliases"] + aliases))
    club_names = index(mens(clubs))
    club_cores = {core(n): k for n, k in club_names.items()}

    out = []
    for c in doc["categories"]:
        is_clubs = c.get("answers_are") == "clubs"
        answers = []
        record: dict[str, list[int]] = {}  # answer -> [times won, most recent year]
        for raw in c["answers"]:
            name, _, pin = raw.partition("|")
            if is_clubs:
                key = resolve_club(raw)
                table = clubs
            elif pin == "new" or pin.startswith("new:"):
                # 'Name|new:5' sets how well known they are (1-5), for Pointless scores
                key = "curated-" + norm(name).replace(" ", "-")
                fame = int(pin[4:]) if pin.startswith("new:") else 3
                players.setdefault(key, {"name": name, "nat": None, "pos": None, "fame": fame, "aliases": [],
                                         "spells": [], "women": False})
                table = players
            else:
                key = (pin if pin in players else None) if pin else player_names.get(norm(name))
                table = players
            if key is None:
                problems.error(f"curated bidding {c['id']}: can't resolve '{raw}'")
                continue
            if norm(name) != norm(table[key]["name"]) and name not in table[key]["aliases"]:
                table[key]["aliases"].append(name)
            answers.append(key)
            if raw in c.get("record", {}):
                record[key] = c["record"][raw]
        if len(set(answers)) != len(answers):
            problems.error(f"curated bidding {c['id']}: same answer twice")
        if not BID_MIN_ANSWERS <= len(answers) <= CURATED_MAX_ANSWERS:
            problems.error(f"curated bidding {c['id']}: {len(answers)} answers, need {BID_MIN_ANSWERS}-{CURATED_MAX_ANSWERS}")
        prefix = "clubs" if is_clubs else "stat"
        out.append({"id": f"{prefix}:{c['id']}", "prompt": c["prompt"], "kind": "curated", "answers": sorted(set(answers)),
                    "difficulty": c["difficulty"], "eras": c["eras"], "record": record,
                    # "radar": false = Bidding War only: every answer's well known
                    # ("Clubs that have won the Premier League"), nothing to dig for.
                    "radar": c.get("radar", True)})
    return out


# Pointless: an answer's score stands in for "how many of 100 people would
# say it". Real survey data doesn't exist for free, so it comes from how well
# known each answer is (Wikipedia reach) RELATIVE to the rest of its list: the
# best-known answer scores high, the least-known scores 0 — every list has a
# pointless answer. Bigger lists spread the votes, so their top score is lower.
FAME_REACH = {5: 0.85, 4: 0.62, 3: 0.45, 2: 0.3, 1: 0.15}


def known_ness(item: dict) -> float:
    reach = item.get("reach")
    if reach:
        return max(0.0, min(1.0, (math.log(reach) - math.log(4)) / (math.log(250) - math.log(4))))
    return FAME_REACH.get(item.get("fame", 1), 0.15)


# For winners lists, how memorable an answer is for THAT question: times won
# and how recently (PSG's back-to-back titles beat Marseille's one in 1993).
THIS_YEAR = 2026


def memorable(times: int, last: int) -> float:
    recency = max(0.0, 1 - (THIS_YEAR - last) / 40)
    return 0.4 * recency + 0.6 * min(1.0, times / 5) ** 0.5


def pointless_scores(answers: list[str], table: dict, record: dict | None = None) -> dict[str, int]:
    """Half how famous the answer is overall, half where it ranks in its own
    list — so a list of all-famous names doesn't hand out zeros, but the
    genuinely obscure ones still go pointless. Where the list has a record of
    wins, that counts for more than general fame."""
    k = {a: known_ness(table[a]) for a in answers}
    if record:
        k = {a: 0.55 * x + 0.45 * memorable(*record[a]) if a in record else x for a, x in k.items()}
    lo, hi = min(k.values()), max(k.values())
    top = max(30, min(90, round(260 / math.sqrt(len(answers)))))
    out = {}
    least = min(k, key=lambda a: (k[a], a))
    for a, x in k.items():
        rel = (x - lo) / (hi - lo) if hi > lo else 0.5
        blend = 0.5 * x + 0.5 * rel
        # The single least-known answer in the list is pointless (as on the
        # show, nearly every question has one) — unless it's a genuine star.
        pointless = blend < 0.12 or (a == least and x < 0.6)
        out[a] = 0 if pointless else max(1, round(top * blend ** 1.6))
    return out


def add_pointless_scores(bidding: list[dict], players, clubs) -> None:
    for b in bidding:
        table = clubs if b["id"].startswith("clubs:") else players
        # No scores = not an Under the Radar question (the app skips it).
        b["scores"] = pointless_scores(b["answers"], table, b.get("record")) if b.get("radar", True) else {}
        b["women"] = all(table[a].get("women") for a in b["answers"])


# Football 501: name players, their league apps + goals for a club come off
# 501. A club makes a category when enough players have numbers, and enough of
# them score 180 or less (a "dart") for two teams to share without running dry.
CHECKOUT_MIN_PLAYERS = 40
CHECKOUT_MIN_DARTS = 30
CHECKOUT_MIN_KNOWN = 15
# Abroad, only clubs a UK group follows closely enough to guess numbers for
# are level 1: the rest (Villarreal, Sevilla, Schalke...) are for Hard and up.
CHECKOUT_FOREIGN_GIANTS = {
    "Q7156", "Q8682", "Q8701",  # Barcelona, Real Madrid, Atlético Madrid
    "Q15789", "Q41420",  # Bayern Munich, Borussia Dortmund
    "Q1422", "Q1543", "Q631",  # Juventus, AC Milan, Inter
    "Q483020",  # Paris Saint-Germain
}


def checkout_level(cid: str, c) -> int:
    """1 = British giants and the biggest clubs abroad; 2 = other British
    clubs (and women's sides, as before); 3 = other clubs abroad."""
    if c["women"]:
        return 2
    if c["country"] in ("GBR", "ENG", "SCO"):
        return 1 if c["fame"] == 5 else 2
    return 1 if cid in CHECKOUT_FOREIGN_GIANTS else 3


def generate_checkouts(clubs, players) -> list[dict]:
    played: dict[str, set[str]] = {}
    with_stats: dict[str, dict[str, list[int]]] = {}
    for pid, p in players.items():
        for sp in p["spells"]:
            played.setdefault(sp["club"], set()).add(pid)
        for cid, ag in p.get("stats", {}).items():
            if cid in clubs and ag[0] > 0:
                with_stats.setdefault(cid, {})[pid] = ag
    out = []
    for cid, values in with_stats.items():
        c = clubs[cid]
        if c["fame"] < 4 or c["country"] not in KNOWN_LEAGUES:
            continue
        darts = sum(1 for a, g in values.values() if a + g <= 180)
        known = sum(1 for pid in values if players[pid]["fame"] >= 2)
        if len(values) < CHECKOUT_MIN_PLAYERS or darts < CHECKOUT_MIN_DARTS or known < CHECKOUT_MIN_KNOWN:
            continue
        eras = 0
        for pid in values:
            eras |= spells_mask([sp for sp in players[pid]["spells"] if sp["club"] == cid])
        out.append({
            "id": f"501:{cid}", "club": cid, "prompt": f"League apps + goals for {c['name']}",
            "values": values, "no_stats": sorted(played.get(cid, set()) - set(values)),
            "difficulty": checkout_level(cid, c), "eras": eras or 31, "women": c["women"],
        })
    return out


def load_generated_checkouts(players, problems: Problems) -> list[dict]:
    """Football 501 by country (radar_build.py): caps + goals. A player the
    career data lacks comes in as 'Name|new:1' and is added (no career), so
    the list stays complete."""
    path = SEED / "checkouts_generated.json"
    if not path.exists():
        return []
    out = []
    for c in json.loads(path.read_text(encoding="utf-8"))["categories"]:
        values = {}
        for raw, (caps, goals) in c["values"].items():
            name, _, pin = raw.partition("|")
            if pin.startswith("new"):
                pid = "curated-" + norm(name).replace(" ", "-")
                players.setdefault(pid, {"name": name, "nat": None, "pos": None, "fame": int(pin[4:] or 1) if ":" in pin else 1,
                                         "aliases": [], "spells": [], "women": c["women"]})
            elif pin in players:
                pid = pin
            else:
                problems.error(f"{c['id']}: unknown player {raw}")
                continue
            values[pid] = [caps, goals]
        out.append({"id": c["id"], "club": c["id"], "prompt": c["prompt"], "values": values, "no_stats": [],
                    "difficulty": c["difficulty"], "eras": 31, "women": c["women"]})
    return out


def match_eras(m) -> int:
    year = int(m["date"][:4])
    return era_mask(year, year)


def write_db(path: pathlib.Path, version: int, clubs, players, matches, connections, careers, bidding, checkouts, grid):
    if path.exists():
        path.unlink()
    con = sqlite3.connect(path)
    con.executescript(SCHEMA)
    meta = {
        "db_version": str(version),
        "built_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "data_status": DATA_STATUS,
        "players": str(len(players)),
        "connections": str(len(connections)),
    }
    con.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
    for cid, c in clubs.items():
        con.execute("INSERT INTO clubs VALUES (?,?,?,?,NULL,?)", (cid, c["name"], c["country"], c["fame"], int(c["women"])))
        con.executemany("INSERT INTO club_aliases VALUES (?,?)", [(cid, a) for a in c["aliases"]])
    for pid, p in players.items():
        con.execute("INSERT INTO players VALUES (?,?,?,?,?,0,'demo_seed',NULL,?)",
                    (pid, p["name"], p["nat"], p["pos"], p["fame"], int(p.get("women", False))))
        con.executemany("INSERT INTO player_aliases VALUES (?,?)", [(pid, a) for a in p["aliases"]])
        con.executemany("INSERT INTO player_spoken VALUES (?,?)", [(pid, s) for s in p.get("spoken", [])])
        con.executemany("INSERT INTO career_spells VALUES (?,?,?,?,?,?)",
                        [(pid, s["seq"], s["club"], s["start"], s["end"], int(s["loan"])) for s in p["spells"]])
    for m in matches:
        # Verified = the XI agrees across two independent sources.
        sources = m.get("sources", [])
        con.execute("INSERT INTO matches VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (m["id"], m["title"], m["competition"], m["date"], m["home"], m["away"],
                     m["score"], m["target"], m["fame"], match_difficulty(m["fame"]),
                     1 if len(sources) >= 2 else 0, " | ".join(sources) or "demo_seed", match_eras(m),
                     m.get("weight", 1)))
        con.executemany("INSERT INTO lineup_slots VALUES (?,?,?,?)",
                        [(m["id"], i, pid, pos) for i, (pid, _n, pos) in enumerate(m["xi"])])
    for c in connections:
        con.execute("INSERT INTO club_connections VALUES (?,?,?,?,?,?,?)",
                    (c["id"], c["a"], c["b"], len(c["answers"]), c["best"], c["difficulty"], c["eras"]))
        con.executemany("INSERT INTO connection_answers VALUES (?,?)", [(c["id"], pid) for pid in c["answers"]])
    cats, rosters = grid
    con.executemany("INSERT INTO grid_categories VALUES (?,?,?)", [(c["id"], c["label"], c["kind"]) for c in cats])
    con.executemany("INSERT INTO category_rosters VALUES (?,?,?,?)",
                    [(r["category"], r["club"], r["eras"], ",".join(r["answers"])) for r in rosters])
    con.executemany("INSERT INTO career_challenges VALUES (?,?,?,?)",
                    [(c["player"], c["clues"], c["difficulty"], c["eras"]) for c in careers])
    for b in bidding:
        con.execute("INSERT INTO bidding_categories VALUES (?,?,?,?,?,?,?)",
                    (b["id"], b["prompt"], b["kind"], len(b["answers"]), b["difficulty"], b["eras"], int(b["women"])))
        con.executemany("INSERT INTO bidding_answers VALUES (?,?,?)",
                        [(b["id"], pid, b["scores"].get(pid)) for pid in b["answers"]])
    for c in checkouts:
        con.execute("INSERT INTO checkout_categories VALUES (?,?,?,?,?,?)",
                    (c["id"], c["prompt"], c["club"], c["difficulty"], c["eras"], int(c["women"])))
        con.executemany("INSERT INTO checkout_answers VALUES (?,?,?,?)",
                        [(c["id"], pid, a, g) for pid, (a, g) in c["values"].items()]
                        + [(c["id"], pid, None, None) for pid in c["no_stats"]])
    con.commit()
    con.execute("VACUUM")
    con.close()


def write_json(path: pathlib.Path, version: int, clubs, players, matches, connections, careers, bidding, checkouts, grid):
    """Same content as the SQLite file, for the web build (no SQLite plugin in browsers)."""
    doc = {
        "db_version": version,
        "data_status": DATA_STATUS,
        # clubs: [id, name, country, fame, aliases, "w" for a women's club]
        "clubs": [[cid, c["name"], c["country"], c["fame"], c["aliases"], *(["w"] if c["women"] else [])]
                  for cid, c in clubs.items()],
        "players": [
            {"id": pid, "name": p["name"], "nat": p["nat"], "pos": p["pos"], "fame": p["fame"], "aliases": p["aliases"],
             **({"g": "w"} if p.get("women") else {}), **({"sp": p["spoken"]} if p.get("spoken") else {})}
            for pid, p in players.items()
        ],
        "careers": [
            {"player": c["player"], "difficulty": c["difficulty"], "eras": c["eras"],
             "spells": [[s["club"], s["start"], s["end"], int(s["loan"])] for s in players[c["player"]]["spells"]]}
            for c in careers
        ],
        "connections": [[c["id"], c["a"], c["b"], c["difficulty"], c["answers"], c["eras"]] for c in connections],
        # grid categories: [id, label, kind]; rosters: [category, club, players, eras]
        "categories": [[c["id"], c["label"], c["kind"]] for c in grid[0]],
        "category_rosters": [[r["category"], r["club"], r["answers"], r["eras"]] for r in grid[1]],
        # bidding: [id, prompt, difficulty, answers, eras, pointless scores
        # (null = not for Under the Radar), 1 if women's]
        "bidding": [[b["id"], b["prompt"], b["difficulty"], b["answers"], b["eras"],
                     [b["scores"][a] for a in b["answers"]] if b["scores"] else None, int(b["women"])] for b in bidding],
        # 501: [id, prompt, difficulty, eras, 1 if women's, [[player, apps, goals]...], [played, no numbers]]
        "checkouts": [[c["id"], c["prompt"], c["difficulty"], c["eras"], int(c["women"]),
                       [[pid, a, g] for pid, (a, g) in sorted(c["values"].items())], c["no_stats"]] for c in checkouts],
        "matches": [
            {"id": m["id"], "title": m["title"], "competition": m["competition"], "date": m["date"],
             "home": m["home"], "away": m["away"], "score": m["score"], "target": m["target"],
             "difficulty": match_difficulty(m["fame"]), "eras": match_eras(m), "weight": m.get("weight", 1),
             "xi": m["xi"]}
            for m in matches
        ],
    }
    path.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def add_spoken(players, problems: Problems) -> None:
    """Respellings of how each name sounds (voice answers), plus fixes from voice tests."""
    spoken.selftest()
    overrides = load("spoken_overrides.json")["players"]
    for pid in overrides:
        if pid not in players:
            problems.error(f"spoken_overrides: unknown player {pid}")
    for pid, p in players.items():
        p["spoken"] = spoken.spoken_variants(p["name"], p.get("nat"), overrides.get(pid, []))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    # Unique per build (YYYYMMDDHHMM) so installed apps always re-copy an updated database.
    ap.add_argument("--version", type=int, default=int(dt.datetime.now().strftime("%Y%m%d%H%M")))
    args = ap.parse_args()

    problems = Problems()
    clubs, players, matches = validate_and_collect(problems)
    curated = load_curated_bidding(players, clubs, problems)
    add_spoken(players, problems)
    for w in problems.warnings:
        print("WARN ", w)
    for e in problems.errors:
        print("ERROR", e)
    if problems.errors:
        return 1

    connections = generate_connections(clubs, players)
    careers = generate_career_challenges(players, clubs)
    grid = generate_grid_categories(clubs, players)
    countries_path = SEED / "countries.json"
    countries = json.loads(countries_path.read_text(encoding="utf-8"))["countries"] if countries_path.exists() else {}
    bidding = generate_bidding(clubs, players, connections, countries) + curated
    add_pointless_scores(bidding, players, clubs)
    checkouts = generate_checkouts(clubs, players) + load_generated_checkouts(players, problems)
    by_diff = {d: sum(1 for c in connections if c["difficulty"] == d) for d in (1, 2, 3, 4)}
    print(f"players={len(players)} clubs={len(clubs)} matches={len(matches)} "
          f"connections={len(connections)} {by_diff} careers={len(careers)} bidding={len(bidding)} "
          f"{ {d: sum(1 for b in bidding if b['difficulty'] == d) for d in (1, 2, 3)} } curated={len(curated)} "
          f"checkouts={len(checkouts)} (women {sum(1 for c in checkouts if c['women'])}) grid_categories={len(grid[0])} rosters={len(grid[1])}")
    if args.check:
        return 0

    ASSETS.mkdir(parents=True, exist_ok=True)
    write_db(ASSETS / "football.db", args.version, clubs, players, matches, connections, careers, bidding, checkouts, grid)
    write_json(ASSETS / "football.json", args.version, clubs, players, matches, connections, careers, bidding, checkouts, grid)
    (ASSETS / "football_db_version.txt").write_text(str(args.version), encoding="utf-8")
    print("wrote", ASSETS / "football.db", "version", args.version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
