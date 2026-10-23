"""Fetch player → club career data from Wikidata (CC0, free for commercial use).

    pip install requests
    python3 data_pipeline/wikidata_fetch.py --min-sitelinks 40 --out data_pipeline/raw/wikidata_careers.json

STATUS: written but not yet run — the build workspace couldn't reach
query.wikidata.org. Run it locally or in CI; expect to tune the threshold.

What it pulls, per player (P106 = association football player):
  * every P54 "member of sports team" statement whose team is an
    association football club (Q476028), with start (P580), end (P582)
    and matches played (P1350) qualifiers
  * sitelink count as a fame proxy (more Wikipedia languages = more famous)

What the next step (normalise.py, Phase 2) must do with it:
  * drop youth / reserve / B teams (label filter below is a first pass)
  * drop spells with P1350 == 0 (signed but never played)
  * flag spells with no P1350 for review rather than trusting them
  * map Wikidata clubs to our club IDs + aliases
  * order spells by start date; mark loans (P54 qualifier P1642 "acquisition
    transaction" = loan, where present)
  * write seed/players.json in the same shape as the demo seed, verified=1
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import time

QUERY = """
SELECT ?player ?playerLabel ?sitelinks ?team ?teamLabel ?start ?end ?apps WHERE {
  ?player wdt:P106 wd:Q937857 ;
          wikibase:sitelinks ?sitelinks .
  FILTER(?sitelinks >= %(min_sitelinks)d)
  ?player p:P54 ?st .
  ?st ps:P54 ?team .
  ?team wdt:P31 wd:Q476028 .
  OPTIONAL { ?st pq:P580 ?start }
  OPTIONAL { ?st pq:P582 ?end }
  OPTIONAL { ?st pq:P1350 ?apps }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "QuizinhoDataPipeline/0.1 (football party game; contact via app support page)"

# First-pass filter for non-senior sides that slip through as "clubs".
NON_SENIOR = re.compile(
    r"\b(U-?\d{2}|Under-?\d{2}|II|B|Reserves?|Youth|Academy|Juvenil|Castilla|Atl[eè]tic|Primavera|Jong)\b",
    re.IGNORECASE,
)


def qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def year(value: str | None) -> int | None:
    return int(value[:4]) if value and value[:4].lstrip("-").isdigit() else None


def main() -> None:
    import requests  # imported here so --help works without it

    ap = argparse.ArgumentParser()
    ap.add_argument("--min-sitelinks", type=int, default=40)
    ap.add_argument("--out", default="data_pipeline/raw/wikidata_careers.json")
    args = ap.parse_args()

    t0 = time.time()
    r = requests.get(
        ENDPOINT,
        params={"query": QUERY % {"min_sitelinks": args.min_sitelinks}, "format": "json"},
        headers={"User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"},
        timeout=300,
    )
    r.raise_for_status()
    rows = r.json()["results"]["bindings"]

    players: dict[str, dict] = {}
    dropped = 0
    for b in rows:
        team_label = b["teamLabel"]["value"]
        if NON_SENIOR.search(team_label):
            dropped += 1
            continue
        pid = qid(b["player"]["value"])
        p = players.setdefault(pid, {
            "wikidata_id": pid,
            "name": b["playerLabel"]["value"],
            "sitelinks": int(b["sitelinks"]["value"]),
            "spells": [],
        })
        p["spells"].append({
            "club_wikidata_id": qid(b["team"]["value"]),
            "club_label": team_label,
            "start": year(b.get("start", {}).get("value")),
            "end": year(b.get("end", {}).get("value")),
            "apps": int(float(b["apps"]["value"])) if "apps" in b else None,
        })

    for p in players.values():
        p["spells"].sort(key=lambda s: (s["start"] is None, s["start"] or 0))

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(list(players.values()), ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(players)} players, {len(rows)} rows, {dropped} non-senior spells dropped, "
          f"{time.time() - t0:.0f}s → {out}")


if __name__ == "__main__":
    main()
