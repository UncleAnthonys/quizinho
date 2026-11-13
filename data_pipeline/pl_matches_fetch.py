"""Every Premier League match since 1992 from the feed premierleague.com's
own pages use: who started, who came on, who scored (and when), with each
player's birth date. Saved compact to raw/pl_matches.json.gz so Top 10 can
work out youngest/oldest scorers, goals off the bench, goals against a club,
derby goals, relegations and more, offline.

    python3 data_pipeline/pl_matches_fetch.py

Runs in GitHub Actions (.github/workflows/pl-stats.yml, input matches=yes).
Standard library only.
"""
from __future__ import annotations

import concurrent.futures as cf
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


def get(path: str, params: dict | None = None) -> dict:
    url = f"{API}/{path}" + (f"?{urllib.parse.urlencode(params)}" if params else "")
    for attempt in range(8):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ConnectionError) as e:
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"gave up on {url}")


def fixture_ids(season: int) -> list[int]:
    ids, page = [], 0
    while True:
        d = get("fixtures", {"comps": 1, "compSeasons": season, "page": page, "pageSize": 100, "statuses": "C"})
        ids += [int(f["id"]) for f in d["content"]]
        page += 1
        if page >= d["pageInfo"]["numPages"]:
            return ids


def match(fid: int, people: dict) -> dict:
    d = get(f"fixtures/{fid}")
    teams = [[int(t["team"]["id"]), t["team"]["name"], int(t.get("score") or 0)] for t in d["teams"]]
    lineups = {}
    for tl in d.get("teamLists") or []:
        rows = []
        for key, starter in (("lineup", 1), ("substitutes", 0)):
            for p in tl.get(key) or []:
                pid = int(p["id"])
                rows.append([pid, p.get("matchPosition") or "", starter])
                if pid not in people:
                    people[pid] = [p["name"]["display"], (p.get("birth") or {}).get("date", {}).get("millis"),
                                   (p.get("nationalTeam") or {}).get("isoCode")]
        lineups[int(tl["teamId"])] = rows
    events = []
    for e in d.get("events") or []:
        if e.get("personId") is not None and e.get("type") not in ("PS", "PE"):
            # G goal, P penalty goal, O own goal (teamId: the side it counted
            # for), S substitution (ON/OFF), B booking (Y, R, YR); anything
            # else is kept as it comes. Last field: the assist, if any.
            events.append([e["type"], e.get("description") or "", int(e["personId"]), int(e.get("teamId") or 0),
                           int(e["clock"]["secs"]) if e.get("clock") else None,
                           int(e["assistId"]) if e.get("assistId") is not None else None])
    return {"id": fid, "season": d["gameweek"]["compSeason"]["label"], "ko": d["kickoff"].get("millis"),
            "teams": teams, "lineups": lineups, "events": events}


def main() -> int:
    t0 = time.time()
    seasons = get("competitions/1/compseasons", {"page": 0, "pageSize": 100})["content"]
    ids = []
    for s in seasons:
        got = fixture_ids(int(s["id"]))
        ids += got
        print(f"{s['label']}: {len(got)} matches", flush=True)
    people: dict[int, list] = {}
    matches = []
    with cf.ThreadPoolExecutor(max_workers=6) as pool:
        for n, m in enumerate(pool.map(lambda f: match(f, people), ids)):
            matches.append(m)
            if n % 1000 == 0:
                print(f"  {n}/{len(ids)} ({int(time.time() - t0)}s)", flush=True)
    with gzip.open(RAW / "pl_matches.json.gz", "wt", encoding="utf-8") as f:
        json.dump({"people": people, "matches": matches}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(matches)} matches, {len(people)} players, {int(time.time() - t0)}s", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
