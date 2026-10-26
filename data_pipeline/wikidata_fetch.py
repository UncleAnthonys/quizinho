"""Download raw footballer data from Wikidata (CC0 — free for commercial use).

    python3 data_pipeline/wikidata_fetch.py [--min-sitelinks 15]

Runs in GitHub Actions (.github/workflows/fetch-data.yml) because the dev
workspace can't reach query.wikidata.org. Standard library only.

Writes gzipped JSON to data_pipeline/raw/:
  players.json.gz  id, name, sitelinks, dob, nationalities, positions,
                   family names, English aliases, IPA pronunciations
  spells.json.gz   every P54 "member of sports team" statement for those
                   players, with start/end, apps, goals, acquisition type
  clubs.json.gz    every team referenced: label, aliases, types (P31),
                   country, sitelinks

Raw = unfiltered. data_pipeline/normalise.py decides what counts.

Strategy: one small query per sitelinks band to list players (avoids the
60-second query timeout), then details and spells in batches of ids.
"""

from __future__ import annotations

import argparse
import gzip
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ENDPOINT = "https://query.wikidata.org/sparql"
UA = "QuizinhoDataPipeline/0.2 (https://github.com/UncleAnthonys/quizinho; football party game)"
OUT = pathlib.Path(__file__).resolve().parent / "raw"

# Sitelinks bands queried separately so each list query stays fast.
BANDS = [(15, 19), (20, 29), (30, 49), (50, 99), (100, 10_000)]
BATCH = 150


def sparql(query: str, tries: int = 6) -> list[dict]:
    data = urllib.parse.urlencode({"query": query, "format": "json"}).encode()
    for attempt in range(tries):
        req = urllib.request.Request(
            ENDPOINT, data=data,
            headers={"User-Agent": UA, "Accept": "application/sparql-results+json",
                     "Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                # strict=False: some labels contain raw control characters
                return json.loads(r.read().decode("utf-8"), strict=False)["results"]["bindings"]
        except urllib.error.HTTPError as e:
            wait = int(e.headers.get("Retry-After", 0) or 0) or 5 * (attempt + 1)
            print(f"  HTTP {e.code}, retry in {wait}s", flush=True)
            time.sleep(wait)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"  {type(e).__name__}: {e}, retrying", flush=True)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError("query failed repeatedly:\n" + query[:400])


def qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def val(b: dict, key: str) -> str | None:
    return b[key]["value"] if key in b else None


def num(v: str | None) -> int | None:
    """Integer qualifier value, or None for 'unknown value' blank nodes and junk."""
    try:
        return int(float(v)) if v is not None else None
    except ValueError:
        return None


def chunks(xs: list, n: int):
    for i in range(0, len(xs), n):
        yield xs[i:i + n]


def values(ids: list[str]) -> str:
    return " ".join(f"wd:{i}" for i in ids)


def list_players(lo: int, hi: int) -> dict[str, dict]:
    rows = sparql(f"""
SELECT ?p ?pLabel ?sl WHERE {{
  ?p wdt:P106 wd:Q937857 ; wikibase:sitelinks ?sl .
  FILTER(?sl >= {lo} && ?sl <= {hi})
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul,es,pt,fr,de,it". }}
}}""")
    return {qid(r["p"]["value"]): {"id": qid(r["p"]["value"]), "name": val(r, "pLabel"), "sitelinks": num(val(r, "sl")) or 0}
            for r in rows}


def player_details(players: dict[str, dict]) -> None:
    ids = list(players)
    for n, batch in enumerate(chunks(ids, BATCH)):
        rows = sparql(f"""
SELECT ?p ?dob ?nat ?pos ?posLabel ?famLabel ?alias ?ipa WHERE {{
  VALUES ?p {{ {values(batch)} }}
  OPTIONAL {{ ?p wdt:P569 ?dob }}
  OPTIONAL {{ ?p wdt:P1532 ?nat }}
  OPTIONAL {{ ?p wdt:P413 ?pos }}
  OPTIONAL {{ ?p wdt:P734 ?fam }}
  OPTIONAL {{ ?p skos:altLabel ?alias FILTER(LANG(?alias) = "en") }}
  OPTIONAL {{ ?p wdt:P898 ?ipa }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul". }}
}}""")
        for r in rows:
            p = players[qid(r["p"]["value"])]
            if (d := val(r, "dob")):
                p["dob"] = d[:10]
            for key, field in (("nat", "nationalities"), ("posLabel", "positions"),
                               ("famLabel", "family_names"), ("alias", "aliases"), ("ipa", "ipa")):
                v = val(r, key)
                if v:
                    v = qid(v) if key == "nat" else v
                    lst = p.setdefault(field, [])
                    if v not in lst:
                        lst.append(v)
        if n % 20 == 0:
            print(f"  details {min((n + 1) * BATCH, len(ids))}/{len(ids)}", flush=True)
        time.sleep(0.3)


def player_spells(ids: list[str]) -> list[dict]:
    out: dict[str, dict] = {}
    for n, batch in enumerate(chunks(ids, BATCH)):
        rows = sparql(f"""
SELECT ?p ?st ?team ?start ?end ?apps ?goals ?acq WHERE {{
  VALUES ?p {{ {values(batch)} }}
  ?p p:P54 ?st . ?st ps:P54 ?team .
  OPTIONAL {{ ?st pq:P580 ?start }}
  OPTIONAL {{ ?st pq:P582 ?end }}
  OPTIONAL {{ ?st pq:P1350 ?apps }}
  OPTIONAL {{ ?st pq:P1351 ?goals }}
  OPTIONAL {{ ?st pq:P1642 ?acq }}
}}""")
        for r in rows:
            sid = r["st"]["value"]
            s = out.setdefault(sid, {
                "player": qid(r["p"]["value"]), "team": qid(r["team"]["value"]),
                "start": None, "end": None, "apps": None, "goals": None, "acq": [],
            })
            if (v := val(r, "start")):
                s["start"] = s["start"] or v[:10]
            if (v := val(r, "end")):
                s["end"] = s["end"] or v[:10]
            if s["apps"] is None:
                s["apps"] = num(val(r, "apps"))
            if s["goals"] is None:
                s["goals"] = num(val(r, "goals"))
            if (v := val(r, "acq")) and qid(v) not in s["acq"]:
                s["acq"].append(qid(v))
        if n % 20 == 0:
            print(f"  spells {min((n + 1) * BATCH, len(ids))}/{len(ids)}", flush=True)
        time.sleep(0.3)
    return list(out.values())


def club_info(team_ids: list[str]) -> dict[str, dict]:
    clubs: dict[str, dict] = {}
    for n, batch in enumerate(chunks(team_ids, BATCH)):
        rows = sparql(f"""
SELECT ?t ?tLabel ?sl ?type ?country ?alias WHERE {{
  VALUES ?t {{ {values(batch)} }}
  OPTIONAL {{ ?t wikibase:sitelinks ?sl }}
  OPTIONAL {{ ?t wdt:P31 ?type }}
  OPTIONAL {{ ?t wdt:P17 ?country }}
  OPTIONAL {{ ?t skos:altLabel ?alias FILTER(LANG(?alias) = "en") }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul,es,pt,fr,de,it". }}
}}""")
        for r in rows:
            t = clubs.setdefault(qid(r["t"]["value"]), {
                "id": qid(r["t"]["value"]), "name": val(r, "tLabel"), "sitelinks": 0,
                "types": [], "country": None, "aliases": [],
            })
            if (v := num(val(r, "sl"))) is not None:
                t["sitelinks"] = v
            if (v := val(r, "type")) and qid(v) not in t["types"]:
                t["types"].append(qid(v))
            if (v := val(r, "country")):
                t["country"] = t["country"] or qid(v)
            if (v := val(r, "alias")) and v not in t["aliases"]:
                t["aliases"].append(v)
        if n % 20 == 0:
            print(f"  clubs {min((n + 1) * BATCH, len(team_ids))}/{len(team_ids)}", flush=True)
        time.sleep(0.3)
    return clubs


def country_info(country_ids: list[str]) -> dict[str, dict]:
    """Name + FIFA/ISO codes for every country referenced (for nationality labels)."""
    out: dict[str, dict] = {}
    for batch in chunks(country_ids, BATCH):
        rows = sparql(f"""
SELECT ?c ?cLabel ?fifa ?iso3 WHERE {{
  VALUES ?c {{ {values(batch)} }}
  OPTIONAL {{ ?c wdt:P3441 ?fifa }}
  OPTIONAL {{ ?c wdt:P298 ?iso3 }}
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en,mul". }}
}}""")
        for r in rows:
            c = out.setdefault(qid(r["c"]["value"]), {"id": qid(r["c"]["value"]), "name": val(r, "cLabel")})
            if (v := val(r, "fifa")):
                c.setdefault("fifa", v)
            if (v := val(r, "iso3")):
                c.setdefault("iso3", v)
        time.sleep(0.3)
    return out


def load(name: str):
    with gzip.open(OUT / f"{name}.json.gz", "rt", encoding="utf-8") as f:
        return json.load(f)


def save(name: str, obj) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.json.gz"
    with gzip.open(path, "wt", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print(f"wrote {path.name} ({path.stat().st_size // 1024} KB)", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-sitelinks", type=int, default=15)
    ap.add_argument("--countries-only", action="store_true", help="only (re)fetch countries for an existing dump")
    args = ap.parse_args()
    t0 = time.time()

    if args.countries_only:
        players, clubs = load("players"), load("clubs")
        ids = {n for p in players for n in p.get("nationalities", [])} | {c["country"] for c in clubs if c.get("country")}
        save("countries", sorted(country_info(sorted(ids)).values(), key=lambda c: c["id"]))
        return 0

    players: dict[str, dict] = {}
    for lo, hi in BANDS:
        if hi < args.min_sitelinks:
            continue
        got = list_players(max(lo, args.min_sitelinks), hi)
        print(f"players with {lo}-{hi} sitelinks: {len(got)}", flush=True)
        players.update(got)
    print(f"total players: {len(players)}", flush=True)

    player_details(players)
    spells = player_spells(sorted(players))
    print(f"spells: {len(spells)}", flush=True)
    clubs = club_info(sorted({s["team"] for s in spells}))
    print(f"teams: {len(clubs)}", flush=True)

    save("players", sorted(players.values(), key=lambda p: p["id"]))
    save("spells", sorted(spells, key=lambda s: (s["player"], s["start"] or "", s["team"])))
    save("clubs", sorted(clubs.values(), key=lambda c: c["id"]))
    country_ids = {n for p in players.values() for n in p.get("nationalities", [])} | {
        c["country"] for c in clubs.values() if c.get("country")}
    save("countries", sorted(country_info(sorted(country_ids)).values(), key=lambda c: c["id"]))
    (OUT / "FETCHED.txt").write_text(
        f"fetched {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}; "
        f"players={len(players)} spells={len(spells)} teams={len(clubs)} "
        f"min_sitelinks={args.min_sitelinks} took={int(time.time() - t0)}s\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
