"""Fetches the English Wikipedia articles behind the hand-checked Under the
Radar lists (tournament squads, World Cup red cards and shoot-outs...) and
saves their wikitext to raw/radar_wikitext.json.gz, so the lists can be
built and re-checked offline. Run from the Actions tab: this needs Wikipedia.
"""
from __future__ import annotations

import gzip
import json
import pathlib

from wiki_stats_fetch import wikitext

RAW = pathlib.Path(__file__).parent / "raw"

ARTICLES = [
    *[f"{y} FIFA World Cup squads" for y in (1990, 1994, 1998, 2002, 2006, 2010, 2014, 2018, 2022)],
    *[f"UEFA Euro {y} squads" for y in (1996, 2000, 2004, 2008, 2012, 2016, 2020, 2024)],
    *[f"{y} FIFA World Cup statistics" for y in (2002, 2006, 2010, 2014, 2018, 2022)],
    *[f"UEFA Euro {y} statistics" for y in (2016, 2020, 2024)],
    "List of FIFA World Cup red cards",
    "List of FIFA World Cup penalty shoot-outs",
    "List of FIFA World Cup own goals",
    "England at the FIFA World Cup",
    "List of UEFA Champions League final penalty shoot-outs",
    "List of European Cup and UEFA Champions League winning managers",
]


def main() -> int:
    pages = wikitext(ARTICLES)
    with gzip.open(RAW / "radar_wikitext.json.gz", "wt", encoding="utf-8") as f:
        json.dump({"pages": pages}, f, ensure_ascii=False)
    missing = [t for t in ARTICLES if t not in pages]
    print(f"fetched {len(pages)} of {len(ARTICLES)} articles; missing: {missing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
