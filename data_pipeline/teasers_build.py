"""Half-Time Teasers: the slow-burn question that runs through a tournament.

    python3 data_pipeline/teasers_build.py            # curated + final scorers (CI)
    python3 data_pipeline/teasers_build.py --offline  # curated only

Two kinds:

  curated  seed/teasers_curated.json, written by hand: "Played in El Clásico,
           the Manchester derby AND the North London derby". Every answer
           has a line-up or match report per fixture in its proof.
  final    "Scored in a Champions League / World Cup final AND played for X".
           Scorers come from each final's Wikipedia article; the club must be
           in both Wikidata and the player's Wikipedia infobox, with league
           games, and the two sources must agree on the whole answer set.

Writes seed/teasers.json. Runs in GitHub Actions (teasers.yml): the dev
workspace can't reach Wikipedia.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import random
import re
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

MIN_FAME = 3  # at least one answer a table could know


def careers_a(players: list[dict], wiki_stats: dict, least: int = 2) -> dict[str, set[str]]:
    """Wikidata: player → pool clubs with at least one appearance."""
    out = {}
    for p in players:
        if p.get("women") or not p.get("wikidata"):
            continue
        stats = {**(wiki_stats.get(p["id"]) or {}), **(p.get("stats") or {})}
        clubs = {e[0] for e in p.get("career", []) if e[0] in POOL and (stats.get(e[0]) or [0])[0] > 0}
        if len(clubs) >= least:
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


GOALS = re.compile(r"\|\s*goals([12])\s*=(.*?)(?=\n\s*\||\n\}\})", re.S)
PLAYER_LINK = re.compile(r"\[\[([^\]|#]+)(?:\|[^\]]*)?\]\]\s*((?:\{\{[^}]*\}\}\s*,?\s*)+)")


def final_titles() -> dict[str, list[str]]:
    """Competition → Wikipedia article titles of its finals (redirects resolve the old names)."""
    cl = [f"{y} European Cup final" if y < 1993 else f"{y} UEFA Champions League final" for y in range(1956, 2027)]
    wc = [f"{y} FIFA World Cup final" for y in (1930, 1934, 1938, *range(1954, 2023, 4))]
    return {"cl": cl, "wc": wc}


def final_scorers(titles: list[str]) -> dict[str, set[str]]:
    """Final article title → linked titles of players who scored in it (own goals and shoot-outs left out)."""
    pages = wikitext(titles)
    out = {}
    for t, text in pages.items():
        who = set()
        for _, block in GOALS.findall(text):
            for name, marks in PLAYER_LINK.findall(block):
                goals = re.findall(r"\{\{\s*goal\s*\|([^}]*)\}\}", marks, re.I)
                # {{goal|35|o.g.}} is an own goal; {{goal|12|pen.}} still counts.
                if any(not re.search(r"\bo\.?g\.?\s*$", g.strip(), re.I) for g in goals):
                    who.add(name.strip().replace("_", " "))
        out[t] = who
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true", help="only the curated teasers (no Wikipedia)")
    args = ap.parse_args()

    players = json.loads((SEED / "players.json").read_text())["players"]
    wiki_stats = json.loads((SEED / "wiki_stats.json").read_text())["players"]
    by_id = {p["id"]: p for p in players}
    by_qid = {p["wikidata"]: p["id"] for p in players if p.get("wikidata")}
    out = []

    # Hand-checked teasers (derbies played in and the like): every answer has a
    # line-up or match report per fixture in its sources.
    curated = json.loads((SEED / "teasers_curated.json").read_text())["teasers"]
    for t in curated:
        out.append({"kind": "curated", **t})
    print(f"{len(curated)} curated teasers")

    if not args.offline:
        # "Scored in a Champions League / World Cup final AND played for X".
        # Scorers: the goals in each final's own article. Clubs: Wikidata AND the
        # player's Wikipedia infobox must both have league games there.
        a = careers_a(players, wiki_stats, least=1)
        comps = final_titles()
        scored: dict[str, set[str]] = {}
        for comp, titles in comps.items():
            per = final_scorers(titles)
            names = sorted({n for s in per.values() for n in s})
            qids = club_qids(names)  # works for any article title
            ids = {by_qid[q] for n, q in qids.items() if q in by_qid}
            scored[comp] = ids
            print(f"{comp}: {len(per)} finals, {len(names)} scorers, {len(ids)} in our player data")
        everyone = sorted(set().union(*scored.values()))
        b = careers_b(players, everyone)
        label = {"cl": "Scored in a European Cup or Champions League final", "wc": "Scored in a World Cup final"}
        for comp, ids in scored.items():
            for club, name in POOL.items():
                s = {i for i in ids if club in a.get(i, set()) and club in b.get(i, set())}
                # Both sources must agree, and nobody Wikidata alone puts at the club.
                loose = {i for i in ids if club in a.get(i, set()) or club in b.get(i, set())}
                if not (1 <= len(s) <= 3) or s != loose or max(by_id[i]["fame"] for i in s) < MIN_FAME:
                    continue
                top = max(by_id[i]["fame"] for i in s)
                out.append({
                    "kind": "final",
                    "q": f"{label[comp]} AND played for {name}",
                    "answers": sorted(s),
                    "names": [by_id[i]["name"] for i in sorted(s)],
                    "difficulty": 1 if top >= 5 else 2 if top == 4 else 3,
                })
        both = scored["cl"] & scored["wc"]
        out.append({
            "kind": "final",
            "q": "Scored in a World Cup final AND a European Cup or Champions League final",
            "answers": sorted(both),
            "names": [by_id[i]["name"] for i in sorted(both)],
            "difficulty": 2,
        })

    random.Random(7).shuffle(out)
    note = (f"Half-Time Teasers: {sum(t['kind'] == 'curated' for t in out)} hand-checked, "
            f"{sum(t['kind'] == 'final' for t in out)} final-scorer teasers checked against Wikipedia. "
            f"Built {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}.")
    print(note)
    (SEED / "teasers.json").write_text(
        "{\n" + f'  "_note": {json.dumps(note)},\n  "teasers": [\n'
        + ",\n".join("    " + json.dumps(t, ensure_ascii=False) for t in out) + "\n  ]\n}\n",
        encoding="utf-8")


if __name__ == "__main__":
    main()
