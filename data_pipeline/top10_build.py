"""Builds the Top 10 bank (assets/db/top10.json) from Wikipedia record tables
(raw/lists_wikitext.json.gz, saved by lists_fetch.py in Actions).

Each list below names an article, which of its tables to read, the question
and a difficulty (1 = everyone knows it, 3 = for the anoraks). A list is
only used if its first ten rows are all players we know: one we can't match
and it's dropped, never shifted up. Figures are kept only when the ten run in
order (so we never show a goals column next to an appearances ranking);
otherwise the list shows ranks alone.
"""
from __future__ import annotations

import datetime as dt
import gzip
import json
import pathlib
import re
import unicodedata

from top10_tables import LINK, load, strip_attr, tables

HERE = pathlib.Path(__file__).parent
OUT = HERE.parent / "assets" / "db" / "top10.json"

PL = "Premier League records and statistics"
LISTS = [
    # (id, article, table index, question, level, unit)
    ("pl-goals", PL, 1, "Premier League all-time top scorers", 1, "goals"),
    ("pl-apps", PL, 0, "Most Premier League appearances", 2, "apps"),
    ("pl-assists", PL, 4, "Most Premier League assists", 2, "assists"),
    ("pl-clean-sheets", PL, 5, "Most Premier League clean sheets", 2, "clean sheets"),
    ("pl-penalties", PL, 2, "Most Premier League penalties scored", 3, "pens"),
    ("ucl-goals", "List of UEFA Champions League top scorers", 0, "Champions League all-time top scorers", 1, "goals"),
    ("eng-caps", "England national football team records and statistics", 0, "Most England caps", 1, "caps"),
    ("eng-goals", "England national football team records and statistics", 4, "England's all-time top scorers", 1, "goals"),
    ("eng-clean-sheets", "England national football team records and statistics", 8, "Most England clean sheets", 3, "clean sheets"),
    ("intl-caps", "List of men's footballers with 100 or more international caps", 1, "Most international caps (men)", 3, "caps"),
    ("mufc-apps", "Manchester United F.C. records and statistics", 0, "Most appearances for Manchester United", 2, ""),
    ("mufc-goals", "Manchester United F.C. records and statistics", 1, "Manchester United's all-time top scorers", 2, ""),
    ("mufc-assists", "Manchester United F.C. records and statistics", 2, "Most assists for Manchester United", 3, ""),
    ("mufc-clean-sheets", "Manchester United F.C. records and statistics", 3, "Most clean sheets for Manchester United", 3, ""),
    ("cfc-apps", "List of Chelsea F.C. records and statistics", 1, "Most appearances for Chelsea", 2, ""),
    ("cfc-signings", "List of Chelsea F.C. records and statistics", 3, "Chelsea's most expensive signings", 3, ""),
    ("thfc-sales", "List of Tottenham Hotspur F.C. records and statistics", 9, "Tottenham's biggest sales", 2, ""),
    ("mcfc-assists", "List of Manchester City F.C. records and statistics", 19, "Most assists for Manchester City", 2, "assists"),
    ("mcfc-signings", "List of Manchester City F.C. records and statistics", 24, "Manchester City's most expensive signings", 3, ""),
    ("efc-sales", "List of Everton F.C. records and statistics", 12, "Everton's biggest sales", 2, ""),
    ("nufc-sales", "List of Newcastle United F.C. records and statistics", 1, "Newcastle's biggest sales", 3, ""),
    ("celtic-sales", "List of Celtic F.C. records and statistics", 3, "Celtic's biggest sales", 3, ""),
    ("rmcf-apps", "List of Real Madrid CF records and statistics", 0, "Most appearances for Real Madrid", 3, ""),
    ("rmcf-goals", "List of Real Madrid CF records and statistics", 1, "Real Madrid's all-time top scorers", 3, ""),
    ("rmcf-assists", "List of Real Madrid CF records and statistics", 7, "Most assists for Real Madrid", 3, "assists"),
    ("fcb-goals", "List of FC Barcelona records and statistics", 1, "Barcelona's all-time top scorers", 3, ""),
    ("juve-apps", "List of Juventus FC records and statistics", 1, "Most appearances for Juventus", 3, "apps"),
    ("juve-goals", "List of Juventus FC records and statistics", 2, "Juventus's all-time top scorers", 3, ""),
    ("fcbayern-apps", "List of FC Bayern Munich records and statistics", 5, "Most appearances for Bayern Munich", 3, ""),
    ("laliga-goals", "List of La Liga top scorers", 0, "La Liga all-time top scorers", 2, "goals"),
    ("bundesliga-goals", "List of Bundesliga top scorers", 0, "Bundesliga all-time top scorers", 3, "goals"),
    ("pl-hat-tricks", "List of Premier League hat-tricks", 2, "Most Premier League hat-tricks", 2, "hat-tricks"),
    ("pl-free-kicks", PL, 3, "Most Premier League free-kick goals", 2, "free kicks"),
    ("wc-goals", "List of FIFA World Cup top goalscorers", 2, "World Cup all-time top scorers", 2, "goals"),
    ("eng-captains", "List of England national football team captains", 3, "Most games as England captain", 2, "as captain"),
    ("ucl-assists", "UEFA Champions League records and statistics", 6, "Most Champions League assists", 2, "assists"),
    ("ucl-managers", "UEFA Champions League records and statistics", 9, "Most Champions League games as a manager", 3, "games"),
    ("pl-managers", "List of Premier League managers", 5, "Most Premier League games as a manager", 2, "games"),
    ("pl-titles", "List of Premier League winning players", 0, "Most Premier League titles as a player", 2, "titles"),
    ("pl-potm", "Premier League Player of the Month", 1, "Most Premier League Player of the Month awards", 2, "awards"),
    ("sco-caps", "Scotland national football team records and statistics", 0, "Most Scotland caps", 2, "caps"),
    ("sco-goals", "Scotland national football team records and statistics", 1, "Scotland's all-time top scorers", 2, "goals"),
    ("wal-caps", "Wales national football team records and statistics", 0, "Most Wales caps", 2, "caps"),
    ("wal-goals", "Wales national football team records and statistics", 1, "Wales's all-time top scorers", 2, "goals"),
    ("nir-caps", "Northern Ireland national football team records and statistics", 0, "Most Northern Ireland caps", 3, "caps"),
    ("nir-goals", "Northern Ireland national football team records and statistics", 1, "Northern Ireland's all-time top scorers", 3, ""),
    ("man-derby-goals", "Manchester derby", 1, "Most goals in the Manchester derby", 3, ""),
    ("nld-goals", "North London derby", 2, "Most goals in the North London derby (Premier League era)", 2, "goals"),
    ("mersey-goals", "Merseyside derby", 2, "Most goals in the Merseyside derby", 3, ""),
    ("clasico-goals", "El Clásico", 13, "Most goals in El Clásico", 2, "goals"),
    ("milan-derby-goals", "Derby della Madonnina", 2, "Most goals in the Milan derby", 3, "goals"),
    ("world-transfers", "List of most expensive association football transfers", 0, "The 10 most expensive transfers ever (a player's biggest)", 1, "\u20acm"),
]
# Skip rows naming anyone in another table on the page (the captains
# ranking mixes in the women's team, listed in its own chronology).
EXCLUDE = {"eng-captains": 1}

# Titles whose fetched qid is wrong (a disambiguation page).
TITLE_QID = {"Luis Suárez": "Q26517"}

LISTS += [(f"ballon-dor-{y}", f"{y} Ballon d'Or", 0, f"{y} Ballon d'Or: the top 10", 1 if y >= 2015 else 2 if y >= 2000 else 3, "")
          for y in range(1990, 2026) if y != 2020]

SCORERS = r"top (?:goal)?scorers|goalscorers"


def _season(y: int) -> str:
    return f"{y}\u2013{str(y + 1)[2:]}"


# Finished seasons, each table found by its heading. A season's list doesn't
# move, so it carries no "as of".
SEASONS = [
    (f"pl-{y}", f"{_season(y)} {'FA ' if y < 2007 else ''}Premier League", SCORERS,
     f"Top scorers in the {_season(y)} Premier League", 2 if y >= 2005 else 3, "goals")
    for y in range(1992, 2026)
] + [
    (f"ucl-{y}", f"{_season(y)} UEFA Champions League", SCORERS,
     f"Top scorers in the {_season(y)} Champions League", 3, "goals")
    for y in range(1992, 2026)
]


def num(s: str) -> int | None:
    s = re.sub(r"<ref.*|<!--.*|(?<=\d)\s*\{\{efn.*", "", s, flags=re.S).strip().replace(",", "")
    s = re.sub(r"'''|''", "", s).strip()
    if re.fullmatch(r"\d+", s):
        return int(s)
    return float(s) if re.fullmatch(r"\d+\.\d+", s) else None


# Lists whose figure isn't the first number after the name (the column).
# Lists where a player can appear twice (a transfer each): keep the first.
DEDUPE = {"world-transfers"}

FIG_COL = {"wal-goals": 4, "clasico-goals": -1, "world-transfers": 5}


def build_list(rows, qids, by_qid, unit: str, col: int | None = None, dedupe: bool = False):
    """(entries, problem): the first ten rows that link anything, all matched.
    Players level with 10th beyond the ten (Beattie, Keane and Pirès all on
    14) share the 10th slot: naming any of them fills it."""
    picked = []
    extra = []  # rows after the tenth: (player or None, figure)
    for cells in rows:
        cells = [strip_attr(c) for c in cells]
        links = [(k, l.strip().replace("_", " ")) for k, c in enumerate(cells) for l in LINK.findall(c) if ":" not in l]
        if not links:
            continue
        if len(picked) >= 10:
            k0 = links[0][0]
            fig = (num(cells[col]) if -len(cells) <= col < len(cells) else None) if col is not None else \
                next((n for c in cells[k0 + 1:] if (n := num(c)) is not None), None)
            who = next((by_qid[qids[l]] for _, l in links if qids.get(l) in by_qid), None)
            extra.append((who, fig))
            if fig is None or fig != picked[-1][1]:
                break
            continue
        hit = next(((k, by_qid[qids[l]]) for k, l in links if qids.get(l) in by_qid), None)
        if hit is None:
            return None, f"row {len(picked) + 1} names nobody we know: {links[0][1]}"
        k, p = hit
        if any(e[0]["id"] == p["id"] for e in picked):
            if dedupe:
                continue
            return None, f"{p['name']} twice (a by-season table?)"
        figure = (num(cells[col]) if -len(cells) <= col < len(cells) else None) if col is not None else \
            next((n for c in cells[k + 1:] if (n := num(c)) is not None), None)
        picked.append((p, figure))
    if len(picked) < 10:
        return None, f"only {len(picked)} rows"
    figs = [f for _, f in picked]
    ordered = all(f is not None for f in figs) and all(a >= b for a, b in zip(figs, figs[1:]))
    tied = [w for w, f in extra if ordered and f == figs[-1]]
    if any(w is None for w in tied):
        return None, f"someone level at 10th we don't know"
    entries, rank = [], 0
    for i, (p, f) in enumerate(picked):
        # Level on the figure: same place ("=4").
        rank = rank if ordered and i and f == figs[i - 1] else i + 1
        shown = (f"\u20ac{f:g}m" if unit == "\u20acm" else f"{f:,} {unit}".strip()) if ordered and unit else ""
        alts = [[w["id"], w["name"]] for w in tied] if i == 9 else []
        entries.append([rank, p["id"], p["name"], shown, alts] if alts else
                       [rank, p["id"], p["name"], shown] if shown else [rank, p["id"], p["name"]])
    return entries, None


def season_record(pages, qids, by_qid, title):
    """Most goals in one season of a competition, each player's best once
    ("36 (2022\u201323)"), from every season's top-scorer table (a record
    season is always in its own season's top ten). title(y) -> article."""
    best: dict[str, tuple[int, int, dict]] = {}
    for y in range(1992, 2026):
        page = pages.get(title(y))
        if not page:
            return None, f"no page for {_season(y)}"
        tabs = list(tables(page))
        idx = next((n for n, (h, c, _, _) in enumerate(tabs) if re.search(SCORERS, f"{h} {c}", re.I)), None)
        if idx is None:
            return None, f"no scorers table for {_season(y)}"
        for cells in tabs[idx][3]:
            cells = [strip_attr(c) for c in cells]
            links = [(k, l.strip()) for k, c in enumerate(cells) for l in LINK.findall(c) if ":" not in l]
            if not links:
                continue
            k, l = links[0]
            goals = next((n for c in cells[k + 1:] if (n := num(c)) is not None), None)
            if goals is None:
                continue
            key = qids.get(l, l)
            if key not in best or goals > best[key][0]:
                best[key] = (goals, y, by_qid.get(qids.get(l)))
    ranked = sorted(best.values(), key=lambda b: -b[0])
    cut = ranked[9][0]
    top, tied = ranked[:10], [b for b in ranked[10:] if b[0] == cut]
    if any(p is None for _, _, p in top + tied):
        return None, "a player we don't know: " + ", ".join(str(y) for _, y, p in top + tied if p is None)
    entries, rank = [], 0
    for i, (g, y, p) in enumerate(top):
        rank = rank if i and g == top[i - 1][0] else i + 1
        alts = [[w["id"], w["name"]] for _, _, w in tied] if i == 9 else []
        entries.append([rank, p["id"], p["name"], f"{g} ({_season(y)})"] + ([alts] if alts else []))
    return entries, None


AFRICA = set("DZ AO BJ BW BF BI CM CV CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW "
               "ML MR MU MA MZ NA NE NG RW ST SN SC SL SO ZA SS SD TZ TG TN UG ZM ZW".split())
SINCE_2006 = " (since 2006\u201307)"  # the feed only tracks these from then


def _fold(t: str) -> str:
    return unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()


def feed_matcher(by_qid):
    """Feed owner -> our player: same birth date and a shared name."""
    raw = json.load(gzip.open(HERE / "raw" / "players.json.gz", "rt", encoding="utf-8"))
    by_dob: dict[str, list[dict]] = {}
    for r in raw:
        if r["id"] in by_qid and r.get("dob"):
            by_dob.setdefault(r["dob"], []).append(r)

    def words(r):
        p = by_qid[r["id"]]
        names = [p["name"], r.get("name") or "", *p.get("aliases", []), *r.get("aliases", []), *r.get("family_names", [])]
        return {w for n in names for w in re.findall(r"[a-z]+", _fold(n)) if len(w) > 2}

    def match(owner):
        ms = (owner.get("birth") or {}).get("date", {}).get("millis")
        if ms is None:
            return None
        dob = dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc).date().isoformat()
        name = owner["name"]
        want = {w for w in re.findall(r"[a-z]+", _fold(f"{name.get('first', '')} {name.get('last', '')} {name['display']}")) if len(w) > 2}
        last = {w for w in re.findall(r"[a-z]+", _fold(name.get("last", ""))) if len(w) > 2}
        same_day = by_dob.get(dob, [])
        # Surname first (Damien Duff, not Damien Gregorini born the same day).
        for need in (last, want):
            hits = [r for r in same_day if need & words(r)]
            if len(hits) == 1:
                return by_qid[hits[0]["id"]]
        return None
    return match


def feed_list(rows, match, unit: str, keep=lambda o: True, max_alts: int = 8):
    """(entries, problem) from feed rows (already ranked): the first ten that
    pass keep(), with anyone level on 10th sharing the slot."""
    rows = [r for r in rows if keep(r["owner"])]
    if len(rows) < 11:
        return None, f"only {len(rows)} rows"
    cut = rows[9]["value"]
    top, tied = rows[:10], [r for r in rows[10:] if r["value"] == cut]
    if len(tied) > max_alts:
        return None, f"{len(tied) + 1} level on 10th"
    who = [match(r["owner"]) for r in top + tied]
    if None in who:
        return None, "a player we don't know: " + ", ".join(
            r["owner"]["name"]["display"] for r, w in zip(top + tied, who) if w is None)
    entries, rank = [], 0
    for i, (r, p) in enumerate(zip(top, who)):
        rank = rank if i and r["value"] == top[i - 1]["value"] else i + 1
        alts = [[w["id"], w["name"]] for w in who[10:]] if i == 9 else []
        entries.append([rank, p["id"], p["name"], f"{int(r['value']):,} {unit}"] + ([alts] if alts else []))
    return entries, None


def feed_lists(pages, qids, by_qid):
    """Top 10s from the Premier League stats feed (raw/pl_stats.json.gz)."""
    path = HERE / "raw" / "pl_stats.json.gz"
    if not path.exists():
        return [], ["pl stats: no feed data"]
    feed = json.load(gzip.open(path, "rt", encoding="utf-8"))
    al, dec = feed["all"], feed["decades"]
    match = feed_matcher(by_qid)
    nat = lambda *codes: (lambda o: (o.get("nationalTeam") or {}).get("isoCode") in codes)
    # No "by a defender" lists: the feed has one position per player, their
    # last (Ashley Young, a winger for most of his goals, is a defender).
    # Title winners: everyone in Wikipedia's list of Premier League winners.
    winners = set()
    page = pages.get("List of Premier League winning players")
    if page:
        for _, _, _, rows in tables(page):
            for cells in rows:
                for l in LINK.findall(" ".join(strip_attr(c) for c in cells)):
                    if (q := qids.get(l.strip())) in by_qid:
                        winners.add(by_qid[q]["id"])
    specs = [
        ("pl-own-goals", "Most Premier League own goals", 2, al["own_goals"], "own goals", None),
        ("pl-red-cards", "Most Premier League red cards", 2, al["red_card"], "reds", None),
        ("pl-yellow-cards", "Most Premier League yellow cards", 3, al["yellow_card"], "yellows", None),
        ("pl-headers", "Most Premier League headed goals" + SINCE_2006, 2, al["att_hd_goal"], "headers", None),
        ("pl-long-range", "Most Premier League goals from outside the box" + SINCE_2006, 2, al["att_obox_goal"], "goals", None),
        ("pl-goals-no-title", "Most Premier League goals without winning the title", 2, al["goals"], "goals",
         lambda o: (p := match(o)) is not None and p["id"] not in winners),
    ]
    for code, label, d in [("BR", "Brazilian", 2), ("FR", "French", 2), ("ES", "Spanish", 2), ("NL", "Dutch", 2),
                           ("AR", "Argentine", 2), ("PT", "Portuguese", 3), ("DE", "German", 3), ("BE", "Belgian", 3),
                           ("NO", "Norwegian", 3), ("GB-SCT", "Scottish", 3), ("GB-WLS", "Welsh", 3), ("IE", "Irish", 3),
                           ("GB-NIR", "Northern Irish", 3), ("US", "American", 3), ("CI", "Ivorian", 3)]:
        specs.append((f"pl-goals-{code.lower()}", f"Most Premier League goals by {'an' if label[0] in 'AEIOU' else 'a'} {label} player", d, al["goals"], "goals", nat(code)))
    specs.append(("pl-goals-africa", "Most Premier League goals by an African player", 2, al["goals"], "goals",
                  lambda o: (o.get("nationalTeam") or {}).get("isoCode") in AFRICA))
    for name, span in [("1990s", "1992\u20132000"), ("2000s", "2000\u201310"), ("2010s", "2010\u201320"), ("2020s", "since 2020")]:
        for stat, what, unit in [("goals", "goals", "goals"), ("goal_assist", "assists", "assists"), ("appearances", "appearances", "apps")]:
            specs.append((f"pl-{stat.split('_')[-1]}-{name}", f"Most Premier League {what} in the {name} ({span})",
                          2 if stat == "goals" else 3, dec[name][stat], unit, None))
    out, dropped = [], []
    for lid, q, d, rows, unit, keep in specs:
        entries, problem = feed_list(rows, match, unit, keep or (lambda o: True))
        if problem:
            dropped.append(f"{lid}: {problem}")
        else:
            out.append({"id": lid, "q": q, "d": d, "asof": dt.date.today().strftime("%b %Y"),
                        "src": "premierleague.com stats", "e": entries})
    return out, dropped


def main() -> int:
    pages, qids, by_qid = load()
    qids.update(TITLE_QID)
    out, dropped = [], []
    got, lost = feed_lists(pages, qids, by_qid)
    out += got
    dropped += lost
    for lid, q, d, title in [
        ("pl-season-goals", "Most Premier League goals in a season (best season each)", 2,
         lambda y: f"{_season(y)} {'FA ' if y < 2007 else ''}Premier League"),
        ("ucl-season-goals", "Most Champions League goals in a season (best season each)", 2,
         lambda y: f"{_season(y)} UEFA Champions League"),
    ]:
        entries, problem = season_record(pages, qids, by_qid, title)
        if problem:
            dropped.append(f"{lid}: {problem}")
        else:
            out.append({"id": lid, "q": q, "d": d, "src": "season articles", "e": entries})
    for lid, article, idx, question, level, unit in LISTS + SEASONS:
        page = pages.get(article)
        if not page:
            dropped.append(f"{lid}: no article")
            continue
        tabs = list(tables(page))
        if isinstance(idx, str):
            # The first table under a heading (or with a caption) matching idx.
            idx = next((n for n, (heads, cap, _, _) in enumerate(tabs) if re.search(idx, f"{heads} {cap}", re.I)), len(tabs))
        if idx >= len(tabs):
            dropped.append(f"{lid}: no table {idx}")
            continue
        rows = tabs[idx][3]
        if lid in EXCLUDE:
            other = {l.strip() for r in tabs[EXCLUDE[lid]][3] for c in r for l in LINK.findall(strip_attr(c))}
            rows = [r for r in rows if not any(l.strip() in other for c in r for l in LINK.findall(strip_attr(c)))]
        entries, problem = build_list(rows, qids, by_qid, unit, FIG_COL.get(lid), lid in DEDUPE)
        if problem:
            dropped.append(f"{lid}: {problem}")
            continue
        live = not lid.split("-")[-1].isdigit()  # a finished season doesn't change
        out.append({"id": lid, "q": question, "d": level, **({"asof": dt.date.today().strftime("%b %Y")} if live else {}),
                    "src": article, "e": entries})
    note = f"Top 10 lists from Wikipedia record tables: {len(out)} lists, {len(dropped)} dropped. Built {dt.date.today()}."
    OUT.write_text(json.dumps({"_note": note, "dropped": dropped, "lists": out}, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
    print(note)
    for d in dropped:
        print("  dropped", d)
    for l in out:
        print(f"  {l['id']:18} {l['q']}: " + "; ".join(f"{e[0]}. {e[2]}" + (f" ({e[3]})" if len(e) > 3 and e[3] else "")
                                                      + ("".join(f" / {a[1]}" for a in e[4]) if len(e) > 4 else "") for e in l["e"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
