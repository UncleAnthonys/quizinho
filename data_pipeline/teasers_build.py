"""Half-Time Teasers: the slow-burn question that runs through a tournament.

    python3 data_pipeline/teasers_build.py            # curated + final scorers (CI)
    python3 data_pipeline/teasers_build.py --offline  # curated only

Two kinds:

  curated  seed/teasers_curated.json, written by hand: "Played in El Clásico,
           the Manchester derby AND the North London derby". Every answer
           has a line-up or match report per fixture in its proof.
  final    "Scored in a Champions League / World Cup final AND played for X".
           Scorers come from each final's Wikipedia article; the club must be
           in both Wikidata and the player's Wikipedia infobox, with league
           games, and the two sources must agree on the whole answer set.

Writes seed/teasers.json. Runs in GitHub Actions (teasers.yml): the dev
workspace can't reach Wikipedia.
"""

from __future__ import annotations

import argparse
import itertools
import json
import pathlib
import random
import re
import time

from build_db import era_mask
from wiki_stats_fetch import LINK, club_qids, enwiki_titles, infobox_rows, wikitext

ROOT = pathlib.Path(__file__).resolve().parent
SEED = ROOT / "seed"

# Clubs a pub table would know, with the name the question uses.
POOL = {
    "Q9617": "Arsenal", "Q9616": "Chelsea", "Q1130849": "Liverpool", "Q18656": "Manchester United",
    "Q50602": "Manchester City", "Q18741": "Tottenham", "Q5794": "Everton", "Q18716": "Newcastle",
    "Q18711": "Aston Villa", "Q18747": "West Ham", "Q18708": "Fulham", "Q1128631": "Leeds",
    "Q19481": "Leicester", "Q18732": "Southampton", "Q18739": "Sunderland", "Q18661": "Middlesbrough",
    "Q19446": "Blackburn", "Q19467": "Crystal Palace", "Q19500": "Wolves", "Q18736": "Stoke",
    "Q19451": "Bolton", "Q19604": "Portsmouth", "Q19490": "Nottingham Forest", "Q19453": "Brighton",
    "Q18723": "QPR", "Q19593": "Celtic", "Q19597": "Rangers",
    "Q8682": "Real Madrid", "Q7156": "Barcelona", "Q8701": "Atlético Madrid", "Q10333": "Valencia",
    "Q10329": "Sevilla", "Q12297": "Villarreal", "Q8723": "Real Betis", "Q8687": "Athletic Bilbao",
    "Q1422": "Juventus", "Q1543": "AC Milan", "Q631": "Inter Milan", "Q2739": "Roma", "Q2609": "Lazio",
    "Q2641": "Napoli", "Q2052": "Fiorentina", "Q1457": "Sampdoria", "Q2693": "Parma", "Q2768": "Torino",
    "Q2798": "Udinese",
    "Q15789": "Bayern Munich", "Q41420": "Borussia Dortmund", "Q104761": "Bayer Leverkusen",
    "Q32494": "Schalke", "Q101859": "Wolfsburg", "Q51976": "Werder Bremen", "Q51974": "Hamburg",
    "Q702455": "RB Leipzig",
    "Q483020": "PSG", "Q132885": "Marseille", "Q704": "Lyon", "Q180305": "Monaco", "Q19516": "Lille",
    "Q81888": "Ajax", "Q11938": "PSV", "Q134241": "Feyenoord",
    "Q128446": "Porto", "Q131499": "Benfica", "Q75729": "Sporting",
    "Q495299": "Galatasaray", "Q6601875": "Fenerbahçe", "Q172567": "Beşiktaş",
    "Q170703": "Boca Juniors", "Q15799": "River Plate", "Q17479": "Flamengo", "Q38568": "São Paulo",
    "Q35933": "Corinthians", "Q204357": "LA Galaxy", "Q16844931": "Inter Miami",
    "Q482764": "Al-Nassr", "Q73965": "Al-Hilal", "Q179075": "Dynamo Kyiv", "Q172969": "Shakhtar Donetsk",
    "Q29108": "Zenit", "Q19628": "Olympiacos",
}

# Well-known clubs beyond POOL: every men's club in the data at fame 4+, plus
# the money moves a table remembers (MLS, Gulf, China, Mexico).
EXTRA = {
    "Q13361030": "New York City FC", "Q327238": "Toronto FC", "Q15214308": "Orlando City",
    "Q308683": "Chicago Fire", "Q632511": "Seattle Sounders", "Q196107": "Vancouver Whitecaps",
    "Q283545": "Al Sadd", "Q1056948": "Al-Duhail", "Q428211": "Al-Gharafa", "Q812720": "Al Ain",
    "Q130521": "Guangzhou Evergrande", "Q564216": "Shanghai SIPG", "Q459090": "Club América",
    "Q768253": "Monterrey", "Q849823": "Tigres", "Q19498": "Sheffield Wednesday", "Q19607": "Sheffield United",
}
TIDY = [(r" (Calcio|Balompié|Paulista|Rotterdam|Istanbul|1909|1913)\b", ""),
        (r"\s*\b(F\.?C\.?|A\.?F\.?C\.?|S\.?K\.?|J\.?K\.?|CFC|BC|UD|S\.?A\.?D\.?)$", ""),
        (r" F\.R\.$", ""),
        (r"^(R\.?S\.?C\.?|GNK|HNK|FK|RC|AS|OGC|CR|SS|U\.?C\.?|ACF|TSG 1899|Sociedade Esportiva) ", ""),
        (r"^Clube Atlético ", "Atlético "), (r"^Tokyo$", "FC Tokyo"),
        (r" de Barcelona$", ""), (r" de Vigo$", " Vigo")]


def tidy(name: str) -> str:
    for pat, sub in TIDY:
        name = re.sub(pat, sub, name).strip()
    return name


def _widen_pool() -> None:
    clubs = json.loads((SEED / "clubs.json").read_text())["clubs"]
    for qid, name, _country, fame, *_rest in clubs:
        if fame >= 4 and _rest[-1] == "m" and qid not in POOL:
            POOL[qid] = tidy(name)
    POOL.update({q: n for q, n in EXTRA.items() if q not in POOL})


_widen_pool()

MIN_FAME = 3  # at least one answer a table could know


def careers_a(players: list[dict], wiki_stats: dict, least: int = 2) -> dict[str, set[str]]:
    """Wikidata: player → pool clubs with at least one appearance."""
    out = {}
    for p in players:
        if p.get("women") or not p.get("wikidata"):
            continue
        stats = {**(wiki_stats.get(p["id"]) or {}), **(p.get("stats") or {})}
        clubs = {e[0] for e in p.get("career", []) if e[0] in POOL and (stats.get(e[0]) or [0])[0] > 0}
        if len(clubs) >= least:
            out[p["id"]] = clubs
    return out


def careers_b(players: list[dict], ids: list[str]) -> dict[str, set[str]]:
    """English Wikipedia infobox: player → pool clubs with at least one league appearance."""
    qid = {p["id"]: p["wikidata"] for p in players}
    titles = enwiki_titles([qid[i] for i in ids])
    pages = wikitext(sorted(set(titles.values())))
    rows = {i: infobox_rows(pages.get(titles.get(qid[i], ""), "")) for i in ids}
    clubs = club_qids(sorted({t for r in rows.values() for t, _, _ in r}))
    out = {}
    for i, r in rows.items():
        out[i] = {clubs[t] for t, apps, _ in r if clubs.get(t) in POOL and (apps or 0) > 0}
    print(f"Wikipedia: {len(titles)} articles, {sum(1 for r in rows.values() if r)} infoboxes")
    return out


GOALS = re.compile(r"\|\s*goals([12])\s*=(.*?)(?=\n\s*\||\n\}\})", re.S)
PLAYER_LINK = re.compile(r"\[\[([^\]|#]+)(?:\|[^\]]*)?\]\]\s*((?:\{\{[^}]*\}\}\s*,?\s*)+)")


def final_titles() -> dict[str, list[str]]:
    """Competition → Wikipedia article titles of its finals (redirects resolve the old names)."""
    cl = [f"{y} European Cup final" if y < 1993 else f"{y} UEFA Champions League final" for y in range(1956, 2027)]
    wc = [f"{y} FIFA World Cup final" for y in (1930, 1934, 1938, *range(1954, 2023, 4))]
    uel = [f"{y} UEFA Cup final" if y < 2010 else f"{y} UEFA Europa League final" for y in range(1972, 2027)]
    euro = ["1960 European Nations' Cup final", *(f"UEFA Euro {y} final" for y in range(1964, 2025, 4))]
    fac = [f"{y} FA Cup final" for y in range(1946, 2027)]
    lc = [f"{y} Football League Cup final" for y in range(1961, 2027)]
    return {"cl": cl, "wc": wc, "uel": uel, "euro": euro, "fac": fac, "lc": lc}


TEAM = re.compile(r"\|\s*team([12])\s*=\s*([^\n]*)")
# Old {{Football box}} and the newer {{#invoke:football box|main}}.
FOOTBALL_BOX = re.compile(r"\{\{\s*(?:#invoke:\s*)?football ?box", re.I)


def link_title(s: str) -> str | None:
    m = LINK.search(s)
    if not m:
        return None
    t = m.group(1).strip().replace("_", " ")
    return t[:1].upper() + t[1:]


def final_scorers(titles: list[str]) -> list[tuple[int, str, str | None]]:
    """[(year, scorer's article title, title of the team he scored for)] from each
    final's football box(es); own goals and shoot-outs left out."""
    pages = wikitext(titles)
    out = []
    for t, text in pages.items():
        year = int(re.search(r"\d{4}", t).group())
        # One box per match (a replayed final has two).
        for box in FOOTBALL_BOX.split(text)[1:]:
            box = box[:6000]
            teams = {n: link_title(v) for n, v in TEAM.findall(box)}
            for side, block in GOALS.findall(box):
                for name, marks in PLAYER_LINK.findall(block):
                    goals = re.findall(r"\{\{\s*goal\s*\|([^}]*)\}\}", marks, re.I)
                    # {{goal|35|o.g.}} is an own goal; {{goal|12|pen.}} still counts.
                    if any(not re.search(r"\bo\.?g\.?\s*$", g.strip(), re.I) for g in goals):
                        out.append((year, name.strip().replace("_", " "), teams.get(side)))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true", help="only the curated teasers (no Wikipedia)")
    args = ap.parse_args()

    players = json.loads((SEED / "players.json").read_text())["players"]
    wiki_stats = json.loads((SEED / "wiki_stats.json").read_text())["players"]
    by_id = {p["id"]: p for p in players}
    by_qid = {p["wikidata"]: p["id"] for p in players if p.get("wikidata")}
    # The app shows Wikipedia's title for a player where it has one ("Juan Mata", not
    # Wikidata's "Juan Mata Pata"), so the teasers do too.
    wiki_names = json.loads((SEED / "wiki_names.json").read_text())["players"]

    def shown(pid: str) -> str:
        return wiki_names.get(pid) or by_id[pid]["name"]
    out = []

    # Hand-checked teasers (derbies played in and the like): every answer has a
    # line-up or match report per fixture in its sources.
    curated = json.loads((SEED / "teasers_curated.json").read_text())["teasers"]
    for t in curated:
        out.append({"kind": "curated", **t})
    print(f"{len(curated)} curated teasers")

    if not args.offline:
        # "Scored in a Champions League / World Cup final AND played for X".
        # Scorers: the goals in each final's own article. Clubs: Wikidata AND the
        # player's Wikipedia infobox must both have league games there.
        a = careers_a(players, wiki_stats, least=1)
        spells = {p["id"]: p.get("career", []) for p in players}
        comps = final_titles()

        def club_in(pid: str, year: int) -> str | None:
            """His club for a final played in [year] (spring): the spell running through it."""
            now = [e for e in spells[pid] if e[1] is not None and e[1] < year and (e[2] is None or e[2] >= year)]
            return now[-1][0] if len(now) == 1 else None

        # comp → player → [(year, club qid he scored for)]
        scored: dict[str, dict[str, list[tuple[int, str | None]]]] = {}
        for comp, titles in comps.items():
            rows = final_scorers(titles)
            qids = club_qids(sorted({n for _, n, _ in rows} | {tm for _, _, tm in rows if tm}))
            per: dict[str, list[tuple[int, str | None]]] = {}
            for year, n, tm in rows:
                if (q := qids.get(n)) in by_qid:
                    pid = by_qid[q]
                    club = qids.get(tm) if tm else None
                    if club is None and comp not in ("wc", "euro"):
                        # The box names the team with a template ({{fb-rt|PSG}}) rather than
                        # a link: take the club he was at that season from his career.
                        club = club_in(pid, year)
                    per.setdefault(pid, []).append((year, club))
            scored[comp] = per
            print(f"{comp}: {len({y for y, _, _ in rows})} finals, {len({n for _, n, _ in rows})} scorers, "
                  f"{len(per)} in our player data")
        everyone = sorted(set().union(*scored.values()))
        b = careers_b(players, everyone)
        label = {
            "cl": "a European Cup or Champions League final", "wc": "a World Cup final",
            "uel": "a UEFA Cup or Europa League final", "euro": "a European Championship final",
            "fac": "an FA Cup final", "lc": "a League Cup final",
        }

        def stats(pid: str) -> dict[str, int]:
            p = by_id[pid]
            st = {**(wiki_stats.get(pid) or {}), **(p.get("stats") or {})}
            return {q: v[0] for q, v in st.items() if v and v[0]}

        def passing_through(pid: str, club: str) -> bool:
            """A spell people forget: not where he started, under 60 league games
            and at most a quarter of his career (Best at Fulham, not Rooney at Everton)."""
            career = spells[pid]
            # Not his first club, and not the famous last move (Gerrard at LA Galaxy).
            if not career or career[0][0] == club or career[-1][0] == club:
                return False
            st = stats(pid)
            apps, total = st.get(club, 0), sum(st.values())
            return 0 < apps < 60 and total > 0 and apps * 4 <= total

        def eras(pid: str, comp: str, club: str | None = None) -> int:
            m = 0
            for year, _ in scored[comp].get(pid, []):
                m |= era_mask(year, year)
            for e in spells[pid]:
                if club is None or e[0] == club:
                    m |= era_mask(e[1], e[2]) if club else 0
            return m

        used: dict[str, int] = {}
        for comp, per in scored.items():
            for club, name in POOL.items():
                s = {i for i in per if club in a.get(i, set()) and club in b.get(i, set())}
                # Both sources must agree, and nobody Wikidata alone puts at the club.
                loose = {i for i in per if club in a.get(i, set()) or club in b.get(i, set())}
                if not (1 <= len(s) <= 3) or s != loose or max(by_id[i]["fame"] for i in s) < MIN_FAME:
                    continue
                # The club must be a red herring: nobody scored a final FOR it
                # (Campbell's goal for Arsenal makes "…and played for Arsenal" too easy).
                if any(tm == club for i in s for _, tm in per[i]):
                    continue
                # …and a club they only passed through, so it takes some thinking.
                if not all(passing_through(i, club) for i in s):
                    continue
                # Two club questions per player at most (Diego Costa passed through a lot of clubs).
                if any(used.get(i, 0) >= 2 for i in s):
                    continue
                for i in s:
                    used[i] = used.get(i, 0) + 1
                top = max(by_id[i]["fame"] for i in s)
                m = 0
                for i in s:
                    m |= eras(i, comp, club)
                out.append({
                    "kind": "final",
                    "q": f"Scored in {label[comp]} AND played for {name}",
                    "answers": sorted(s),
                    "names": [shown(i) for i in sorted(s)],
                    "difficulty": 1 if top >= 5 else 2 if top == 4 else 3,
                    "eras": m or 31,
                })
        def add(q: str, ids, comps_: tuple[str, ...]) -> None:
            ids = sorted(ids)
            m = 0
            for i in ids:
                for c in comps_:
                    m |= eras(i, c)
            top = max(by_id[i]["fame"] for i in ids)
            out.append({"kind": "final", "q": q, "answers": ids, "names": [shown(i) for i in ids],
                        "difficulty": 1 if top >= 5 else 2 if top == 4 else 3, "eras": m or 31})

        # Finals in two, three or four competitions ("FA Cup, League Cup, UEFA
        # Cup AND Champions League" → Gerrard). Up to six answers: naming one is enough.
        seen: set[frozenset] = set()
        for n in (4, 3, 2):
            for combo in itertools.combinations(scored, n):
                ids = set.intersection(*(set(scored[c]) for c in combo))
                # Biggest combinations first; a smaller one with the same answers adds nothing.
                if 1 <= len(ids) <= 6 and max(by_id[i]["fame"] for i in ids) >= MIN_FAME \
                        and frozenset(ids) not in seen:
                    seen.add(frozenset(ids))
                    words = [label[c].split(" ", 1)[1] if c != combo[0] else label[c] for c in combo]
                    add("Scored in " + ", ".join(words[:-1]) + " AND " + words[-1], ids, combo)

        # The same final, for two different clubs (Ronaldo: United and Real).
        for comp in ("cl", "uel", "fac", "lc"):
            ids = {i for i, rows in scored[comp].items() if len({tm for _, tm in rows if tm}) >= 2}
            if 1 <= len(ids) <= 6:
                add(f"Scored in {label[comp]} for TWO different clubs", ids, (comp,))

    random.Random(7).shuffle(out)
    note = (f"Half-Time Teasers: {sum(t['kind'] == 'curated' for t in out)} hand-checked, "
            f"{sum(t['kind'] == 'final' for t in out)} final-scorer teasers checked against Wikipedia. "
            f"Built {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}.")
    print(note)
    (SEED / "teasers.json").write_text(
        "{\n" + f'  "_note": {json.dumps(note)},\n  "teasers": [\n'
        + ",\n".join("    " + json.dumps(t, ensure_ascii=False) for t in out) + "\n  ]\n}\n",
        encoding="utf-8")


if __name__ == "__main__":
    main()
