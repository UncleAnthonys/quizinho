"""The names players are actually known by, from English Wikipedia titles.

    python3 data_pipeline/wiki_names_fetch.py

Wikidata labels are often full legal names ("Alex Rodrigo Dias da Costa"),
but everyone knew him as Alex — which is his English Wikipedia title,
"Alex (footballer, born 1982)". For every player in seed/players.json this
reads the English Wikipedia title, drops the "(…)" part, and keeps it where it
differs from our name. Writes:

  seed/wiki_names.json   {"players": {player_id: "Alex"}}

build_db.py shows the known name and keeps the full name as an alias. Runs in
GitHub Actions (fetch-wiki-stats.yml): the dev workspace can't reach Wikipedia.
"""

from __future__ import annotations

import json
import re
import time

from wiki_stats_fetch import SEED, enwiki_titles

_BRACKETS = re.compile(r"\s*\([^)]*\)\s*$")


def known_name(title: str) -> str:
    return _BRACKETS.sub("", title).strip()


def main() -> None:
    players = json.loads((SEED / "players.json").read_text())["players"]
    by_qid = {p["wikidata"]: p for p in players if p.get("wikidata")}
    titles = enwiki_titles(sorted(by_qid))
    out = {}
    for qid, title in titles.items():
        p = by_qid[qid]
        name = known_name(title)
        # Only a genuinely different name: not a disambiguation or list page.
        if not name or name == p["name"] or "," in name or name.lower().startswith(("list of", "category")):
            continue
        out[p["id"]] = name
    note = (f"Known names from English Wikipedia titles where they differ from the Wikidata label: "
            f"{len(out)} players. Fetched {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}.")
    print(note)
    (SEED / "wiki_names.json").write_text(
        "{\n" + f'  "_note": {json.dumps(note)},\n  "players": {{\n'
        + ",\n".join(f"    {json.dumps(pid)}: {json.dumps(n, ensure_ascii=False)}" for pid, n in sorted(out.items()))
        + "\n  }\n}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
