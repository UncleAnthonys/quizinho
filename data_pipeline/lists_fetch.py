"""Fetches the English Wikipedia articles behind Top 10 (record tables:
Premier League top scorers, club record scorers, most caps...) and saves the
wikitext, plus the Wikidata id of every linked article, to
raw/lists_wikitext.json.gz for top10_build.py to read offline. Run from the
Actions tab: this needs Wikipedia.
"""
from __future__ import annotations

import gzip
import json
import pathlib
import re

from wiki_stats_fetch import club_qids, wikitext

RAW = pathlib.Path(__file__).parent / "raw"
LINK = re.compile(r"\[\[([^\]|#]+)")

ARTICLES = [
    "Premier League records and statistics",
    "List of Premier League players with 100 or more goals",
    "List of footballers with 500 or more Premier League appearances",
    "List of UEFA Champions League top scorers",
    "List of FIFA World Cup top goalscorers",
    "UEFA European Championship records and statistics",
    "List of men's footballers with 100 or more international caps",
    "List of men's footballers with 50 or more international goals",
    "England national football team records and statistics",
    "List of most expensive association football transfers",
    "Manchester United F.C. records and statistics",
    "Liverpool F.C. records and statistics",
    "Arsenal F.C. records and statistics",
    "Chelsea F.C. records and statistics",
    "Tottenham Hotspur F.C. records and statistics",
    "Manchester City F.C. records and statistics",
    "Newcastle United F.C. records and statistics",
    "Everton F.C. records and statistics",
    "Aston Villa F.C. records and statistics",
    "West Ham United F.C. records and statistics",
    "List of Real Madrid CF records and statistics",
    "List of FC Barcelona records and statistics",
    "List of Juventus FC records and statistics",
    "List of AC Milan records and statistics",
    "FC Bayern Munich records and statistics",
    "List of La Liga top scorers",
    "List of Serie A top scorers",
    "List of Bundesliga top scorers",
    "Premier League Golden Boot",
    "List of Premier League hat-tricks",
    "List of Liverpool F.C. records and statistics",
    "List of Arsenal F.C. records and statistics",
    "List of Chelsea F.C. records and statistics",
    "List of Tottenham Hotspur F.C. records and statistics",
    "List of Manchester City F.C. records and statistics",
    "List of Newcastle United F.C. records and statistics",
    "List of Everton F.C. records and statistics",
    "List of West Ham United F.C. records and statistics",
    "List of FC Bayern Munich records and statistics",
    "List of Celtic F.C. records and statistics",
    "List of Rangers F.C. records and statistics",
    "List of Ballon d'Or winners",
]


def main() -> int:
    pages = wikitext(ARTICLES)
    linked = sorted({m.strip().replace("_", " ") for t in pages.values() for m in LINK.findall(t) if ":" not in m})
    qids = club_qids(linked)
    with gzip.open(RAW / "lists_wikitext.json.gz", "wt", encoding="utf-8") as f:
        json.dump({"pages": pages, "qids": qids}, f, ensure_ascii=False)
    missing = [t for t in ARTICLES if t not in pages]
    print(f"fetched {len(pages)} of {len(ARTICLES)} articles; {len(qids)} linked ids; missing: {missing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
