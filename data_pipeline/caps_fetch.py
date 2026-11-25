"""Every capped player for the Football 501 countries, from 1 cap up.

Wikipedia's "List of X international footballers" pages stop at a cut-off
(Portugal 25+ caps, Brazil 20+...), which left whole score ranges with no
player in them. Every capped player is in "Category:X international
footballers", and his article's infobox has his caps and goals for the
senior team (nationalteamN / nationalcapsN / nationalgoalsN). This reads
them all and writes raw/national_caps.json.gz:

  {"teams": {country: {article title: [caps, goals]}}, "qids": {title: wikidata id}}

radar_build.py merges these under the lists' own numbers. Runs in GitHub
Actions (.github/workflows/caps.yml): the dev workspace can't reach Wikipedia.
"""
from __future__ import annotations

import gzip
import json
import pathlib
import re
import time

from wiki_stats_fetch import ENWIKI, club_qids, get, number, wikitext

RAW = pathlib.Path(__file__).parent / "raw"

# Country -> (categories of its capped players, its senior team articles).
# Germany counts West Germany caps, as the DFB does.
TEAMS = {
    **{c: ([f"{c} international footballers"], [f"{c} national football team"]) for c in (
        "England", "Scotland", "Wales", "Northern Ireland", "Republic of Ireland", "Brazil", "Argentina",
        "France", "Spain", "Portugal", "Netherlands", "Italy")},
    "Germany": (["Germany international footballers", "West Germany international footballers"],
                ["Germany national football team", "West Germany national football team"]),
    "England women's": (["England women's international footballers"], ["England women's national football team"]),
}

TEAM = re.compile(r"\|\s*nationalteam(\d+)\s*=\s*((?:\[\[[^\]]*\]\]|\{\{[^}]*\}\}|[^|\n])*)")
LINK = re.compile(r"\[\[([^\]|#]+)")


def members(category: str) -> list[str]:
    out, cont = [], {}
    while True:
        d = get(ENWIKI, {"action": "query", "list": "categorymembers", "cmtitle": f"Category:{category}",
                         "cmtype": "page", "cmnamespace": 0, "cmlimit": 500, **cont})
        out += [m["title"] for m in d.get("query", {}).get("categorymembers", [])]
        if "continue" not in d:
            return out
        cont = {"cmcontinue": d["continue"]["cmcontinue"]}
        time.sleep(0.2)


def caps_for(text: str, teams: list[str]) -> tuple[int, int] | None:
    """Caps and goals for these senior teams (summed: West Germany + Germany)."""
    want = {t.lower() for t in teams}
    caps = goals = 0
    found = False
    for n, val in TEAM.findall(text):
        link = LINK.search(val)
        if not link or link.group(1).strip().replace("_", " ").lower() not in want:
            continue
        c = number((re.search(rf"\|\s*nationalcaps{n}\s*=\s*([^|\n]*)", text) or [None, ""])[1])
        g = number((re.search(rf"\|\s*nationalgoals{n}\s*=\s*([^|\n]*)", text) or [None, ""])[1])
        if c:
            caps += c
            goals += g or 0
            found = True
    return (caps, goals) if found else None


def main() -> int:
    out: dict[str, dict[str, list[int]]] = {}
    for country, (cats, teams) in TEAMS.items():
        titles = sorted({t for c in cats for t in members(c)})
        pages = wikitext(titles)
        got = {}
        for t, text in pages.items():
            v = caps_for(text, teams)
            if v:
                got[t] = list(v)
        out[country] = got
        print(f"{country}: {len(titles)} in the category, {len(got)} with caps; "
              f"{sum(1 for c, _ in got.values() if c < 10)} under 10 caps")
    qids = club_qids(sorted({t for g in out.values() for t in g}))
    with gzip.open(RAW / "national_caps.json.gz", "wt", encoding="utf-8") as f:
        json.dump({"teams": out, "qids": qids}, f, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
