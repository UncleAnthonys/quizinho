# Football data pipeline

Everything the games know comes from one versioned SQLite file,
`assets/db/football.db`, built here and bundled with the app (fully offline).

```
seed/*.json  ──build_db.py──▶  assets/db/football.db  +  football_db_version.txt
     ▲
     └── (Phase 2) wikidata_fetch.py → raw/ → normalise.py → verified seed
```

## Current status: demo data

`seed/` holds ~55 career histories and 12 famous line-ups **written from general
knowledge, not checked against sources**. Every row is imported with
`verified = 0` and the app shows a "demo data" note. It is good enough to
play-test the games, not to ship.

## Commands

```bash
python3 data_pipeline/build_db.py --check   # validate only (CI runs this)
python3 data_pipeline/build_db.py           # rebuild the bundled DB
```

The build fails on: unknown clubs, duplicate IDs, spells ending before they
start, line-ups without exactly 11 unique players and one GK. It warns on
out-of-order careers.

## Rules for "played for a club"

Applied in the pipeline so every game agrees:

1. Senior first-team spells only. Youth, academy, U-21/23 and B teams are never stored.
2. Loans count (flagged `is_loan`, shown as LOAN in Career Path).
3. Signed-but-never-played transfers don't count (Wikidata `P1350` matches played = 0 → dropped).
4. Return spells are separate entries in career order (Zlatan: … → LA Galaxy → AC Milan).
5. Answers are checked by stable player ID, never by text.

## Generated content

- **Club Connections**: every club pair sharing ≥1 player. A pair with no
  answer is impossible by construction. Difficulty blends the fame of the best
  answer (60%) with the clubs' fame (40%) → 1 easy … 4 expert.
- **Career Path**: every player with ≥3 spells at ≥3 clubs. Difficulty from player fame.
- **Starting XI**: matches from `seed/matches.json`, difficulty from match fame.
- **Bidding War**: generated "played for both clubs" and "players from X at
  club Y" categories, plus hand-made ones in `seed/bidding_curated.json`
  (records, awards, managers, clubs). Hand-made lists are short: 5–20
  answers, so a team can get through them in a minute; the generated ones
  may run longer. Each hand-made list names its source and an `as_of`; stat
  lists (top 10s, caps, Golden Boot…) need refreshing when they change.
  Answers are names; pin an ambiguous one with `"Name|player-id"`, or
  `"Name|new"` for someone the career data lacks (e.g. a manager).
  `"answers_are": "clubs"` takes club names, and `club_aliases` adds
  nicknames. The build fails if any answer doesn't resolve. In the app,
  categories are picked 40% hand-made / 40% club pairs / 20% nationality.

The demo seed already yields 811 club pairings; with a few thousand players
from Wikidata this becomes tens of thousands without writing questions by hand.

## Sources and licences

| Source | Use | Licence position |
|---|---|---|
| Wikidata (`P54` team membership, `P580/P582` dates, `P1350` apps) | Careers, clubs, aliases | CC0 — free for commercial use and offline redistribution. |
| StatsBomb Open Data | Not used | Offered for research and analytics with attribution; not a safe basis for a paid app without written permission. |
| Hand-checked line-ups | Starting XI | Facts (who started) aren't copyrightable, but don't bulk-copy one site's database (UK/EU database right). Verify each XI against two independent match reports, record the sources, then set `verified = 1`. |
| Commercial football APIs | Not used | Most forbid storing and redistributing their data offline in an app; would need a specific licence. |

## Next steps (Phase 2)

1. Run `wikidata_fetch.py` (≥40 sitelinks ≈ well-known players).
2. Write `normalise.py`: club mapping/aliases, youth filter, loan flags, fame from sitelinks.
3. Review the diff against the demo seed; anything that disagrees gets a human check.
4. Verify the 12 line-ups, then extend towards 100 matches.
