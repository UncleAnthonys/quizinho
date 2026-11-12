"""Players the main Wikidata fetch misses, merged into raw/players, spells,
clubs and countries (.json.gz) so normalise.py treats them like the rest.

    python3 data_pipeline/players_extra_fetch.py

1. Footballers our Wikipedia record pages and cup finals link to who aren't
   in the dump (Matthaus, Wenger: the band query only finds people whose
   occupation is a plain "association football player" statement).
2. Lesser-known players (5-14 Wikipedia pages) who played for a Premier
   League club (seed/pl_clubs.json): the 90s squad players.
3. Senior careers (and national teams) from the English Wikipedia infobox for
   players Wikidata has no dated clubs for (Kroupi). Saved as spells with
   "src": "enwiki"; a re-run replaces them.

Runs in GitHub Actions (.github/workflows/players-extra.yml): the dev
workspace can't reach Wikidata or Wikipedia. Standard library only.
"""

from __future__ import annotations

import gzip
import json
import pathlib
import re
import time

import wikidata_fetch as wd
import wiki_stats_fetch as wp

ROOT = pathlib.Path(__file__).resolve().parent
RAW, SEED = ROOT / "raw", ROOT / "seed"
FOOTBALLER, MANAGER, HUMAN = "Q937857", "Q628099", "Q5"
LOAN = "Q2914547"

INFOBOX = re.compile(
    r"\|\s*(years|clubs|caps|goals|nationalyears|nationalteam|nationalcaps|nationalgoals)(\d+)\s*=\s*"
    r"((?:\[\[[^\]]*\]\]|\{\{[^}]*\}\}|[^|\n])*)")
YEAR = re.compile(r"(1[89]\d\d|20\d\d)")


def linked_qids() -> set[str]:
    out: set[str] = set()
    for name in ("lists_wikitext", "finals_wikitext"):
        path = RAW / f"{name}.json.gz"
        if path.exists():
            with gzip.open(path, "rt", encoding="utf-8") as f:
                out |= set(json.load(f).get("qids", {}).values())
    return out


def footballers_among(qids: list[str]) -> dict[str, dict]:
    """Of these ids, the people who played or managed football."""
    out: dict[str, dict] = {}
    for n, batch in enumerate(wd.chunks(qids, wd.BATCH)):
        rows = wd.sparql(f"""
SELECT DISTINCT ?p ?pLabel ?sl WHERE {{
  VALUES ?p {{ {wd.values(batch)} }}
  ?p wdt:P31 wd:{HUMAN} ; wikibase:sitelinks ?sl .
  {{ ?p p:P106/ps:P106 wd:{FOOTBALLER} }} UNION {{ ?p p:P106/ps:P106 wd:{MANAGER} }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul,es,pt,fr,de,it". }}
}}""")
        for r in rows:
            q = wd.qid(r["p"]["value"])
            out[q] = {"id": q, "name": wd.val(r, "pLabel"), "sitelinks": wd.num(wd.val(r, "sl")) or 0}
        if n % 10 == 0:
            print(f"  linked {min((n + 1) * wd.BATCH, len(qids))}/{len(qids)}: {len(out)} footballers", flush=True)
        time.sleep(0.3)
    return out


def club_squad(club: str, lo: int = 5, hi: int = 14) -> dict[str, dict]:
    rows = wd.sparql(f"""
SELECT DISTINCT ?p ?pLabel ?sl WHERE {{
  ?p wdt:P54 wd:{club} ; wdt:P106 wd:{FOOTBALLER} ; wikibase:sitelinks ?sl .
  FILTER(?sl >= {lo} && ?sl <= {hi})
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul". }}
}}""")
    return {wd.qid(r["p"]["value"]): {"id": wd.qid(r["p"]["value"]), "name": wd.val(r, "pLabel"),
                                     "sitelinks": wd.num(wd.val(r, "sl")) or 0} for r in rows}


def years(v: str) -> tuple[int, int | None] | None:
    ys = [int(y) for y in YEAR.findall(re.sub(r"<ref.*?(</ref>|/>)", "", v))]
    if not ys:
        return None
    if len(ys) >= 2:
        return ys[0], ys[1]
    return ys[0], (None if re.search(r"[–-]\s*$", v.strip()) else ys[0])


def infobox_spells(text: str) -> list[dict]:
    """Senior career and national teams: [{title, start, end, loan, apps, goals}]."""
    box = text[:text.find("\n}}")] if "\n}}" in text else text
    params: dict[tuple[str, str], str] = {}
    for kind, n, v in INFOBOX.findall(box):
        params.setdefault((kind, n), v.strip())
    out = []
    for prefix in ("", "national"):
        team_key = "nationalteam" if prefix else "clubs"
        for (kind, n), v in sorted(params.items(), key=lambda kv: int(kv[0][1])):
            if kind != team_key:
                continue
            link = wp.LINK.search(v)
            span = years(params.get((f"{prefix}years", n), ""))
            if not link or not span:
                continue
            title = link.group(1).strip().replace("_", " ")
            out.append({"title": title[:1].upper() + title[1:], "start": span[0], "end": span[1],
                        "loan": "→" in v or "loan" in v.lower(),
                        "apps": wp.number(params.get((f"{prefix}caps", n), "")),
                        "goals": wp.number(params.get((f"{prefix}goals", n), ""))})
    return out


def main() -> int:
    t0 = time.time()
    players = {p["id"]: p for p in wd.load("players")}
    spells = [s for s in wd.load("spells") if s.get("src") != "enwiki"]
    clubs = {c["id"]: c for c in wd.load("clubs")}
    countries = {c["id"]: c for c in wd.load("countries")}
    before = len(players)

    # 1. Footballers our record pages link to.
    candidates = sorted(linked_qids() - set(players) - set(clubs) - set(countries))
    print(f"linked ids not in the dump: {len(candidates)}", flush=True)
    new = footballers_among(candidates)
    print(f"linked footballers added: {len(new)}", flush=True)

    # 2. Premier League squad players under the main fetch's bar.
    pl = json.loads((SEED / "pl_clubs.json").read_text(encoding="utf-8"))["clubs"]
    for n, club in enumerate(pl):
        got = {q: p for q, p in club_squad(club).items() if q not in players}
        new.update(got)
        print(f"  {pl[club]}: {len(got)}", flush=True)
        time.sleep(0.5)
    print(f"new players: {len(new)}", flush=True)

    wd.player_details(new)
    new_spells = wd.player_spells(sorted(new))
    players.update(new)
    spells += new_spells

    # 3. Infobox careers for players with no dated club in Wikidata.
    dated = {s["player"] for s in spells if s.get("start")}
    bare = sorted(q for q in players if q not in dated)
    print(f"players with no dated spell: {len(bare)}", flush=True)
    titles = wp.enwiki_titles(bare)
    texts = wp.wikitext(sorted(set(titles.values())))
    by_player = {q: infobox_spells(texts.get(t, "")) for q, t in titles.items()}
    team_titles = sorted({s["title"] for ss in by_player.values() for s in ss})
    team_qid = wp.club_qids(team_titles)
    added = 0
    for q, ss in by_player.items():
        for s in ss:
            team = team_qid.get(s["title"])
            if not team:
                continue
            spells.append({"player": q, "team": team, "start": f"{s['start']}-07-01",
                           "end": f"{s['end']}-06-30" if s["end"] else None,
                           "apps": s["apps"], "goals": s["goals"], "acq": [LOAN] if s["loan"] else [],
                           "src": "enwiki"})
            added += 1
    print(f"infobox spells: {added} for {sum(1 for ss in by_player.values() if ss)} players", flush=True)

    # Teams and countries the new spells and players bring in.
    missing_teams = sorted({s["team"] for s in spells} - set(clubs))
    clubs.update(wd.club_info(missing_teams))
    country_ids = {n for p in players.values() for n in p.get("nationalities", [])} | {
        c["country"] for c in clubs.values() if c.get("country")}
    countries.update(wd.country_info(sorted(country_ids - set(countries))))

    wd.save("players", sorted(players.values(), key=lambda p: p["id"]))
    wd.save("spells", sorted(spells, key=lambda s: (s["player"], s["start"] or "", s["team"])))
    wd.save("clubs", sorted(clubs.values(), key=lambda c: c["id"]))
    wd.save("countries", sorted(countries.values(), key=lambda c: c["id"]))
    with open(RAW / "FETCHED.txt", "a", encoding="utf-8") as f:
        f.write(f"extras {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}: players {before}->{len(players)}, "
                f"infobox spells {added}, teams +{len(missing_teams)}, took={int(time.time() - t0)}s\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
