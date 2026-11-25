"""Builds the big Under the Radar (and Bidding War) lists from data already on
disk, so every answer set is complete and checkable:

  * the Premier League's own stats feed (raw/pl_stats.json.gz),
  * Wikipedia line-ups of finals (raw/finals_wikitext.json.gz),
  * Wikipedia squads, red cards, shoot-outs, own goals and record tables
    (raw/radar_wikitext.json.gz, raw/lists_wikitext.json.gz),
  * the career data (seed/players.json) and the grid's manager and teammate
    rosters (seed/grid_managers.json via the built database).

Writes seed/bidding_generated.json in the same shape as bidding_curated.json
(build_db.py reads both). Answers are pinned to player ids ("Name|id"); a
name the career data lacks comes in as "Name|new:1" so the list stays
complete. Lists that can't be read cleanly are left out and reported, never
guessed.

    python3 data_pipeline/radar_build.py
"""
from __future__ import annotations

import gzip
import json
import pathlib
import re
import sys
import unicodedata

HERE = pathlib.Path(__file__).parent
RAW, SEED = HERE / "raw", HERE / "seed"
sys.path.insert(0, str(HERE))

from finals_squads import LINK as FLINK, ROW, boxes, plain  # noqa: E402
from top10_build import feed_matcher  # noqa: E402
from top10_tables import LINK, strip_attr, tables  # noqa: E402

ALL_ERAS = 31


def era_bits(first: int, last: int) -> int:
    bits = 0
    for y in range(first, last + 1):
        bits |= 1 if y < 1992 else 2 if y < 2000 else 4 if y < 2010 else 8 if y < 2020 else 16
    return bits


def fold(t: str) -> str:
    return unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()


class Data:
    def __init__(self):
        players = json.loads((SEED / "players.json").read_text(encoding="utf-8"))["players"]
        known = json.loads((SEED / "wiki_names.json").read_text(encoding="utf-8")).get("players", {})
        # Shown by the name people know ("Eni Aluko"); the data's full name
        # ("Eniola Aluko") still matches, as an alias.
        self.by_qid = {p["wikidata"]: {**p, "name": known.get(p["id"], p["name"]),
                                       "aliases": [*p.get("aliases", []), p["name"]]} for p in players}
        self.by_id = {p["id"]: p for p in self.by_qid.values()}
        self.qids: dict[str, str] = {}
        self.pages: dict[str, str] = {}
        for f in ("lists_wikitext.json.gz", "finals_wikitext.json.gz", "radar_wikitext.json.gz"):
            doc = json.load(gzip.open(RAW / f, "rt", encoding="utf-8"))
            self.pages.update(doc["pages"])
            self.qids.update(doc.get("qids", {}))
        self.feed = json.load(gzip.open(RAW / "pl_stats.json.gz", "rt", encoding="utf-8"))["all"]
        self.match = feed_matcher(self.by_qid)
        clubs = json.loads((SEED / "clubs.json").read_text(encoding="utf-8"))["clubs"]
        self.club_name = {c[0]: c[1] for c in clubs}
        womens_clubs = {c[0] for c in clubs if len(c) > 6 and c[6] == "w"}
        # A women's player = most of her career at women's clubs.
        self.women = {p["id"]: sum(c[0] in womens_clubs for c in p.get("career", [])) * 2 > len(p.get("career", []))
                      for p in self.by_qid.values() if p.get("career")}
        # A link we have no id for: the one player of that name, if only one.
        self.by_name: dict[str, dict[str, dict]] = {}
        for p in self.by_qid.values():
            for nm in {p["name"], *p.get("aliases", [])}:
                self.by_name.setdefault(fold(nm), {})[p["id"]] = p

    def answer(self, title: str, shown: str | None = None, women: bool | None = None) -> str:
        """A Wikipedia link -> 'Name|id', or 'Name|new:1' when we lack them.
        [women]: only the men's or the women's game when matching by name."""
        t = plain(title)
        q = self.qids.get(t)
        p = self.by_qid.get(q) if q else None
        name = re.sub(r"\s*\(.*?\)$", "", t).strip()
        same = sorted(self.by_name.get(fold(name), {}).values(), key=lambda x: -x["fame"]) if not p else []
        if women is not None:
            same = [x for x in same if self.women.get(x["id"], False) == women]
        # One player of that name, or one far better known than the rest
        # (Luis Suárez the Uruguayan, not the 1960 Ballon d'Or winner).
        if len(same) == 1 or (len(same) > 1 and same[0]["fame"] == 5 and same[1]["fame"] <= 3):
            p = same[0]
        if p:
            return f"{p['name']}|{p['id']}"
        return f"{re.sub(r'\s*\(.*?\)$', '', shown or t).strip()}|new:1"

    def feed_answer(self, owner) -> str:
        p = self.match(owner)
        if p:
            return f"{p['name']}|{p['id']}"
        return f"{owner['name']['display']}|new:2"


OUT: list[dict] = []
DROPPED: list[str] = []


def add(cid, prompt, difficulty, eras, source, answers, as_of=None, limit=None):
    answers = list(dict.fromkeys(answers))
    # The same person twice under two spellings ('new' entries): keep one.
    seen, uniq = set(), []
    for a in answers:
        key = a.split("|")[1] if not a.split("|")[1].startswith("new") else fold(a.split("|")[0])
        if key not in seen:
            seen.add(key)
            uniq.append(a)
    if len(uniq) < 5:
        DROPPED.append(f"{cid}: only {len(uniq)} answers")
        return
    if limit and len(uniq) > limit:
        DROPPED.append(f"{cid}: {len(uniq)} answers, over {limit}")
        return
    new = sum(1 for a in uniq if "|new" in a)
    OUT.append({"id": cid, "prompt": prompt, "difficulty": difficulty, "eras": eras, "source": source,
                **({"as_of": as_of} if as_of else {}), "answers": uniq})
    print(f"  {cid}: {len(uniq)} answers ({new} not in the career data)")


# --- Premier League stats feed -------------------------------------------

def feed_lists(d: Data):
    f = d.feed

    def owners(stat, at_least, keep=lambda o: True):
        return [e["owner"] for e in f[stat] if e["value"] >= at_least and keep(e["owner"])]

    pos = lambda o: (o.get("info") or {}).get("position")  # noqa: E731
    src = "Premier League stats (premierleague.com)"
    add("pl-100-goals", "Scored 100+ Premier League goals", 1, ALL_ERAS - 1, src,
        [d.feed_answer(o) for o in owners("goals", 100)], as_of="Nov 2026")
    add("pl-500-apps", "Made 500+ Premier League appearances", 2, ALL_ERAS - 1, src,
        [d.feed_answer(o) for o in owners("appearances", 500)], as_of="Nov 2026")
    add("pl-gk-100-clean-sheets", "Goalkeepers with 100+ Premier League clean sheets", 2, ALL_ERAS - 1, src,
        [d.feed_answer(o) for o in owners("clean_sheet", 100, lambda o: pos(o) == "G")], as_of="Nov 2026")
    add("pl-defenders-20-goals", "Defenders who've scored 20+ Premier League goals", 2, ALL_ERAS - 1, src,
        [d.feed_answer(o) for o in owners("goals", 20, lambda o: pos(o) == "D")], as_of="Nov 2026")
    add("pl-own-goals-4", "Scored 4+ Premier League own goals", 3, ALL_ERAS - 1, src,
        [d.feed_answer(o) for o in owners("own_goals", 4)], as_of="Nov 2026")
    add("pl-red-cards-5", "Sent off 5+ times in the Premier League", 2, ALL_ERAS - 1, src,
        [d.feed_answer(o) for o in owners("red_card", 5)], as_of="Nov 2026")
    add("pl-100-assists", "Made 100+ Premier League assists", 2, ALL_ERAS - 1, src,
        [d.feed_answer(o) for o in owners("goal_assist", 100)], as_of="Nov 2026")
    add("pl-free-kicks-5", "Scored 5+ direct free kicks in the Premier League (since 2006-07)", 3, 4 | 8 | 16, src,
        [d.feed_answer(o) for o in owners("att_freekick_goal", 5)], as_of="Nov 2026")


# --- Record tables on Wikipedia --------------------------------------------

def linked_players(cell: str) -> list[str]:
    return [l for l in LINK.findall(strip_attr(cell)) if not re.search(r"F\.C\.|A\.F\.C\.|football club|national", l)]


def hat_tricks(d: Data):
    page = d.pages.get("List of Premier League hat-tricks", "")
    counts: dict[str, int] = {}
    for heads, cap, headers, rows in tables(page):
        if not any(re.search(r"Player", h, re.I) for h in headers):
            continue
        col = next(i for i, h in enumerate(headers) if re.search(r"Player", h, re.I))
        for r in rows:
            if col < len(r) and (links := linked_players(r[col])):
                counts[links[0]] = counts.get(links[0], 0) + 1
        if counts:
            break
    if not counts:
        DROPPED.append("pl-hat-tricks: table not read")
        return
    add("pl-hat-trick-2", "Scored 2+ Premier League hat-tricks", 2, ALL_ERAS - 1, "Wikipedia: List of Premier League hat-tricks",
        [d.answer(p) for p, n in counts.items() if n >= 2], as_of="Nov 2026")


def golden_boot(d: Data):
    page = d.pages.get("Premier League Golden Boot", "")
    names = []
    for heads, cap, headers, rows in tables(page):
        if any(re.search(r"Season", h) for h in headers) and any(re.search(r"Player", h) for h in headers):
            col = next(i for i, h in enumerate(headers) if re.search(r"Player", h))
            for r in rows:
                if col < len(r):
                    names += linked_players(r[col])
            break
    add("pl-golden-boot-all", "Premier League Golden Boot winners (incl. shared)", 1, ALL_ERAS - 1,
        "Wikipedia: Premier League Golden Boot", [d.answer(p) for p in names], as_of="2025-26 season")


# --- Finals line-ups ------------------------------------------------------

def sides(text: str):
    """Each line-up table in page order: [(title, played)], played = started
    or came on (an unused substitute has no {{subon}})."""
    out, cur = [], None
    for line in text.splitlines():
        if ROW.match(line):
            if cur is None:
                cur = []
            links = [plain(l) for l in FLINK.findall(line) if ":" not in l and not l.startswith("Captain")]
            if links:
                cur.append((links[0], len(cur) < 11 or bool(re.search(r"\{\{subon", line, re.I)),
                            line.split("||")[0].strip("| ")))
        elif cur is not None and (re.search(r"Manager|Coach|Head coach", line, re.I) or line.startswith("|}")):
            out.append(cur)
            cur = None
    return out


def managers(text: str) -> list[str]:
    """The manager under each line-up: the first link on the "Manager:" line
    or the lines just after it."""
    out = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.search(r"'''\s*(?:Manager|Head coach|Coach)\s*:?\s*'''", line):
            for nxt in lines[i:i + 3]:
                links = [l for l in FLINK.findall(nxt) if ":" not in l]
                if links:
                    out.append(plain(links[0]))
                    break
    return out


def goals(text: str) -> list[str]:
    out = []
    for m in re.finditer(r"\|\s*goals[12]\s*=(.*?)(?=\|\s*(?:goals[12]|stadium|location|attendance|referee)\s*=)", text, re.S):
        out += [plain(l) for l in FLINK.findall(m.group(1)) if ":" not in l and "Stadium" not in l and "stadium" not in l]
    return out


def finals(d: Data):
    ucl = [(y, f"{y} UEFA Champions League final") for y in range(1993, 2027)]
    uel = [(y, f"{y} UEFA Europa League final") for y in range(2010, 2027)] + \
          [(y, f"{y} UEFA Cup final") for y in range(1998, 2009)]
    wc = [(y, f"{y} FIFA World Cup final") for y in range(1930, 2023, 4)]
    english = {"Manchester United F.C.", "Liverpool F.C.", "Chelsea F.C.", "Arsenal F.C.", "Tottenham Hotspur F.C.",
               "Manchester City F.C."}
    scorers, keepers, coaches, eng_players, uel_scorers = [], [], [], [], []
    clubs_of: dict[str, set[str]] = {}
    ucl_players, wc_players = set(), set()
    missing = []
    for y, t in ucl:
        text = d.pages.get(t)
        if not text:
            missing.append(t)
            continue
        scorers += goals(text)
        coaches += managers(text)
        bs, ss = boxes(text), sides(text)
        if len(ss) != 2 or not bs:
            missing.append(f"{t} (line-ups)")
            continue
        for team, side in zip((bs[0]["team1"], bs[0]["team2"]), ss):
            for name, played, pos in side:
                if not played:
                    continue
                ucl_players.add(name)
                clubs_of.setdefault(name, set()).add(team)
                if "GK" in pos:
                    keepers.append(name)
                if team in english:
                    eng_players.append(name)
    for y, t in uel:
        if text := d.pages.get(t):
            uel_scorers += goals(text)
    for y, t in wc:
        if text := d.pages.get(t):
            for side in sides(text):
                wc_players |= {n for n, played, _ in side if played}
    if missing:
        print("  finals missing:", missing)
    add("ucl-final-scorers", "Scored in a Champions League final (since 1993)", 1, era_bits(1993, 2026),
        "Wikipedia: each final's article", [d.answer(p) for p in scorers])
    add("ucl-final-keepers", "Goalkeepers who've played in a Champions League final (since 1993)", 2, era_bits(1993, 2026),
        "Wikipedia: each final's line-ups", [d.answer(p) for p in keepers])
    add("ucl-final-managers", "Managers who've taken a team to a Champions League final (since 1993)", 2, era_bits(1993, 2026),
        "Wikipedia: each final's line-ups", [d.answer(p) for p in coaches])
    add("ucl-final-english-club", "Played in a Champions League final for an English club", 1, era_bits(1999, 2026),
        "Wikipedia: each final's line-ups (started or came on)", [d.answer(p) for p in eng_players])
    add("ucl-final-two-clubs", "Played in Champions League finals for two different clubs", 2, era_bits(1993, 2026),
        "Wikipedia: each final's line-ups (started or came on)",
        [d.answer(p) for p, cs in clubs_of.items() if len(cs) >= 2])
    add("uel-final-scorers", "Scored in a UEFA Cup or Europa League final (since 1998)", 2, era_bits(1998, 2026),
        "Wikipedia: each final's article", [d.answer(p) for p in uel_scorers])
    add("ucl-and-wc-final", "Played in both a Champions League final and a World Cup final", 2, era_bits(1993, 2026),
        "Wikipedia: final line-ups (started or came on)", [d.answer(p) for p in sorted(ucl_players & wc_players)])
    wc_scorers = []
    for y, t in wc:
        if text := d.pages.get(t):
            wc_scorers += goals(text)
    add("wc-final-scorers-all", "Scored in a World Cup final", 2, ALL_ERAS,
        "Wikipedia: each final's article", [d.answer(p) for p in wc_scorers])


# Who played (started or came on) for one side in one final.
FINAL_SIDES = [
    ("eng-euro-2020-final", "England players in the Euro 2020 final (started or came on)", "UEFA Euro 2020 final", "ENG", 1, 2021),
    ("eng-euro-2024-final", "England players in the Euro 2024 final (started or came on)", "UEFA Euro 2024 final", "ENG", 1, 2024),
    ("esp-euro-2024-final", "Spain players in the Euro 2024 final (started or came on)", "UEFA Euro 2024 final", "ESP", 2, 2024),
    ("ars-2006-ucl-final", "Arsenal players in the 2006 Champions League final (started or came on)",
     "2006 UEFA Champions League final", "Arsenal F.C.", 2, 2006),
    ("tot-2019-ucl-final", "Tottenham players in the 2019 Champions League final (started or came on)",
     "2019 UEFA Champions League final", "Tottenham Hotspur F.C.", 2, 2019),
    ("che-2021-ucl-final", "Chelsea players in the 2021 Champions League final (started or came on)",
     "2021 UEFA Champions League final", "Chelsea F.C.", 2, 2021),
    ("che-2008-ucl-final", "Chelsea players in the 2008 Champions League final (started or came on)",
     "2008 UEFA Champions League final", "Chelsea F.C.", 2, 2008),
    ("mun-2008-ucl-final", "Man United players in the 2008 Champions League final (started or came on)",
     "2008 UEFA Champions League final", "Manchester United F.C.", 2, 2008),
]


def final_sides(d: Data):
    for cid, prompt, title, team, level, year in FINAL_SIDES:
        text = d.pages.get(title, "")
        bs, ss = boxes(text), sides(text)
        if not bs or len(ss) != 2:
            DROPPED.append(f"{cid}: line-ups not read")
            continue
        teams = [bs[0]["team1"], bs[0]["team2"]]
        if team not in teams:
            DROPPED.append(f"{cid}: {team} not in {teams}")
            continue
        side = ss[teams.index(team)]
        add(cid, prompt, level, era_bits(year, year), f"Wikipedia: {title}", [d.answer(n) for n, played, _ in side if played])
    euro = []
    for y in range(1996, 2025, 4):
        euro += goals(d.pages.get(f"UEFA Euro {y} final", ""))
    add("euro-final-scorers-1996", "Scored in a Euros final (since 1996)", 2, era_bits(1996, 2024),
        "Wikipedia: each final's article", [d.answer(n) for n in euro])
    fa = []
    for y in range(2017, 2027):
        fa += goals(d.pages.get(f"{y} FA Cup final", ""))
    add("fa-cup-final-scorers-2017", "Scored in an FA Cup final (since 2017)", 2, era_bits(2017, 2026),
        "Wikipedia: each final's article", [d.answer(n) for n in fa])


# --- Tournament squads, red cards, shoot-outs, own goals -------------------

def squad(d: Data, title: str, nation: str) -> list[str]:
    text = d.pages.get(title, "")
    i = re.search(rf"^===\s*{re.escape(nation)}\s*===", text, re.M)
    if not i:
        return []
    chunk = text[i.end():]
    if (j := re.search(r"^===?[^=]", chunk, re.M)):
        chunk = chunk[:j.start()]
    out = []
    for m in re.finditer(r"\|\s*name\s*=\s*\[\[([^\]|]+)(?:\|([^\]]+))?\]\]", chunk):
        out.append(d.answer(m.group(1), m.group(2)))
    return out


SQUADS = [
    ("eng-squad-wc-2006", "England's 2006 World Cup squad", "2006 FIFA World Cup squads", "England", 1, 2006),
    ("eng-squad-wc-2010", "England's 2010 World Cup squad", "2010 FIFA World Cup squads", "England", 1, 2010),
    ("eng-squad-wc-2002", "England's 2002 World Cup squad", "2002 FIFA World Cup squads", "England", 1, 2002),
    ("eng-squad-wc-1998", "England's 1998 World Cup squad", "1998 FIFA World Cup squads", "England", 2, 1998),
    ("eng-squad-wc-2014", "England's 2014 World Cup squad", "2014 FIFA World Cup squads", "England", 2, 2014),
    ("eng-squad-wc-2018", "England's 2018 World Cup squad", "2018 FIFA World Cup squads", "England", 1, 2018),
    ("eng-squad-euro-2004", "England's Euro 2004 squad", "UEFA Euro 2004 squads", "England", 1, 2004),
    ("eng-squad-euro-1996", "England's Euro 96 squad", "UEFA Euro 1996 squads", "England", 2, 1996),
    ("eng-squad-euro-2012", "England's Euro 2012 squad", "UEFA Euro 2012 squads", "England", 2, 2012),
    ("bra-squad-wc-2002", "Brazil's 2002 World Cup squad", "2002 FIFA World Cup squads", "Brazil", 2, 2002),
    ("fra-squad-wc-1998", "France's 1998 World Cup squad", "1998 FIFA World Cup squads", "France", 2, 1998),
    ("fra-squad-wc-2018", "France's 2018 World Cup squad", "2018 FIFA World Cup squads", "France", 1, 2018),
    ("ita-squad-wc-2006", "Italy's 2006 World Cup squad", "2006 FIFA World Cup squads", "Italy", 2, 2006),
    ("esp-squad-wc-2010", "Spain's 2010 World Cup squad", "2010 FIFA World Cup squads", "Spain", 2, 2010),
    ("ger-squad-wc-2014", "Germany's 2014 World Cup squad", "2014 FIFA World Cup squads", "Germany", 2, 2014),
    ("arg-squad-wc-2022", "Argentina's 2022 World Cup squad", "2022 FIFA World Cup squads", "Argentina", 2, 2022),
    ("ned-squad-wc-2010", "Netherlands' 2010 World Cup squad", "2010 FIFA World Cup squads", "Netherlands", 3, 2010),
    ("por-squad-euro-2016", "Portugal's Euro 2016 squad", "UEFA Euro 2016 squads", "Portugal", 3, 2016),
    ("wal-squad-euro-2016", "Wales' Euro 2016 squad", "UEFA Euro 2016 squads", "Wales", 2, 2016),
    ("sco-squad-euro-2020", "Scotland's Euro 2020 squad", "UEFA Euro 2020 squads", "Scotland", 2, 2021),
]


def squads(d: Data):
    for cid, prompt, title, nation, level, year in SQUADS:
        names = squad(d, title, nation)
        if not 22 <= len(names) <= 26:
            DROPPED.append(f"{cid}: {len(names)} in the squad")
            continue
        add(cid, prompt, level, era_bits(year, year), f"Wikipedia: {title}", names)


def table_col(text: str, want: str):
    """Rows of the first sortable table with a header matching want, and that column."""
    for heads, cap, headers, rows in tables(text):
        for i, h in enumerate(headers):
            if re.search(want, h, re.I):
                yield rows, i
                break


def wc_tables(d: Data):
    # Red cards since 1990: the player column, rows in a year from 1990.
    reds = []
    for rows, col in table_col(d.pages.get("List of FIFA World Cup red cards", ""), r"^Player$"):
        for r in rows:
            year = re.search(r"\[\[(\d{4}) FIFA World Cup", " ".join(r))
            if year and int(year.group(1)) >= 1998 and col < len(r):
                reds += linked_players(r[col])[:1]
        break
    add("wc-red-cards-1998", "Sent off at a World Cup (since 1998)", 3, era_bits(1998, 2022),
        "Wikipedia: List of FIFA World Cup red cards", [d.answer(p) for p in reds])
    # Shoot-out misses: takers marked {{penmiss}}.
    misses = []
    page = d.pages.get("List of FIFA World Cup penalty shoot-outs", "")
    for m in re.finditer(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]\s*\{\{penmiss", page):
        misses.append(m.group(1))
    add("wc-shootout-misses", "Missed in a World Cup penalty shoot-out", 3, era_bits(1982, 2022),
        "Wikipedia: List of FIFA World Cup penalty shoot-outs", [d.answer(p) for p in misses])
    ogs = []
    for rows, col in table_col(d.pages.get("List of FIFA World Cup own goals", ""), r"^Player$"):
        for r in rows:
            year = re.search(r"\[\[(\d{4}) FIFA World Cup", " ".join(r))
            if year and int(year.group(1)) >= 1990 and col < len(r):
                ogs += linked_players(r[col])[:1]
        break
    add("wc-own-goals-1990", "Scored an own goal at a World Cup (since 1990)", 3, era_bits(1990, 2022),
        "Wikipedia: List of FIFA World Cup own goals", [d.answer(p) for p in ogs])


def euro_scorers(d: Data):
    for y, level in ((2016, 2), (2020, 2), (2024, 2)):
        page = d.pages.get(f"UEFA Euro {y} statistics", "")
        start = page.find("{{Goalscorers")
        if start < 0:
            DROPPED.append(f"euro-{y}-scorers: no goalscorers template")
            continue
        end = page.find("\n}}", start)
        block = re.split(r"\|\s*own goals?\s*=", page[start:end], flags=re.I)[0]
        names = [m.group(1) for m in re.finditer(r"^\*\s*\{\{fbicon\|[^}]*\}\}\s*\[\[([^\]|]+)", block, re.M)]
        played = y if y != 2020 else 2021
        add(f"euro-{y}-scorers", f"Scored at Euro {y}" + (" (played in 2021)" if y == 2020 else ""), level,
            era_bits(played, played), f"Wikipedia: UEFA Euro {y} statistics", [d.answer(p) for p in names])


# --- Careers and rosters --------------------------------------------------

BIG_SIX = {"Q9617", "Q9616", "Q1130849", "Q18656", "Q50602", "Q18741"}
LONDON_PL = {"Q9617", "Q9616", "Q18741", "Q18747", "Q19467", "Q18708", "Q19571", "Q18723", "Q19462", "Q19482"}


def careers(d: Data):
    def clubs_of(p):
        return {c[0] for c in p.get("career", [])}
    big = [p for p in d.by_qid.values() if len(clubs_of(p) & BIG_SIX) >= 3]
    add("three-big-six", "Played for three of the Big Six (Arsenal, Chelsea, Liverpool, Man Utd, Man City, Spurs)",
        2, ALL_ERAS, "Career data (Wikidata)", [f"{p['name']}|{p['id']}" for p in big])
    names = {q: d.club_name.get(q) for q in LONDON_PL}
    if any(v is None for v in names.values()):
        DROPPED.append(f"three-london: unknown club ids {[q for q, v in names.items() if v is None]}")
        return
    ldn = [p for p in d.by_qid.values() if len(clubs_of(p) & LONDON_PL) >= 3]
    add("three-london-pl", "Played for three or more London clubs that have been in the Premier League",
        2, ALL_ERAS, "Career data (Wikidata)", [f"{p['name']}|{p['id']}" for p in ldn])


# A club's Premier League years: everyone with a spell there that overlaps
# them (joined before the last season ended, left after the first began).
CLUB_ERAS = [
    ("pl-era-portsmouth", "Q19604", "Portsmouth", 2003, 2010, "in their Premier League years (2003–2010)", 2),
    ("pl-era-wigan", "Q18750", "Wigan Athletic", 2005, 2013, "in their Premier League years (2005–2013)", 2),
    ("pl-era-stoke", "Q18736", "Stoke City", 2008, 2018, "in their Premier League years (2008–2018)", 2),
    ("pl-era-swansea", "Q18659", "Swansea City", 2011, 2018, "in their Premier League years (2011–2018)", 2),
    ("pl-era-blackpool", "Q19449", "Blackpool", 2010, 2011, "in their one Premier League season (2010–11)", 3),
    ("pl-era-bradford", "Q48879", "Bradford City", 1999, 2001, "in their Premier League years (1999–2001)", 3),
    ("pl-era-wimbledon", "Q19482", "Wimbledon", 1992, 2000, "in their Premier League years (1992–2000)", 2),
    ("pl-era-bolton", "Q19451", "Bolton Wanderers", 2001, 2012, "in their 2001–2012 Premier League spell", 2),
    ("pl-era-reading", "Q18729", "Reading", 2006, 2008, "in their first Premier League spell (2006–2008)", 3),
    ("pl-era-hull", "Q19477", "Hull City", 2008, 2010, "in their first Premier League spell (2008–2010)", 3),
    ("pl-era-qpr", "Q18723", "Queens Park Rangers", 2011, 2013, "in their 2011–2013 Premier League spell", 3),
    ("pl-era-middlesbrough", "Q18661", "Middlesbrough", 1998, 2009, "in their 1998–2009 Premier League spell", 2),
    ("pl-era-charlton", "Q19462", "Charlton Athletic", 2000, 2007, "in their 2000–2007 Premier League spell", 3),
    ("pl-era-blackburn", "Q19446", "Blackburn Rovers", 2001, 2012, "in their 2001–2012 Premier League spell", 2),
    ("pl-era-leeds", "Q1128631", "Leeds United", 1992, 2004, "in their Premier League years (1992–2004)", 2),
]


def club_eras(d: Data):
    for cid, club, name, first, last, when, level in CLUB_ERAS:
        if d.club_name.get(club) is None:
            DROPPED.append(f"{cid}: unknown club {club}")
            continue
        ids = []
        for p in d.by_qid.values():
            for c, start, end, *_ in p.get("career", []):
                if c == club and start is not None and start < last and (end or 2026) > first:
                    ids.append(f"{p['name']}|{p['id']}")
                    break
        add(cid, f"Played for {name} {when}", level, era_bits(first, last - 1), "Career data (Wikidata)", ids)


def sortname_title(cell: str) -> str | None:
    """{{sortname|First|Last|dab=...}} (or a target as the third argument) ->
    the article title; else the first link."""
    m = re.search(r"\{\{sortname\|([^|}]*)\|([^|}]*)((?:\|[^}]*)?)\}\}", cell)
    if not m:
        links = LINK.findall(cell)
        return links[0] if links else None
    title = f"{m.group(1)} {m.group(2)}".strip()
    args = m.group(3).split("|")[1:]
    positional = [a.strip() for a in args if "=" not in a]
    for arg in args:
        if arg.startswith("dab="):
            title += f" ({arg[4:]})"
    # The third positional argument is the article (blank = the name); the
    # fourth is only a sort key.
    if positional and positional[0]:
        title = positional[0]
    return title


def cl_hat_tricks(d: Data):
    page = d.pages.get("List of UEFA Champions League hat-tricks", "")
    names = []
    for heads, cap, headers, rows in tables(page):
        if cap.startswith("Hat-tricks scored in the UEFA Champions League"):
            names = [t for r in rows if (t := sortname_title(r[0]))]
            break
    add("ucl-hat-tricks", "Scored a Champions League hat-trick (group stage on, since 1992)", 2, era_bits(1992, 2026),
        "Wikipedia: List of UEFA Champions League hat-tricks", [d.answer(t) for t in names], as_of="Nov 2026")


def rosters(d: Data):
    """Pairs of the grid's rosters (built by build_db.py from careers and
    managers' spells): played under both, or alongside both."""
    db = json.loads((HERE.parent / "assets" / "db" / "football.json").read_text(encoding="utf-8"))
    names = {p["id"]: p["name"] for p in db["players"]}
    roster: dict[str, set[str]] = {}
    for cat, club, ids, eras in db["category_rosters"]:
        roster.setdefault(cat, set()).update(ids)
    for cid, prompt, a, b, level in [
        ("under-mourinho-and-ancelotti", "Played under both José Mourinho and Carlo Ancelotti (club football)",
         "mgr:jose-mourinho", "mgr:carlo-ancelotti", 2),
        ("teammate-messi-and-ronaldo", "Club teammate of both Lionel Messi and Cristiano Ronaldo",
         "with:lionel-messi", "with:cristiano-ronaldo", 2),
        ("under-klopp-and-guardiola", "Played under both Jürgen Klopp and Pep Guardiola (club football)",
         "mgr:jurgen-klopp", "mgr:pep-guardiola", 3),
    ]:
        both = roster.get(a, set()) & roster.get(b, set())
        add(cid, prompt, level, ALL_ERAS, "Career data (Wikidata) and managers' spells",
            [f"{names[i]}|{i}" for i in sorted(both) if i in names])


def pl_managers(d: Data):
    """Permanent Premier League jobs (caretakers left out) per manager."""
    page = d.pages.get("List of Premier League managers", "")
    jobs: dict[str, set[str]] = {}
    for heads, cap, headers, rows in tables(page):
        if headers[:3] != ["Name", "Nationality}}", "Club"]:
            continue
        for r in rows:
            if "double dagger" in r[0]:
                continue
            title = sortname_title(r[0])
            club = LINK.findall(r[2])
            if not title or not club:
                continue
            jobs.setdefault(title, set()).add(club[0])
        break
    if not jobs:
        DROPPED.append("pl-managers-3-clubs: table not read")
        return
    add("pl-managers-3-clubs", "Managed three or more Premier League clubs (permanent jobs)", 2, ALL_ERAS - 1,
        "Wikipedia: List of Premier League managers", [d.answer(t) for t, cs in jobs.items() if len(cs) >= 3],
        as_of="Nov 2026")


# Football 501 by country: caps + goals for EVERY capped player, 1 cap up.
# Wikipedia's lists stop at a cut-off (Portugal 25+ caps), so the rest come
# from each player's infobox (caps_fetch.py -> raw/national_caps.json.gz);
# a list's own numbers win where it has the player.
NATIONS = [
    ("eng", "England", "England caps + goals", 1, False),
    ("sco", "Scotland", "Scotland caps + goals", 2, False),
    ("wal", "Wales", "Wales caps + goals", 2, False),
    ("nir", "Northern Ireland", "Northern Ireland caps + goals", 3, False),
    ("irl", "Republic of Ireland", "Republic of Ireland caps + goals", 2, False),
    ("bra", "Brazil", "Brazil caps + goals", 2, False),
    ("arg", "Argentina", "Argentina caps + goals", 3, False),
    ("ger", "Germany", "Germany caps + goals (West Germany counts)", 2, False),
    ("ita", "Italy", "Italy caps + goals", 3, False),
    ("por", "Portugal", "Portugal caps + goals", 2, False),
    ("fra", "France", "France caps + goals", 2, False),
    ("esp", "Spain", "Spain caps + goals", 2, False),
    ("ned", "Netherlands", "Netherlands caps + goals", 2, False),
    ("eng-w", "England women's", "Lionesses caps + goals", 2, True),
]
NATIONAL_OUT: list[dict] = []


def nation_rows(page: str) -> list[tuple[str, int, int]]:
    """(article, caps, goals) from the list's main table."""
    def num(cell):
        c = re.sub(r"<ref.*", "", strip_attr(cell))
        c = re.sub(r"\{\{[^}]*\}\}", "", c)
        m = re.search(r"\d+", c.replace(",", ""))
        return int(m.group()) if m else None
    for heads, cap, headers, rows in tables(page):
        if len(rows) < 50:
            continue
        cols = [re.sub(r"\W", "", h).lower() for h in headers]
        try:
            pi = next(i for i, c in enumerate(cols) if c.startswith("player") or c == "name")
            ci = next(i for i, c in enumerate(cols) if c.startswith("caps"))
            gi = next(i for i, c in enumerate(cols) if c.startswith("goals"))
        except StopIteration:
            continue
        out = []
        for r in rows:
            if max(pi, ci, gi) >= len(r):
                continue
            title, caps, goals = sortname_title(r[pi]), num(r[ci]), num(r[gi])
            if title and caps is not None and goals is not None:
                out.append((title, caps, goals))
        return out
    return []


def nations(d: Data):
    caps = json.load(gzip.open(RAW / "national_caps.json.gz", "rt", encoding="utf-8"))
    d.qids.update(caps.get("qids", {}))
    for code, country, prompt, level, women in NATIONS:
        page = d.pages.get(f"List of {country} international footballers", "")
        listed = {plain(t): (c, g) for t, c, g in nation_rows(page)}
        # Everyone in the infoboxes; the list's numbers where it has him.
        rows = {**{plain(t): tuple(v) for t, v in caps["teams"].get(country, {}).items()}, **listed}
        low = sum(1 for c, _ in rows.values() if c < 10)
        # Every player, or it's unplayable: with nobody under 25, you can't
        # finish from 14 or less. So no list without its 1-cap players.
        if len(rows) < 100 or low < 20:
            DROPPED.append(f"501 {country}: {len(rows)} players, {low} under 10 caps")
            continue
        values = {}
        for title, (c, g) in rows.items():
            values[d.answer(title, women=women)] = [c, g]
        as_of = re.search(r"correct as of:?'*\s*([^,\n<]+)", page)
        NATIONAL_OUT.append({"id": f"501:{code}", "prompt": prompt, "difficulty": level, "women": women,
                             "source": f"Wikipedia: List of {country} international footballers",
                             **({"as_of": as_of.group(1).strip()} if as_of else {}), "values": values})
        new = sum(1 for a in values if "|new" in a)
        print(f"  501 {country}: {len(values)} players ({new} not in the career data)")


def main() -> int:
    d = Data()
    for step in (feed_lists, hat_tricks, golden_boot, finals, squads, wc_tables, euro_scorers, careers, club_eras, pl_managers, cl_hat_tricks, rosters, final_sides, nations):
        print(step.__name__)
        step(d)
    (SEED / "checkouts_generated.json").write_text(json.dumps({
        "_about": "GENERATED by radar_build.py: Football 501 by country (caps + goals) from Wikipedia's lists of "
                  "internationals. Keys are 'Name|player-id' or 'Name|new:1'.",
        "categories": NATIONAL_OUT}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    (SEED / "bidding_generated.json").write_text(json.dumps({
        "_about": "GENERATED by radar_build.py from the raw Wikipedia / Premier League data and the career data. "
                  "Do not edit by hand: fix the source or the builder.",
        "categories": OUT}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(OUT)} lists written; {len(DROPPED)} left out:")
    for x in DROPPED:
        print("  -", x)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
