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
import json
import pathlib
import re

from top10_tables import LINK, load, strip_attr, tables

HERE = pathlib.Path(__file__).parent
OUT = HERE.parent / "assets" / "db" / "top10.json"

PL = "Premier League records and statistics"
LISTS = [
    # (id, article, table index, question, level, unit)
    ("pl-goals", PL, 1, "Premier League all-time top scorers", 1, "goals"),
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
    s = re.sub(r"<ref.*", "", s).strip().replace(",", "")
    s = re.sub(r"'''|''", "", s).strip()
    return int(s) if re.fullmatch(r"\d+", s) else None


def build_list(rows, qids, by_qid, unit: str):
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
            fig = next((n for c in cells[k0 + 1:] if (n := num(c)) is not None), None)
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
            return None, f"{p['name']} twice (a by-season table?)"
        figure = next((n for c in cells[k + 1:] if (n := num(c)) is not None), None)
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
        shown = f"{f:,} {unit}".strip() if ordered and unit else ""
        alts = [[w["id"], w["name"]] for w in tied] if i == 9 else []
        entries.append([rank, p["id"], p["name"], shown, alts] if alts else
                       [rank, p["id"], p["name"], shown] if shown else [rank, p["id"], p["name"]])
    return entries, None


def pl_season_record(pages, qids, by_qid):
    """Most Premier League goals in a season, each player's best once
    ("36 (2022\u201323)"), from every season's top-scorer table: a 30-goal
    season is always in its season's top ten."""
    best: dict[str, tuple[int, int, dict]] = {}
    for y in range(1992, 2026):
        page = pages.get(f"{_season(y)} {'FA ' if y < 2007 else ''}Premier League")
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
    top = [b for b in ranked if b[0] >= cut]
    if len(top) > 10 or any(p is None for _, _, p in top):
        return None, "tie past 10th or a player we don't know"
    entries, rank = [], 0
    for i, (g, y, p) in enumerate(top):
        rank = rank if i and g == top[i - 1][0] else i + 1
        entries.append([rank, p["id"], p["name"], f"{g} ({_season(y)})"])
    return entries, None


def main() -> int:
    pages, qids, by_qid = load()
    qids.update(TITLE_QID)
    out, dropped = [], []
    entries, problem = pl_season_record(pages, qids, by_qid)
    if problem:
        dropped.append(f"pl-season-goals: {problem}")
    else:
        out.append({"id": "pl-season-goals", "q": "Most Premier League goals in a season (best season each)", "d": 2,
                    "src": "Premier League season articles", "e": entries})
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
        entries, problem = build_list(rows, qids, by_qid, unit)
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
