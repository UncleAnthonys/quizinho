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
import pathlib
import sqlite3
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent
SEED = ROOT / "seed"
ASSETS = ROOT.parent / "assets" / "db"

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE clubs (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, country TEXT, fame INTEGER NOT NULL,
  wikidata_id TEXT
);
CREATE TABLE club_aliases (club_id TEXT NOT NULL REFERENCES clubs(id), alias TEXT NOT NULL);
CREATE TABLE players (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, nationality TEXT, position TEXT,
  fame INTEGER NOT NULL, verified INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL,
  wikidata_id TEXT
);
CREATE TABLE player_aliases (player_id TEXT NOT NULL REFERENCES players(id), alias TEXT NOT NULL);
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
  eras INTEGER NOT NULL
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
CREATE TABLE bidding_categories (
  id TEXT PRIMARY KEY, prompt TEXT NOT NULL, kind TEXT NOT NULL,
  answer_count INTEGER NOT NULL, difficulty INTEGER NOT NULL, eras INTEGER NOT NULL
);
CREATE TABLE bidding_answers (
  category_id TEXT NOT NULL REFERENCES bidding_categories(id),
  player_id TEXT NOT NULL REFERENCES players(id)
);
CREATE INDEX idx_match_diff ON matches(difficulty);
CREATE INDEX idx_bid_ans ON bidding_answers(category_id);
"""

POSITIONS = {"GK", "RB", "CB", "LB", "RWB", "LWB", "DM", "CM", "AM", "RM", "LM", "RW", "LW", "ST"}


def load(name: str) -> dict:
    return json.loads((SEED / name).read_text(encoding="utf-8"))


def connection_difficulty(best_fame: int, club_fame_a: int, club_fame_b: int) -> int:
    """1 easy .. 4 expert. Driven by how famous the best answer is, then the clubs."""
    score = best_fame * 0.6 + (club_fame_a + club_fame_b) / 2 * 0.4
    if score >= 4.6:
        return 1
    if score >= 3.8:
        return 2
    if score >= 3.0:
        return 3
    return 4


def career_difficulty(fame: int) -> int:
    return {5: 1, 4: 2, 3: 3}.get(fame, 4)


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
    matches_doc = load("matches.json")

    clubs = {}
    for cid, name, country, fame, aliases in clubs_raw:
        if cid in clubs:
            problems.error(f"duplicate club id {cid}")
        if not 1 <= fame <= 5:
            problems.error(f"club {cid} fame out of range")
        clubs[cid] = {"name": name, "country": country, "fame": fame, "aliases": aliases}

    players = {}
    for p in players_raw:
        pid = p["id"]
        if pid in players:
            problems.error(f"duplicate player id {pid}")
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
            "name": p["name"], "nat": p.get("nat"), "pos": p.get("pos"), "fame": p["fame"],
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
            if real is None:
                # not in the career data: create a line-up-only player
                real = pid
                players[pid] = {"name": name, "nat": None, "pos": pos, "fame": 3, "aliases": [], "spells": []}
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


# Club Connections / Tic-Tac-Toe only use clubs at least this well known, and
# a pair needs at least one answer at least this famous — technically valid but
# unguessable pairs ("Kauno Žalgiris + Vegalta Sendai") are no fun.
CONNECTION_MIN_CLUB_FAME = 3
# Leagues normal play sticks to. Anything outside is Expert-only (difficulty 4),
# so a random Peruvian or youth-era Brazilian club never turns up on Medium.
TOP5 = {"GBR", "ENG", "ESP", "ITA", "GER", "FRA", "MCO"}
KNOWN_LEAGUES = TOP5 | {"NED", "POR", "SCO", "TUR", "BEL", "USA", "KSA"}
# Generated from Wikidata by normalise.py, or the old hand-written demo seed.
DATA_STATUS = "wikidata" if "GENERATED" in (SEED / "players.json").read_text(encoding="utf-8")[:300] else "demo_unverified"
CONNECTION_MIN_ANSWER_FAME = 2
CAREER_MIN_FAME = 2


def generate_connections(clubs, players):
    """Pairs built from each player's own clubs (fast at 20k+ players)."""
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
        diff = connection_difficulty(best, clubs[a]["fame"], clubs[b]["fame"])
        if clubs[a]["country"] not in KNOWN_LEAGUES or clubs[b]["country"] not in KNOWN_LEAGUES:
            diff = 4
        eras = 0
        for pid in shared:
            eras |= spells_mask([s for s in players[pid]["spells"] if s["club"] in (a, b)])
        out.append({"id": f"{a}|{b}", "a": a, "b": b, "answers": sorted(shared), "best": best,
                    "difficulty": diff, "eras": eras or 31})
    return out


def generate_career_challenges(players, clubs):
    out = []
    for pid, p in players.items():
        distinct = {s["club"] for s in p["spells"]}
        if p["fame"] >= CAREER_MIN_FAME and len(p["spells"]) >= 3 and len(distinct) >= 3:
            diff = career_difficulty(p["fame"])
            # normal play needs a career mostly in leagues people watch:
            # at least two top-five-league clubs (Kanté: Caen, Leicester, Chelsea ✓)
            top5_clubs = {s["club"] for s in p["spells"] if clubs[s["club"]]["country"] in TOP5}
            known = sum(1 for s in p["spells"] if clubs[s["club"]]["country"] in KNOWN_LEAGUES)
            if len(top5_clubs) < 2 or known * 2 < len(p["spells"]):  # and most of the career
                diff = 4
            out.append({"player": pid, "clues": len(p["spells"]), "difficulty": diff,
                        "eras": spells_mask(p["spells"]) or 31})
    return out


# Bidding War: categories whose COMPLETE answer set is known from the data.
BID_MIN_ANSWERS = 5
BID_MAX_ANSWERS = 35
BID_MIN_CLUB_FAME = 4
# Leagues a UK group will know; keeps out e.g. J-League pairs.
BID_COUNTRIES = {"GBR", "ENG", "SCO", "ESP", "ITA", "GER", "FRA", "NED", "POR", "TUR", "BEL", "MCO"}


def bidding_difficulty(answers: list[str], players) -> int | None:
    """Easy needs lots of recognisable answers; a category with 25 valid
    answers that nobody would know is rejected rather than called 'hard'."""
    known = sum(1 for pid in answers if players[pid]["fame"] >= 3)
    guessable = sum(1 for pid in answers if players[pid]["fame"] >= 2)
    if guessable < BID_MIN_ANSWERS or known < 2:
        return None
    return 1 if known >= 10 else 2 if known >= 5 else 3


def generate_bidding(clubs, players, connections, countries):
    out = []

    def add(cid, prompt, kind, answers, club_ids):
        if any(clubs[c]["country"] not in BID_COUNTRIES for c in club_ids):
            return
        answers = sorted(answers)
        if not BID_MIN_ANSWERS <= len(answers) <= BID_MAX_ANSWERS:
            return
        diff = bidding_difficulty(answers, players)
        if diff is None:
            return
        eras = 0
        for pid in answers:
            eras |= spells_mask([s for s in players[pid]["spells"] if s["club"] in club_ids])
        out.append({"id": cid, "prompt": prompt, "kind": kind, "answers": answers, "difficulty": diff, "eras": eras or 31})

    # 1. Played for both clubs
    for c in connections:
        if clubs[c["a"]]["fame"] >= BID_MIN_CLUB_FAME and clubs[c["b"]]["fame"] >= BID_MIN_CLUB_FAME:
            add(f"pair:{c['id']}", f"Players who played for both {clubs[c['a']]['name']} and {clubs[c['b']]['name']}",
                "pair", c["answers"], {c["a"], c["b"]})

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
            add(f"nat:{cid}:{nat}", f"Players from {country} who played for {clubs[cid]['name']}", "nationality", answers, {cid})
    return out


def load_curated_bidding(players, problems: Problems) -> list[dict]:
    """Hand-made categories (records, awards, famous squads) from
    seed/bidding_curated.json. Answers are names, pinned with 'Name|id' where a
    name is ambiguous; 'Name|new' adds a player the career data lacks. Every
    answer must resolve, so the answer set stays complete. The curated name
    becomes an alias, so the common spelling can be typed ("Juan Mata")."""
    path = SEED / "bidding_curated.json"
    if not path.exists():
        return []
    by_name: dict[str, str] = {}
    for pid, p in sorted(players.items(), key=lambda kv: kv[1]["fame"]):  # most famous wins
        for n in [p["name"], *p["aliases"]]:
            by_name[norm(n)] = pid
    out = []
    for c in json.loads(path.read_text(encoding="utf-8"))["categories"]:
        answers = []
        for raw in c["answers"]:
            name, _, pin = raw.partition("|")
            if pin == "new":
                pid = "curated-" + norm(name).replace(" ", "-")
                players.setdefault(pid, {"name": name, "nat": None, "pos": None, "fame": 3, "aliases": [], "spells": []})
            elif pin:
                pid = pin if pin in players else None
            else:
                pid = by_name.get(norm(name))
            if pid is None:
                problems.error(f"curated bidding {c['id']}: can't resolve '{raw}'")
                continue
            if norm(name) != norm(players[pid]["name"]) and name not in players[pid]["aliases"]:
                players[pid]["aliases"].append(name)
            answers.append(pid)
        if len(set(answers)) != len(answers):
            problems.error(f"curated bidding {c['id']}: same player twice")
        if not BID_MIN_ANSWERS <= len(answers) <= BID_MAX_ANSWERS:
            problems.error(f"curated bidding {c['id']}: {len(answers)} answers, need {BID_MIN_ANSWERS}-{BID_MAX_ANSWERS}")
        out.append({"id": f"stat:{c['id']}", "prompt": c["prompt"], "kind": "curated", "answers": sorted(set(answers)),
                    "difficulty": c["difficulty"], "eras": c["eras"]})
    return out


def match_eras(m) -> int:
    year = int(m["date"][:4])
    return era_mask(year, year)


def write_db(path: pathlib.Path, version: int, clubs, players, matches, connections, careers, bidding):
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
        con.execute("INSERT INTO clubs VALUES (?,?,?,?,NULL)", (cid, c["name"], c["country"], c["fame"]))
        con.executemany("INSERT INTO club_aliases VALUES (?,?)", [(cid, a) for a in c["aliases"]])
    for pid, p in players.items():
        con.execute("INSERT INTO players VALUES (?,?,?,?,?,0,'demo_seed',NULL)",
                    (pid, p["name"], p["nat"], p["pos"], p["fame"]))
        con.executemany("INSERT INTO player_aliases VALUES (?,?)", [(pid, a) for a in p["aliases"]])
        con.executemany("INSERT INTO career_spells VALUES (?,?,?,?,?,?)",
                        [(pid, s["seq"], s["club"], s["start"], s["end"], int(s["loan"])) for s in p["spells"]])
    for m in matches:
        con.execute("INSERT INTO matches VALUES (?,?,?,?,?,?,?,?,?,?,0,'demo_seed',?)",
                    (m["id"], m["title"], m["competition"], m["date"], m["home"], m["away"],
                     m["score"], m["target"], m["fame"], match_difficulty(m["fame"]), match_eras(m)))
        con.executemany("INSERT INTO lineup_slots VALUES (?,?,?,?)",
                        [(m["id"], i, pid, pos) for i, (pid, _n, pos) in enumerate(m["xi"])])
    for c in connections:
        con.execute("INSERT INTO club_connections VALUES (?,?,?,?,?,?,?)",
                    (c["id"], c["a"], c["b"], len(c["answers"]), c["best"], c["difficulty"], c["eras"]))
        con.executemany("INSERT INTO connection_answers VALUES (?,?)", [(c["id"], pid) for pid in c["answers"]])
    con.executemany("INSERT INTO career_challenges VALUES (?,?,?,?)",
                    [(c["player"], c["clues"], c["difficulty"], c["eras"]) for c in careers])
    for b in bidding:
        con.execute("INSERT INTO bidding_categories VALUES (?,?,?,?,?,?)",
                    (b["id"], b["prompt"], b["kind"], len(b["answers"]), b["difficulty"], b["eras"]))
        con.executemany("INSERT INTO bidding_answers VALUES (?,?)", [(b["id"], pid) for pid in b["answers"]])
    con.commit()
    con.execute("VACUUM")
    con.close()


def write_json(path: pathlib.Path, version: int, clubs, players, matches, connections, careers, bidding):
    """Same content as the SQLite file, for the web build (no SQLite plugin in browsers)."""
    doc = {
        "db_version": version,
        "data_status": DATA_STATUS,
        "clubs": [[cid, c["name"], c["country"], c["fame"]] for cid, c in clubs.items()],
        "players": [
            {"id": pid, "name": p["name"], "nat": p["nat"], "pos": p["pos"], "fame": p["fame"], "aliases": p["aliases"]}
            for pid, p in players.items()
        ],
        "careers": [
            {"player": c["player"], "difficulty": c["difficulty"], "eras": c["eras"],
             "spells": [[s["club"], s["start"], s["end"], int(s["loan"])] for s in players[c["player"]]["spells"]]}
            for c in careers
        ],
        "connections": [[c["id"], c["a"], c["b"], c["difficulty"], c["answers"], c["eras"]] for c in connections],
        "bidding": [[b["id"], b["prompt"], b["difficulty"], b["answers"], b["eras"]] for b in bidding],
        "matches": [
            {"id": m["id"], "title": m["title"], "competition": m["competition"], "date": m["date"],
             "home": m["home"], "away": m["away"], "score": m["score"], "target": m["target"],
             "difficulty": match_difficulty(m["fame"]), "eras": match_eras(m), "xi": m["xi"]}
            for m in matches
        ],
    }
    path.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    # Unique per build (YYYYMMDDHHMM) so installed apps always re-copy an updated database.
    ap.add_argument("--version", type=int, default=int(dt.datetime.now().strftime("%Y%m%d%H%M")))
    args = ap.parse_args()

    problems = Problems()
    clubs, players, matches = validate_and_collect(problems)
    curated = load_curated_bidding(players, problems)
    for w in problems.warnings:
        print("WARN ", w)
    for e in problems.errors:
        print("ERROR", e)
    if problems.errors:
        return 1

    connections = generate_connections(clubs, players)
    careers = generate_career_challenges(players, clubs)
    countries_path = SEED / "countries.json"
    countries = json.loads(countries_path.read_text(encoding="utf-8"))["countries"] if countries_path.exists() else {}
    bidding = generate_bidding(clubs, players, connections, countries) + curated
    by_diff = {d: sum(1 for c in connections if c["difficulty"] == d) for d in (1, 2, 3, 4)}
    print(f"players={len(players)} clubs={len(clubs)} matches={len(matches)} "
          f"connections={len(connections)} {by_diff} careers={len(careers)} bidding={len(bidding)} "
          f"{ {d: sum(1 for b in bidding if b['difficulty'] == d) for d in (1, 2, 3)} } curated={len(curated)}")
    if args.check:
        return 0

    ASSETS.mkdir(parents=True, exist_ok=True)
    write_db(ASSETS / "football.db", args.version, clubs, players, matches, connections, careers, bidding)
    write_json(ASSETS / "football.json", args.version, clubs, players, matches, connections, careers, bidding)
    (ASSETS / "football_db_version.txt").write_text(str(args.version), encoding="utf-8")
    print("wrote", ASSETS / "football.db", "version", args.version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
