"""Fetches the English Wikipedia articles behind the hand-checked Under the
Radar lists (tournament squads, World Cup red cards and shoot-outs...) and
saves their wikitext to raw/radar_wikitext.json.gz, so the lists can be
built and re-checked offline. Run from the Actions tab: this needs Wikipedia.
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
    # Starting XI: articles with the line-ups of the matches being added.
    "2008 FA Cup final",
    "2011 Football League Cup final",
    "2013 Football League Cup final",
    "2025 EFL Cup final",
    "2026 EFL Cup final",
    "UEFA Euro 2004 Group A",
    "UEFA Euro 1996 Group A",
    "UEFA Euro 2016 knockout stage",
    "UEFA Euro 2020 knockout stage",
    "2018 FIFA World Cup Group G",
    "2017–18 UEFA Champions League knockout phase",
    "2003–04 Arsenal F.C. season",
    "2020–21 Manchester United F.C. season",
    "2022–23 Liverpool F.C. season",
    "Liverpool F.C. 7–0 Manchester United F.C.",
    "UEFA Euro 2024 knockout stage",
    "UEFA Euro 2004 Group B",
    "UEFA Euro 2016 Group F",
    "2002 FIFA World Cup Group F",
    "2018 FIFA World Cup knockout stage",
    "Germany v England (2016)",
    "Northern Ireland 3–2 Spain (2006)",
]


def main() -> int:
    pages = wikitext(ARTICLES)
    # Every linked article's Wikidata id, so players match the career data.
    linked = sorted({m.strip().replace("_", " ") for t in pages.values() for m in LINK.findall(t) if ":" not in m})
    qids = club_qids(linked)
    with gzip.open(RAW / "radar_wikitext.json.gz", "wt", encoding="utf-8") as f:
        json.dump({"pages": pages, "qids": qids}, f, ensure_ascii=False)
    missing = [t for t in ARTICLES if t not in pages]
    print(f"fetched {len(pages)} of {len(ARTICLES)} articles; {len(qids)} linked ids; missing: {missing}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
