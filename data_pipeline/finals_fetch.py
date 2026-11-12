"""Fetches the English Wikipedia article of every final the grid's cup-winner
categories use (Champions League, Europa League/UEFA Cup, World Cup, Euros,
FA Cup) and saves the wikitext to raw/finals_wikitext.json.gz, so the line-ups
can be parsed offline (finals_squads.py). Run from the Actions tab: this
needs Wikipedia, which a local sandbox may not reach.
"""
from __future__ import annotations

import gzip
import json
import pathlib

import re

from wiki_stats_fetch import club_qids, wikitext

LINK = re.compile(r"\[\[([^\]|#]+)")

RAW = pathlib.Path(__file__).parent / "raw"


def final_titles() -> dict[str, list[str]]:
    """Competition → Wikipedia titles of its finals (redirects resolve old names)."""
    return {
        "cl": [f"{y} European Cup final" if y < 1993 else f"{y} UEFA Champions League final" for y in range(1956, 2027)],
        "uel": [f"{y} UEFA Cup final" if y < 2010 else f"{y} UEFA Europa League final" for y in range(1972, 2027)],
        "wc": [f"{y} FIFA World Cup final" for y in (1930, 1934, 1938, *range(1950, 2023, 4))],
        "euro": ["1960 European Nations' Cup final", "1964 European Nations' Cup final",
                 *(f"UEFA Euro {y} final" for y in range(1968, 2025, 4))],
        "fac": [f"{y} FA Cup final" for y in range(1946, 2027)],
    }


def main() -> int:
    titles = final_titles()
    pages = wikitext(sorted({t for ts in titles.values() for t in ts}))
    # Every article linked from a line-up row ("|GK ||'''1''' ||[[Dida (footballer...)|Dida]]")
    # or a flag ("{{flagicon|BRA}} [[Cafu]]"), resolved to its Wikidata id so
    # players can be matched without guessing from names.
    linked = sorted({
        m.strip().replace("_", " ") for text in pages.values() for line in text.splitlines()
        if re.match(r"^\|\s*[A-Z]{1,3}\s*\|", line) or "flagicon" in line
        for m in LINK.findall(line) if ":" not in m
    })
    qids = club_qids(linked)
    print(f"linked {len(linked)} articles; {len(qids)} with a Wikidata id")
    out = {"titles": titles, "pages": pages, "qids": qids}
    with gzip.open(RAW / "finals_wikitext.json.gz", "wt", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    missing = [t for ts in titles.values() for t in ts if t not in pages]
    print(f"fetched {len(pages)} finals; missing {len(missing)}: {missing[:20]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
