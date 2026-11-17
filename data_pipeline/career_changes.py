"""What the weekly refresh changed in well-known players' careers.

    python3 career_changes.py OLD_PLAYERS OLD_CLUBS > changes.md

Compares the previous seed (before this run's rebuild) with the new one, for
players with fame 4+. A club that starts this season or last is a transfer:
expected, just listed. Any other club gained or lost changes a career's
history, which is how a source error shows up (a vandalised club name, a
youth side, a club linked to the wrong article), so those are flagged.
Prints nothing when nothing changed; exit code 1 when history changed.
"""
from __future__ import annotations

import datetime as dt
import json
import pathlib
import sys

SEED = pathlib.Path(__file__).parent / "seed"


def load(players_path: str, clubs_path: str) -> tuple[dict, dict]:
    players = json.loads(pathlib.Path(players_path).read_text(encoding="utf-8"))["players"]
    clubs = json.loads(pathlib.Path(clubs_path).read_text(encoding="utf-8"))["clubs"]
    return {p["wikidata"]: p for p in players}, {c[0]: c[1] for c in clubs}


def main() -> int:
    old, old_clubs = load(sys.argv[1], sys.argv[2])
    new, new_clubs = load(str(SEED / "players.json"), str(SEED / "clubs.json"))
    names = {**old_clubs, **new_clubs}
    recent = dt.date.today().year - 1
    history: list[str] = []
    transfers: list[str] = []
    for q, p in sorted(new.items(), key=lambda kv: -kv[1].get("reach", 0)):
        if p["fame"] < 4 or q not in old:
            continue
        was = {s[0]: s for s in old[q]["career"]}
        now = {s[0]: s for s in p["career"]}

        def spell(s) -> str:
            return f"{names.get(s[0], s[0])} {s[1]}-{s[2] or ''}"

        for c in now.keys() - was.keys():
            line = f"- {p['name']}: + {spell(now[c])}"
            (transfers if now[c][1] >= recent else history).append(line)
        for c in was.keys() - now.keys():
            history.append(f"- {p['name']}: - {spell(was[c])}")
    if not history and not transfers:
        return 0
    if history:
        print("### Well-known players whose past clubs changed\n")
        print("Usually a source fixing itself; sometimes a new error. Check any that look wrong.\n")
        print("\n".join(history[:60]) + "\n")
    if transfers:
        print("### New moves\n")
        print("\n".join(transfers[:60]) + "\n")
    return 1 if history else 0


if __name__ == "__main__":
    sys.exit(main())
