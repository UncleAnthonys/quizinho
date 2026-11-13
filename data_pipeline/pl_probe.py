"""Probe: what the Premier League feed's match pages hold (goal events, line-ups, ages)."""
import json, urllib.request
H = {"Origin": "https://www.premierleague.com", "Referer": "https://www.premierleague.com/",
     "User-Agent": "Mozilla/5.0 (QuizinhoDataPipeline)", "Accept": "application/json"}
A = "https://footballapi.pulselive.com/football"
def get(u):
    try:
        with urllib.request.urlopen(urllib.request.Request(u, headers=H), timeout=30) as r:
            return r.status, json.load(r)
    except Exception as e:
        return getattr(e, "code", "ERR"), str(e)[:200]
c, d = get(f"{A}/fixtures?comps=1&compSeasons=1&page=0&pageSize=5&statuses=C")
print("fixtures", c, json.dumps(d)[:1500])
fid = int(d["content"][0]["id"]) if c == 200 else 0
c, d = get(f"{A}/fixtures/{fid}")
print("fixture", c, json.dumps(d)[:4000])
c, d = get(f"{A}/fixtures/{fid}?altIds=true&detail=2")
print("fixture detail", c, json.dumps(d)[:200], "keys:", list(d) if isinstance(d, dict) else "")
for k in ("goals", "events", "teamLists"):
    print(k, json.dumps(d.get(k) if isinstance(d, dict) else None)[:1500])
c, d = get(f"{A}/stats/ranked/players/goals?page=0&pageSize=5&comps=1&opponent=12")
print("opponent filter", c, json.dumps(d)[:600])
c, d = get(f"{A}/players/1440?altIds=true")
print("player", c, json.dumps(d)[:1500])
