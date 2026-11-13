"""Players the main Wikidata fetch misses, merged into raw/players, spells,
clubs and countries (.json.gz) so normalise.py treats them like the rest.

    python3 data_pipeline/players_extra_fetch.py

1. Footballers our Wikipedia record pages and cup finals link to who aren't
   in the dump (Matthaus, Wenger: the band query only finds people whose
   occupation is a plain "association football player" statement).
2. Lesser-known players (5-14 Wikipedia pages) who played for a Premier
   League club (seed/pl_clubs.json): the 90s squad players.
3. Everyone who has played a Premier League match (raw/pl_matches.json.gz)
   but isn't in seed/players.json: found on Wikidata by birth date and name,
   and given their Wikipedia career (below) even if Wikidata has one, since
   Wikidata's was too thin to keep them (Kluivert, Podence).
4. Senior careers (and national teams) from the English Wikipedia infobox for
   players Wikidata has no dated clubs for (Kroupi), and for those in 3.
   Saved as spells with "src": "enwiki", replacing that player's Wikidata
   spells; a re-run replaces them.

Runs in GitHub Actions (.github/workflows/players-extra.yml): the dev
workspace can't reach Wikidata or Wikipedia. Standard library only.
"""

from __future__ import annotations

import datetime as dt
import gzip
import json
import pathlib
import re
import time
import unicodedata

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


def fold(t: str | None) -> str:
    return unicodedata.normalize("NFKD", t or "").encode("ascii", "ignore").decode().lower()


def name_words(*names: str) -> set[str]:
    return {w for n in names for w in re.findall(r"[a-z]+", fold(n)) if len(w) > 2}


def same_person(name: str, dob: str, cand_names: list[str], cand_dob: str | None) -> bool:
    """Same birth date and a shared name word; or the same full name born
    within a year (sources swap day and month, or slip a day)."""
    if not cand_dob:
        return False
    if cand_dob == dob:
        return bool(name_words(name) & name_words(*cand_names))
    return abs(int(cand_dob[:4]) - int(dob[:4])) <= 1 and any(fold(name) == fold(c) for c in cand_names)


def pl_people() -> list[tuple[str, str]]:
    """(name, birth date) of everyone with a Premier League appearance."""
    path = RAW / "pl_matches.json.gz"
    if not path.exists():
        return []
    with gzip.open(path, "rt", encoding="utf-8") as f:
        d = json.load(f)
    played = set()
    for m in d["matches"]:
        on = {e[2] for e in m["events"] if e[0] == "S" and e[1] == "ON"}
        for rows in m["lineups"].values():
            played |= {str(pid) for pid, _, start in rows if start or pid in on}
    out = []
    for pid in played:
        name, millis, _ = d["people"][pid]
        if millis is not None:
            out.append((name, dt.datetime.fromtimestamp(millis / 1000, dt.timezone.utc).date().isoformat()))
    return out


def by_birth_date(dates: list[str]) -> dict[str, list[dict]]:
    """Footballers on Wikidata born on these dates: {date: [{id, name, aliases, sitelinks}]}."""
    out: dict[str, list[dict]] = {}
    for batch in wd.chunks(dates, 40):
        vals = " ".join(f'"{d}T00:00:00Z"^^xsd:dateTime' for d in batch)
        rows = wd.sparql(f"""
SELECT ?p ?pLabel ?d ?sl (GROUP_CONCAT(DISTINCT ?alias; SEPARATOR="|") AS ?aliases) WHERE {{
  VALUES ?d {{ {vals} }}
  ?p wdt:P569 ?d ; wdt:P106 wd:{FOOTBALLER} ; wikibase:sitelinks ?sl .
  OPTIONAL {{ ?p skos:altLabel ?alias FILTER(LANG(?alias) = "en") }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul". }}
}} GROUP BY ?p ?pLabel ?d ?sl""")
        for r in rows:
            out.setdefault(wd.val(r, "d")[:10], []).append({
                "id": wd.qid(r["p"]["value"]), "name": wd.val(r, "pLabel"),
                "aliases": [a for a in (wd.val(r, "aliases") or "").split("|") if a],
                "sitelinks": wd.num(wd.val(r, "sl")) or 0})
        time.sleep(0.3)
    return out


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

    # 3. Premier League players we still don't have.
    seed = json.loads((SEED / "players.json").read_text(encoding="utf-8"))["players"]
    seed_q = {p["wikidata"] for p in seed}
    by_dob: dict[str, list[dict]] = {}
    by_name: dict[str, list[dict]] = {}
    for p in players.values():
        if p.get("dob"):
            by_dob.setdefault(p["dob"], []).append(p)
            by_name.setdefault(fold(p.get("name")), []).append(p)
    forced: set[str] = set()
    lost = []
    for name, dob in pl_people():
        hit = next((p for p in by_dob.get(dob, []) if same_person(name, dob, [p.get("name") or "", *p.get("aliases", [])], p.get("dob"))), None)
        if hit is None:
            hit = next((p for p in by_name.get(fold(name), []) if same_person(name, dob, [p["name"]], p["dob"])), None)
        if hit is None:
            lost.append((name, dob))
        elif hit["id"] not in seed_q:
            forced.add(hit["id"])
    print(f"Premier League players: {len(forced)} in the dump but not kept, {len(lost)} not in it", flush=True)
    found = by_birth_date(sorted({d for _, d in lost}))
    for name, dob in lost:
        hit = next((c for c in found.get(dob, []) if same_person(name, dob, [c["name"] or "", *c["aliases"]], dob)), None)
        if hit and hit["id"] not in players:
            new[hit["id"]] = {"id": hit["id"], "name": hit["name"], "sitelinks": hit["sitelinks"]}
            forced.add(hit["id"])
    print(f"  found on Wikidata by birth date: {sum(1 for q in forced if q in new)}", flush=True)
    # The feed's birth date can be wrong (Mick Quinn): search the name, and
    # take the one footballer it finds who played for a Premier League club.
    still = [(name, dob) for name, dob in lost
             if not any(same_person(name, dob, [c["name"] or "", *c["aliases"]], dob) for c in found.get(dob, []))]
    by_name_found = 0
    pl_ids = list(json.loads((SEED / "pl_clubs.json").read_text(encoding="utf-8"))["clubs"])
    for name, dob in still:
        d = wp.get(wp.WIKIDATA, {"action": "wbsearchentities", "search": name, "language": "en", "type": "item", "limit": 7})
        cands = [c["id"] for c in d.get("search", [])]
        if not cands:
            continue
        rows = wd.sparql(f"""
SELECT DISTINCT ?p ?pLabel ?sl WHERE {{
  VALUES ?p {{ {wd.values(cands)} }}
  VALUES ?club {{ {wd.values(pl_ids)} }}
  ?p wdt:P106 wd:{FOOTBALLER} ; wdt:P54 ?club ; wikibase:sitelinks ?sl .
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul". }}
}}""")
        if len(rows) == 1:
            q = wd.qid(rows[0]["p"]["value"])
            if q not in players and q not in new:
                new[q] = {"id": q, "name": wd.val(rows[0], "pLabel"), "sitelinks": wd.num(wd.val(rows[0], "sl")) or 0}
                by_name_found += 1
            forced.add(q)
        time.sleep(0.3)
    print(f"  found on Wikidata by name: {by_name_found} of {len(still)}", flush=True)

    wd.player_details(new)
    new_spells = wd.player_spells(sorted(new))
    players.update(new)
    spells += new_spells

    # 4. Infobox careers: players with no dated club in Wikidata, and the
    # Premier League players above.
    dated = {s["player"] for s in spells if s.get("start")}
    bare = sorted({q for q in players if q not in dated} | forced)
    print(f"players with no dated spell: {len(bare)}", flush=True)
    titles = wp.enwiki_titles(bare)
    texts = wp.wikitext(sorted(set(titles.values())))
    by_player = {q: infobox_spells(texts.get(t, "")) for q, t in titles.items()}
    team_titles = sorted({s["title"] for ss in by_player.values() for s in ss})
    team_qid = wp.club_qids(team_titles)
    added = 0
    # An infobox career replaces a forced player's thin Wikidata one.
    replaced = {q for q, ss in by_player.items() if ss and q in forced}
    spells = [s for s in spells if s["player"] not in replaced]
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
