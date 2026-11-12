"""Probe: can Actions reach the Premier League's public stats feed (the one
premierleague.com's own pages call)? Prints status and a sample per stat."""
import json
import urllib.request

H = {"Origin": "https://www.premierleague.com", "Referer": "https://www.premierleague.com/",
     "User-Agent": "Mozilla/5.0 (QuizinhoDataPipeline)", "Accept": "application/json"}
OLD = "https://footballapi.pulselive.com/football/stats/ranked/players/{}?page=0&pageSize=12&comps=1&compCodeForActivePlayer=EN_PR&altIds=true"
STATS = ["goals", "own_goals", "red_card", "yellow_card", "att_hd_goal", "att_freekick_goal", "att_obox_goal",
         "goal_assist", "clean_sheet", "appearances", "sub_goals", "goals_sub", "att_pen_goal", "hat_trick"]
NEW = ["https://sdp-prem-prod.premier-league-prod.pulselive.com/api/v2/competitions/8/seasons/2025/players/stats/leaderboard?_sort=goals:desc&_limit=5",
       "https://sdp-prem-prod.premier-league-prod.pulselive.com/api/v1/competitions/8/seasons/2025/players/stats/leaderboard?_sort=goals:desc&_limit=5",
       "https://footballapi.pulselive.com/football/competitions/1/compseasons?page=0&pageSize=100"]


def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=H), timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except Exception as e:
        return getattr(e, "code", "ERR"), str(e)[:200]


for s in STATS:
    code, body = get(OLD.format(s))
    try:
        d = json.loads(body)
        rows = d["stats"]["content"]
        print(s, code, [(r["owner"]["name"]["display"], r["value"]) for r in rows[:12]])
    except Exception:
        print(s, code, body[:200])
for u in NEW:
    code, body = get(u)
    print(u, code, body[:600])
