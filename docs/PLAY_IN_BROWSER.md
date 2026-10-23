# Play Quizinho in your browser (no iPhone, no Xcode)

GitHub builds the game and hosts it at a web link. You do 3 things once;
after that every update appears at the same link automatically.

## You do (5 minutes, all on github.com)

1. **Create the repo** — github.com → **+** (top right) → **New repository**
   - Name: `quizinho`
   - Visibility: **Public** (free GitHub hosting only works for public repos;
     you can make it private later when we move to TestFlight)
   - Leave everything else unticked → **Create repository**
2. **Turn on hosting** — in the new repo: **Settings** → **Pages** (left menu)
   → under *Build and deployment*, **Source: GitHub Actions**. That's it.
3. **Get the code in** — either:
   - tell Claude the repo address (e.g. `github.com/yourname/quizinho`) and
     it pushes the code for you, **or**
   - use **GitHub Desktop** (free app): File → Add local repository → pick the
     unzipped `quizinho` folder → Publish/Push to your repo.

## Then wait ~5 minutes

Repo → **Actions** tab → **Web preview** shows a yellow dot (building), then a
green tick. Your game is at:

**`https://YOUR-GITHUB-USERNAME.github.io/quizinho/`**

Open it on a laptop (shows as a phone-sized window) or on any phone's browser.
Tap the screen once early on — browsers only allow sound after a tap.

If the Action shows a **red cross**, click it, copy the error, and send it to Claude.

## What the browser version can and can't do

- ✅ All three games, the wheel, scoring, sounds, commentary, winner screen.
- ✅ Same football data as the phone app.
- ❌ No vibration (browsers don't support it on iPhone).
- The iPhone/TestFlight route in `SETUP_IPHONE.md` is still there for later.
