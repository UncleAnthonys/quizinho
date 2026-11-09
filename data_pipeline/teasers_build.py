"""Half-Time Teasers: "Name the player who played for X, Y AND Z".

    python3 data_pipeline/teasers_build.py            # fetch + check (CI)
    python3 data_pipeline/teasers_build.py --offline  # candidates only, no checking

Two independent sources must agree before a teaser is kept:

  A. Wikidata careers (seed/players.json), with appearances at each club
     (Wikidata's own numbers or the Wikipedia-filled seed/wiki_stats.json).
  B. The senior-career rows of each player's English Wikipedia infobox,
     with at least one league appearance at each club (loans count).

For every trio of well-known clubs, the set of players who fit must be the
SAME in A and B, and only one or two players. Every player with two or more
of the clubs in either source is checked, so a player Wikidata missed but
Wikipedia has (or the other way round) knocks the trio out rather than
becoming a "wrong" answer at the table. Wikidata errors (a transfer that
never happened, an unused registration) fail the same way.

Writes seed/teasers.json. Runs in GitHub Actions (teasers.yml): the dev
workspace can't reach Wikipedia.
"""

from __future__ import annotations

import argparse
import collections
import itertools
import json
import pathlib
import random
import time

from wiki_stats_fetch import club_qids, enwiki_titles, infobox_rows, wikitext

ROOT = pathlib.Path(__file__).resolve().parent
SEED = ROOT / "seed"

# Clubs a pub table would know, with the name the question uses.
POOL = {
    "Q9617": "Arsenal", "Q9616": "Chelsea", "Q1130849": "Liverpool", "Q18656": "Manchester United",
    "Q50602": "Manchester City", "Q18741": "Tottenham", "Q5794": "Everton", "Q18716": "Newcastle",
    "Q18711": "Aston Villa", "Q18747": "West Ham", "Q18708": "Fulham", "Q1128631": "Leeds",
    "Q19481": "Leicester", "Q18732": "Southampton", "Q18739": "Sunderland", "Q18661": "Middlesbrough",
    "Q19446": "Blackburn", "Q19467": "Crystal Palace", "Q19500": "Wolves", "Q18736": "Stoke",
    "Q19451": "Bolton", "Q19604": "Portsmouth", "Q19490": "Nottingham Forest", "Q19453": "Brighton",
    "Q18723": "QPR", "Q19593": "Celtic", "Q19597": "Rangers",
    "Q8682": "Real Madrid", "Q7156": "Barcelona", "Q8701": "Atlético Madrid", "Q10333": "Valencia",
    "Q10329": "Sevilla", "Q12297": "Villarreal", "Q8723": "Real Betis", "Q8687": "Athletic Bilbao",
    "Q1422": "Juventus", "Q1543": "AC Milan", "Q631": "Inter Milan", "Q2739": "Roma", "Q2609": "Lazio",
    "Q2641": "Napoli", "Q2052": "Fiorentina", "Q1457": "Sampdoria", "Q2693": "Parma", "Q2768": "Torino",
    "Q2798": "Udinese",
    "Q15789": "Bayern Munich", "Q41420": "Borussia Dortmund", "Q104761": "Bayer Leverkusen",
    "Q32494": "Schalke", "Q101859": "Wolfsburg", "Q51976": "Werder Bremen", "Q51974": "Hamburg",
    "Q702455": "RB Leipzig",
    "Q483020": "PSG", "Q132885": "Marseille", "Q704": "Lyon", "Q180305": "Monaco", "Q19516": "Lille",
    "Q81888": "Ajax", "Q11938": "PSV", "Q134241": "Feyenoord",
    "Q128446": "Porto", "Q131499": "Benfica", "Q75729": "Sporting",
    "Q495299": "Galatasaray", "Q6601875": "Fenerbahçe", "Q172567": "Beşiktaş",
    "Q170703": "Boca Juniors", "Q15799": "River Plate", "Q17479": "Flamengo", "Q38568": "São Paulo",
    "Q35933": "Corinthians", "Q204357": "LA Galaxy", "Q16844931": "Inter Miami",
    "Q482764": "Al-Nassr", "Q73965": "Al-Hilal", "Q179075": "Dynamo Kyiv", "Q172969": "Shakhtar Donetsk",
    "Q29108": "Zenit", "Q19628": "Olympiacos",
}

# Derbies, both sides in POOL. A derby teaser names three: you need a player
# who played for a side in each, so every name that comes to mind for one
# derby is a red herring for the other two.
DERBIES = {
    "El Clásico": ("Q8682", "Q7156"),
    "the Madrid derby": ("Q8682", "Q8701"),
    "the Manchester derby": ("Q18656", "Q50602"),
    "the North London derby": ("Q9617", "Q18741"),
    "the Merseyside derby": ("Q1130849", "Q5794"),
    "the North West derby": ("Q1130849", "Q18656"),
    "the Old Firm": ("Q19593", "Q19597"),
    "the Tyne–Wear derby": ("Q18716", "Q18739"),
    "the Milan derby": ("Q1543", "Q631"),
    "the Derby della Capitale": ("Q2739", "Q2609"),
    "the Derby d'Italia": ("Q1422", "Q631"),
    "Der Klassiker": ("Q15789", "Q41420"),
    "the Revierderby": ("Q41420", "Q32494"),
    "Le Classique": ("Q483020", "Q132885"),
    "De Klassieker": ("Q81888", "Q134241"),
    "O Clássico": ("Q131499", "Q128446"),
    "the Lisbon derby": ("Q131499", "Q75729"),
    "the Intercontinental derby": ("Q495299", "Q6601875"),
    "the Superclásico": ("Q170703", "Q15799"),
    "the Seville derby": ("Q10329", "Q8723"),
}

MAX_ANSWERS = 2
MAX_DERBY_ANSWERS = 4
KEEP_DERBY = 250
MIN_FAME = 3  # at least one answer a table could know
KEEP = 400


def careers_a(players: list[dict], wiki_stats: dict) -> dict[str, set[str]]:
    """Wikidata: player → pool clubs with at least one appearance."""
    out = {}
    for p in players:
        if p.get("women") or not p.get("wikidata"):
            continue
        stats = {**(wiki_stats.get(p["id"]) or {}), **(p.get("stats") or {})}
        clubs = {e[0] for e in p.get("career", []) if e[0] in POOL and (stats.get(e[0]) or [0])[0] > 0}
        if len(clubs) >= 2:
            out[p["id"]] = clubs
    return out


def careers_b(players: list[dict], ids: list[str]) -> dict[str, set[str]]:
    """English Wikipedia infobox: player → pool clubs with at least one league appearance."""
    qid = {p["id"]: p["wikidata"] for p in players}
    titles = enwiki_titles([qid[i] for i in ids])
    pages = wikitext(sorted(set(titles.values())))
    rows = {i: infobox_rows(pages.get(titles.get(qid[i], ""), "")) for i in ids}
    clubs = club_qids(sorted({t for r in rows.values() for t, _, _ in r}))
    out = {}
    for i, r in rows.items():
        out[i] = {clubs[t] for t, apps, _ in r if clubs.get(t) in POOL and (apps or 0) > 0}
    print(f"Wikipedia: {len(titles)} articles, {sum(1 for r in rows.values() if r)} infoboxes")
    return out


def fits(careers: dict[str, set[str]]) -> dict[tuple, set[str]]:
    out = collections.defaultdict(set)
    for pid, s in careers.items():
        for t in itertools.combinations(sorted(s), 3):
            out[t].add(pid)
    return out


def derby_fits(careers: dict[str, set[str]]) -> dict[tuple, set[str]]:
    """Three derbies → players who played for a side in each (one club per derby)."""
    out = collections.defaultdict(set)
    for pid, s in careers.items():
        hit = sorted(d for d, pair in DERBIES.items() if s & set(pair))
        for t in itertools.combinations(hit, 3):
            # Each derby needs its own club: Real Madrid alone can't cover
            # El Clásico and the Madrid derby.
            pairs = [s & set(DERBIES[d]) for d in t]
            if any(len({x, y, z}) == 3 for x in pairs[0] for y in pairs[1] for z in pairs[2]):
                out[t].add(pid)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true", help="skip the Wikipedia check (local dry run)")
    args = ap.parse_args()

    players = json.loads((SEED / "players.json").read_text())["players"]
    wiki_stats = json.loads((SEED / "wiki_stats.json").read_text())["players"]
    by_id = {p["id"]: p for p in players}
    a = careers_a(players, wiki_stats)
    fa = fits(a)
    cand = {t: s for t, s in fa.items() if 1 <= len(s) <= MAX_ANSWERS
            and max(by_id[i].get("fame", 0) for i in s) >= MIN_FAME}
    fda = derby_fits(a)
    dcand = {t: s for t, s in fda.items() if 1 <= len(s) <= MAX_DERBY_ANSWERS
             and max(by_id[i].get("fame", 0) for i in s) >= MIN_FAME}
    print(f"Wikidata: {len(a)} players at 2+ pool clubs; {len(cand)} club trios, {len(dcand)} derby trios")

    if args.offline:
        kept, dkept = cand, dcand
    else:
        # Everyone with 2+ pool clubs anywhere in Wikidata (appearances or not), so a
        # club or a number Wikidata lacks still shows up on the Wikipedia side.
        loose = [p["id"] for p in players if not p.get("women") and p.get("wikidata")
                 and len({e[0] for e in p.get("career", []) if e[0] in POOL}) >= 2]
        b = careers_b(players, loose)
        fb = fits(b)
        kept = {t: s for t, s in cand.items() if fb.get(t, set()) == s}
        fdb = derby_fits(b)
        dkept = {t: s for t, s in dcand.items() if fdb.get(t, set()) == s}
        print(f"Both sources agree on {len(kept)} of {len(cand)} club trios, {len(dkept)} of {len(dcand)} derby trios")

    # One question per player as the (or an) answer, the most famous answers first,
    # then shuffled so a run isn't all one club.
    rng = random.Random(7)
    order = sorted(kept.items(), key=lambda kv: (-max(by_id[i]["fame"] for i in kv[1]), len(kv[1]), kv[0]))
    used: set[str] = set()
    out = []
    for t, s in order:
        if s & used:
            continue
        used |= s
        top = max(by_id[i]["fame"] for i in s)
        out.append({
            "kind": "clubs",
            "clubs": list(t),
            "q": "Played for " + ", ".join(POOL[c] for c in t[:-1]) + " AND " + POOL[t[-1]],
            "answers": sorted(s),
            "names": [by_id[i]["name"] for i in sorted(s)],
            "difficulty": 1 if top >= 5 else 2 if top == 4 else 3,
        })
        if len(out) >= KEEP:
            break

    # Derbies: the fewer answers the better, and a player can be the answer
    # to two derby teasers at most.
    dorder = sorted(dkept.items(), key=lambda kv: (len(kv[1]), -max(by_id[i]["fame"] for i in kv[1]), kv[0]))
    dused: collections.Counter = collections.Counter()
    nd = 0
    for t, s in dorder:
        if any(dused[i] >= 2 for i in s):
            continue
        dused.update(s)
        top = max(by_id[i]["fame"] for i in s)
        out.append({
            "kind": "derbies",
            "derbies": list(t),
            "q": "Played for a side in " + ", ".join(t[:-1]) + " AND " + t[-1],
            "answers": sorted(s),
            "names": [by_id[i]["name"] for i in sorted(s)],
            "difficulty": 1 if top >= 5 and len(s) > 1 else 2 if top >= 4 else 3,
        })
        nd += 1
        if nd >= KEEP_DERBY:
            break
    rng.shuffle(out)

    note = (f"Half-Time Teasers: three clubs (one or two players fit) or three derbies (up to four). "
            f"{'UNCHECKED (offline run)' if args.offline else 'Wikidata and English Wikipedia agree on every answer set'}. "
            f"{len(out)} teasers. Built {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}.")
    print(note)
    (SEED / "teasers.json").write_text(
        "{\n" + f'  "_note": {json.dumps(note)},\n  "checked": {json.dumps(not args.offline)},\n  "teasers": [\n'
        + ",\n".join("    " + json.dumps(t, ensure_ascii=False) for t in out) + "\n  ]\n}\n",
        encoding="utf-8")


if __name__ == "__main__":
    main()
