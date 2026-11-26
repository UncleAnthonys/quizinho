"""Every player who's played for each club Hat-Trick can deal, from Wikipedia.

Hat-Trick scores a point for each of three clubs a named player played for,
so a Swindon one-pointer (Christian Roberts) has to be known even though the
career data only has the players it has careers for. Each club's "players"
category on Wikipedia ("Category:Swindon Town F.C. players") lists everyone;
Wikidata says which category is the club's (P6112, category for members of a
team), so nothing is guessed. Writes raw/club_rosters.json.gz:

  {"clubs": {club qid: [[article title, player qid or null], ...]}}

build_db.py turns these into assets/db/hat_trick_rosters.json (Hat-Trick only:
the extra names never join the main player list). Runs in GitHub Actions
(.github/workflows/club-rosters.yml): the dev workspace can't reach Wikipedia.
"""
from __future__ import annotations

import gzip
import json
import pathlib
import time

from wiki_stats_fetch import ENWIKI, WIKIDATA, chunks, club_qids, get

ROOT = pathlib.Path(__file__).parent
RAW = ROOT / "raw"
SEED = ROOT / "seed"

# The clubs Hat-Trick can deal (a superset of today's sets, so new ones are
# covered): men's clubs, fame 3+, in the leagues build_db's Hat-Trick uses.
LEAGUES = {"GBR", "ENG", "SCO", "ESP", "ITA", "GER", "FRA", "MCO", "POR", "NED", "TUR", "BRA", "ARG"}


def clubs() -> list[str]:
    rows = json.loads((SEED / "clubs.json").read_text(encoding="utf-8"))["clubs"]
    return [c[0] for c in rows if c[3] >= 3 and c[2] in LEAGUES and not (len(c) > 6 and c[6] == "w")]


def categories(qids: list[str]) -> dict[str, str]:
    """Club qid -> its players category title on English Wikipedia."""
    cat_of: dict[str, str] = {}
    for batch in chunks(qids):
        d = get(WIKIDATA, {"action": "wbgetentities", "ids": "|".join(batch), "props": "claims"})
        for qid, e in d.get("entities", {}).items():
            for claim in (e.get("claims") or {}).get("P6112", []):
                v = ((claim.get("mainsnak") or {}).get("datavalue") or {}).get("value") or {}
                if v.get("id"):
                    cat_of[qid] = v["id"]
                    break
        time.sleep(0.2)
    out: dict[str, str] = {}
    cats = sorted(set(cat_of.values()))
    titles: dict[str, str] = {}
    for batch in chunks(cats):
        d = get(WIKIDATA, {"action": "wbgetentities", "ids": "|".join(batch), "props": "sitelinks",
                           "sitefilter": "enwiki"})
        for qid, e in d.get("entities", {}).items():
            link = (e.get("sitelinks") or {}).get("enwiki")
            if link:
                titles[qid] = link["title"]
        time.sleep(0.2)
    for club, cat in cat_of.items():
        if cat in titles:
            out[club] = titles[cat]
    return out


def members(category: str) -> list[str]:
    out, cont = [], {}
    while True:
        d = get(ENWIKI, {"action": "query", "list": "categorymembers", "cmtitle": category,
                         "cmtype": "page", "cmnamespace": 0, "cmlimit": 500, **cont})
        out += [m["title"] for m in d.get("query", {}).get("categorymembers", [])]
        if "continue" not in d:
            return out
        cont = {"cmcontinue": d["continue"]["cmcontinue"]}
        time.sleep(0.2)


def main() -> int:
    ids = clubs()
    cats = categories(ids)
    print(f"{len(ids)} clubs, {len(cats)} with a players category")
    rosters: dict[str, list[str]] = {}
    for club, cat in sorted(cats.items()):
        rosters[club] = members(cat)
        print(f"  {cat}: {len(rosters[club])}")
    qids = club_qids(sorted({t for ts in rosters.values() for t in ts}))
    out = {"clubs": {c: [[t, qids.get(t)] for t in ts] for c, ts in rosters.items()},
           "missing": sorted(set(ids) - set(cats))}
    with gzip.open(RAW / "club_rosters.json.gz", "wt", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"{sum(len(v) for v in rosters.values())} roster entries, {len(qids)} with a Wikidata id; "
          f"no category: {len(out['missing'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
