"""Fill gaps in league apps/goals from English Wikipedia infoboxes.

    python3 data_pipeline/wiki_stats_fetch.py [--min-fame 1] [--limit N]

Wikidata often has a player's clubs but not the appearances/goals qualifiers
(Maldini at Milan, Bertrand Traoré at Lyon), so Football 501 can't use them.
The "Infobox football biography" on English Wikipedia lists senior league
apps and goals per club (clubsN / capsN / goalsN). This reads those for every
spell in seed/players.json that has no numbers yet, resolves each club link
to its Wikidata id, and writes:

  seed/wiki_stats.json   {"players": {player_id: {club_qid: [apps, goals]}}}

build_db.py uses these only where Wikidata has nothing. Runs in GitHub Actions
(.github/workflows/fetch-wiki-stats.yml): the dev workspace can't reach
Wikipedia. Standard library only.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
SEED = ROOT / "seed"
UA = "QuizinhoDataPipeline/0.3 (https://github.com/UncleAnthonys/quizinho; football party game)"
WIKIDATA = "https://www.wikidata.org/w/api.php"
ENWIKI = "https://en.wikipedia.org/w/api.php"
BATCH = 50

PARAM = re.compile(r"\|\s*(clubs|caps|goals)(\d+)\s*=\s*((?:\[\[[^\]]*\]\]|\{\{[^}]*\}\}|[^|\n])*)")
LINK = re.compile(r"\[\[([^\]|#]+)")
NUMBER = re.compile(r"^\D{0,3}?(\d+)")


def get(url: str, params: dict) -> dict:
    q = urllib.parse.urlencode({**params, "format": "json", "formatversion": 2})
    for attempt in range(6):
        try:
            req = urllib.request.Request(f"{url}?{q}", headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            wait = 5 * (attempt + 1)
            print(f"  retry in {wait}s: {e}", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"gave up on {url}")


def chunks(items: list, n: int = BATCH):
    for i in range(0, len(items), n):
        yield items[i:i + n]


def enwiki_titles(qids: list[str]) -> dict[str, str]:
    """Wikidata id → English Wikipedia article title."""
    out = {}
    for batch in chunks(qids):
        d = get(WIKIDATA, {"action": "wbgetentities", "ids": "|".join(batch), "props": "sitelinks",
                           "sitefilter": "enwiki"})
        for qid, e in d.get("entities", {}).items():
            link = (e.get("sitelinks") or {}).get("enwiki")
            if link:
                out[qid] = link["title"]
        time.sleep(0.2)
    return out


def resolve(d: dict) -> dict[str, str]:
    """Requested title → final title, following normalisation and redirects."""
    step = {}
    for n in d.get("query", {}).get("normalized", []):
        step[n["from"]] = n["to"]
    for r in d.get("query", {}).get("redirects", []):
        step[r["from"]] = r["to"]

    def final(t: str) -> str:
        seen = set()
        while t in step and t not in seen:
            seen.add(t)
            t = step[t]
        return t
    return {t: final(t) for t in step}


def wikitext(titles: list[str]) -> dict[str, str]:
    """Requested title → page wikitext."""
    out = {}
    for batch in chunks(titles):
        d = get(ENWIKI, {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
                         "redirects": 1, "titles": "|".join(batch)})
        hop = resolve(d)
        pages = {p["title"]: p for p in d.get("query", {}).get("pages", [])}
        for t in batch:
            p = pages.get(hop.get(t, t))
            revs = (p or {}).get("revisions") or []
            if revs:
                out[t] = revs[0]["slots"]["main"]["content"]
        time.sleep(0.2)
    return out


def club_qids(titles: list[str]) -> dict[str, str]:
    """Club article title → Wikidata id."""
    out = {}
    for batch in chunks(titles):
        d = get(ENWIKI, {"action": "query", "prop": "pageprops", "ppprop": "wikibase_item", "redirects": 1,
                         "titles": "|".join(batch)})
        hop = resolve(d)
        pages = {p["title"]: p for p in d.get("query", {}).get("pages", [])}
        for t in batch:
            p = pages.get(hop.get(t, t))
            q = ((p or {}).get("pageprops") or {}).get("wikibase_item")
            if q:
                out[t] = q
        time.sleep(0.2)
    return out


def number(s: str) -> int | None:
    s = re.sub(r"<ref[^>]*/>|<ref.*?</ref>|\{\{.*?\}\}|'''?", "", s).strip()
    m = NUMBER.match(s)
    return int(m.group(1)) if m else None


def infobox_rows(text: str) -> list[tuple[str, int | None, int | None]]:
    """[(club article title, apps, goals)] from the senior-career rows."""
    params: dict[tuple[str, str], str] = {}
    for kind, n, val in PARAM.findall(text):
        params.setdefault((kind, n), val.strip())
    rows = []
    for (kind, n), val in sorted(params.items(), key=lambda kv: int(kv[0][1])):
        if kind != "clubs":
            continue
        link = LINK.search(val)
        if not link:
            continue
        title = link.group(1).strip().replace("_", " ")
        title = title[:1].upper() + title[1:]
        rows.append((title, number(params.get(("caps", n), "")), number(params.get(("goals", n), ""))))
    return rows


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-fame", type=int, default=1)
    ap.add_argument("--limit", type=int, default=0, help="only the first N players (testing)")
    args = ap.parse_args()

    players = json.loads((SEED / "players.json").read_text())["players"]
    todo = {}
    for p in players:
        if p.get("fame", 0) < args.min_fame or not p.get("wikidata"):
            continue
        have = set((p.get("stats") or {}).keys())
        missing = {e[0] for e in p.get("career", [])} - have
        if missing:
            todo[p["id"]] = (p["wikidata"], missing)
    fame = {p["id"]: p.get("fame", 0) for p in players}
    ids = sorted(todo, key=lambda pid: (-fame[pid], pid))
    if args.limit:
        ids = ids[:args.limit]
    print(f"{len(ids)} players with spells lacking apps/goals")

    titles = enwiki_titles([todo[pid][0] for pid in ids])
    print(f"{len(titles)} have an English Wikipedia article")
    pages = wikitext(sorted(set(titles.values())))
    print(f"{len(pages)} pages fetched")

    rows_by_player = {}
    club_titles = set()
    for pid in ids:
        text = pages.get(titles.get(todo[pid][0], ""), "")
        rows = infobox_rows(text)
        if rows:
            rows_by_player[pid] = rows
            club_titles.update(t for t, _, _ in rows)
    print(f"{len(rows_by_player)} infoboxes with career rows; {len(club_titles)} club links")
    clubs = club_qids(sorted(club_titles))

    out: dict[str, dict[str, list[int]]] = {}
    for pid, rows in rows_by_player.items():
        missing = todo[pid][1]
        per_club: dict[str, list[int]] = {}
        for title, apps, goals in rows:
            q = clubs.get(title)
            if q in missing and apps is not None:
                a = per_club.setdefault(q, [0, 0])
                a[0] += apps
                a[1] += goals or 0
        per_club = {q: v for q, v in per_club.items() if v[0] > 0}
        if per_club:
            out[pid] = dict(sorted(per_club.items()))

    filled = sum(len(v) for v in out.values())
    wanted = sum(len(todo[pid][1]) for pid in ids)
    note = (f"League apps/goals from English Wikipedia infoboxes, only for spells Wikidata has no numbers for. "
            f"{filled} of {wanted} missing spells filled, {len(out)} players. "
            f"Fetched {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}.")
    print(note)
    doc = {"_note": note, "players": dict(sorted(out.items()))}
    (SEED / "wiki_stats.json").write_text(
        "{\n" + f'  "_note": {json.dumps(note)},\n  "players": {{\n'
        + ",\n".join(f"    {json.dumps(pid)}: {json.dumps(v, ensure_ascii=False)}" for pid, v in doc["players"].items())
        + "\n  }\n}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
