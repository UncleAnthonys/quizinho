"""All-time and by-decade Premier League player rankings from the stats feed
premierleague.com's own pages use (goals, own goals, cards, headers...),
saved raw to raw/pl_stats.json.gz for top10_build.py to read offline.

    python3 data_pipeline/pl_stats_fetch.py

Runs in GitHub Actions (.github/workflows/pl-stats.yml): the dev workspace
can't reach the feed. Standard library only. Detailed stats (headers, free
kicks, outside the box) are only tracked from 2006-07.
"""
from __future__ import annotations

import gzip
import json
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

RAW = pathlib.Path(__file__).resolve().parent / "raw"
API = "https://footballapi.pulselive.com/football"
HEADERS = {"Origin": "https://www.premierleague.com", "Referer": "https://www.premierleague.com/",
           "User-Agent": "Mozilla/5.0 (QuizinhoDataPipeline; football party game)", "Accept": "application/json"}

# stat -> how deep to go (deep ones feed nationality / position lists).
STATS = {"goals": 1500, "goal_assist": 800, "appearances": 800, "own_goals": 100, "red_card": 100,
         "yellow_card": 100, "att_hd_goal": 300, "att_freekick_goal": 100, "att_obox_goal": 300,
         "att_pen_goal": 100, "clean_sheet": 600}
DECADE_STATS = ["goals", "goal_assist", "appearances"]


def get(path: str, params: dict) -> dict:
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    for attempt in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"  retry {attempt + 1}: {e}", flush=True)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"gave up on {url}")


def ranked(stat: str, depth: int, seasons: list[int] | None = None) -> list[dict]:
    rows, page = [], 0
    while len(rows) < depth:
        params = {"page": page, "pageSize": 100, "comps": 1, "compCodeForActivePlayer": "EN_PR", "altIds": "true"}
        if seasons:
            params["compSeasons"] = ",".join(str(s) for s in seasons)
        content = get(f"stats/ranked/players/{stat}", params)["stats"]["content"]
        if not content:
            break
        rows += content
        page += 1
        time.sleep(0.3)
    return rows[:depth]


def main() -> int:
    seasons = get("competitions/1/compseasons", {"page": 0, "pageSize": 100})["content"]
    by_start = {}
    for s in seasons:
        label = s["label"].split()[-1]  # "2025/26" or "Season 2026/2027" -> "2026/2027"
        by_start[int(label[:4])] = int(s["id"])
    decades = {f"{d}s": [i for y, i in by_start.items() if d <= y < d + 10 and y <= 2025]
               for d in (1990, 2000, 2010, 2020)}
    out = {"seasons": by_start, "all": {}, "decades": {}}
    for stat, depth in STATS.items():
        out["all"][stat] = ranked(stat, depth)
        print(f"{stat}: {len(out['all'][stat])}", flush=True)
    for name, ids in decades.items():
        out["decades"][name] = {stat: ranked(stat, 300, ids) for stat in DECADE_STATS}
        print(f"{name}: {len(ids)} seasons", flush=True)
    with gzip.open(RAW / "pl_stats.json.gz", "wt", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
