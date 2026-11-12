"""Winning sides of the finals behind the grid's cup-winner categories, from
the Wikipedia articles finals_fetch.py saved (raw/finals_wikitext.json.gz).

For each final: the football box(es) give the teams and the result (a
replay's last match decides it; penalties settle a draw); the line-up tables
after it give each side's players on the day, starters and substitutes,
in the box's order (team 1, then team 2). Writes seed/final_winners.json:
competition -> year -> winning team and the Wikidata ids of its players.
Finals we can't read cleanly (no line-up table, a side under 11) are left
out and listed, never guessed.
"""
from __future__ import annotations

import gzip
import json
import pathlib
import re

HERE = pathlib.Path(__file__).parent
RAW, SEED = HERE / "raw", HERE / "seed"

BOX = re.compile(r"\{\{\s*(?:#invoke:\s*)?football ?box", re.I)
FIELD = re.compile(r"\|\s*(team1|team2|score|penaltyscore)\s*=\s*([^\n]*)")
LINK = re.compile(r"\[\[([^\]|#]+)(?:\|[^\]]*)?\]\]")
# "|GK ||'''1''' ||{{flagicon|BRA}} [[Cafu]]" or "|{{abbr|RB|Right-back}} ||'''16'''||[[Philipp Lahm]]"
ROW = re.compile(r"^\|\s*(?:[A-Z]{1,3}|\{\{abbr\|[A-Z]{1,3}\|[^}]*\}\})\s*\|\|")
NUM = re.compile(r"(\d+)\s*[–-]\s*(\d+)")


def plain(link: str) -> str:
    t = link.strip().replace("_", " ")
    return t[:1].upper() + t[1:]


def boxes(text: str) -> list[dict]:
    out = []
    for chunk in BOX.split(text)[1:]:
        f = {k: v.strip() for k, v in FIELD.findall(chunk[:4000])}
        def team(v: str | None) -> str:
            v = v or ""
            if m := LINK.search(v):
                return plain(m.group(1))
            if m := re.search(r"\|\s*([A-Z]{3})\s*(?:\|\s*\d{4}\s*)?\}\}", v):
                return m.group(1)  # a national side: {{fb-rt|FRA|1974}}, {{#invoke:flag|fb|ENG}}
            return re.sub(r"\{\{[^}]*\}\}", "", v).strip()
        out.append({"team1": team(f.get("team1")), "team2": team(f.get("team2")),
                    "score": NUM.search(f.get("score", "")), "pens": NUM.search(f.get("penaltyscore", ""))})
    return out


def lineups(text: str) -> list[list[str]]:
    """Each side's line-up table: the linked players, in page order."""
    sides, current = [], None
    for line in text.splitlines():
        if ROW.match(line):
            if current is None:
                current = []
            links = [plain(l) for l in LINK.findall(line) if ":" not in l]
            links = [l for l in links if not l.startswith("Captain")]
            if links:
                current.append(links[0])
        elif current is not None and re.search(r"Manager|Coach|Head coach|'''Manager", line, re.I):
            sides.append(current)
            current = None
        elif current is not None and line.startswith("|}"):
            sides.append(current)
            current = None
    if current:
        sides.append(current)
    return [s for s in sides if s]


def winner(b: dict) -> int | None:
    """1 or 2, or None for a draw that a replay settled."""
    s, p = b["score"], b["pens"]
    if not s:
        return None
    g1, g2 = int(s.group(1)), int(s.group(2))
    if g1 != g2:
        return 1 if g1 > g2 else 2
    if p:
        return 1 if int(p.group(1)) > int(p.group(2)) else 2
    return None


# Two-legged UEFA Cup finals level on aggregate, settled on away goals or
# penalties (checked against each final's article).
AGG_WINNERS = {
    1977: "Juventus FC",             # away goals
    1980: "Eintracht Frankfurt",     # away goals
    1984: "Tottenham Hotspur F.C.",  # penalties
    1988: "Bayer 04 Leverkusen",     # penalties
    1992: "AFC Ajax",                # away goals
    1997: "FC Schalke 04",           # penalties
}


def decide(bs: list[dict], sides: list[list[str]], two_legged: bool, year: int = 0) -> tuple[str | None, list[str] | str]:
    """(winning team, its players on the day), or (None, why not). Each box
    has two line-up tables, in order: team 1's, then team 2's."""
    if not bs or len(sides) != 2 * len(bs):
        return None, f"{len(bs)} match boxes but {len(sides)} line-up tables"
    if any(not b["team1"] or b["team1"] == b["team2"] for b in bs):
        return None, "teams not read"
    if two_legged and year in AGG_WINNERS:
        team = AGG_WINNERS[year]
        if team not in {b[k] for b in bs for k in ("team1", "team2")}:
            return None, f"hand-set winner {team} not in the boxes"
    elif two_legged:
        goals: dict[str, int] = {}
        for b in bs:
            if not b["score"]:
                return None, "a leg without a score"
            goals[b["team1"]] = goals.get(b["team1"], 0) + int(b["score"].group(1))
            goals[b["team2"]] = goals.get(b["team2"], 0) + int(b["score"].group(2))
        best = sorted(goals.items(), key=lambda kv: -kv[1])
        if len(best) != 2 or best[0][1] == best[1][1]:
            return None, f"two legs level on aggregate {goals} (away goals)"
        team = best[0][0]
    else:
        decided = [b for b in bs if winner(b)]
        if not decided:
            return None, "no result read"
        last = decided[-1]
        team = last["team1"] if winner(last) == 1 else last["team2"]
    players: list[str] = []
    for i, b in enumerate(bs):
        for n, key in ((0, "team1"), (1, "team2")):
            if b[key] == team:
                players += [p for p in sides[2 * i + n] if p not in players]
    if len(players) < 11:
        return None, f"winning side {team} has {len(players)} players"
    return team, players


def main() -> int:
    doc = json.load(gzip.open(RAW / "finals_wikitext.json.gz", "rt", encoding="utf-8"))
    pages, qids = doc["pages"], doc.get("qids", {})
    out, skipped = {}, []
    for comp, titles in doc["titles"].items():
        for title in titles:
            text = pages.get(title)
            if not text:
                continue
            year = int(re.search(r"\d{4}", title).group())
            bs = boxes(text)
            sides = lineups(text)
            team, side = decide(bs, sides, two_legged=comp == "uel" and year < 1998, year=year)
            if team is None:
                skipped.append(f"{title}: {side}")
                continue
            out.setdefault(comp, {})[str(year)] = {
                "team": team, "players": [qids.get(t, t) for t in side], "names": side}
    note = (f"Winning sides from Wikipedia final line-ups (starters and substitutes). "
            f"{sum(len(v) for v in out.values())} finals read; {len(skipped)} left out.")
    (SEED / "final_winners.json").write_text(
        json.dumps({"_note": note, "skipped": skipped, "finals": out}, ensure_ascii=False, indent=1) + "\n",
        encoding="utf-8")
    print(note)
    for s in skipped:
        print("  skipped", s)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
