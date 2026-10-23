# Getting Quizinho onto your iPhone — no Xcode needed

Pipeline: **GitHub** (code) → **GitHub Actions** (free tests + Android build) →
**Codemagic** (cloud Mac builds the iOS app and signs it) → **TestFlight** → your iPhone.

Everything below happens in a web browser except step 1. Steps marked 🔑 need
you signed in to your own accounts — nobody else can do them.

Apple requirement check: since 28 April 2026, App Store Connect only accepts
builds made with Xcode 26 / iOS 26 SDK. `codemagic.yaml` uses `xcode: latest`
on Codemagic's Macs, so this is handled in the cloud.

---

## 1. Put the code on GitHub 🔑 (~10 min)

1. github.com → **New repository** → name `quizinho`, **Private**, no README → Create.
2. Unzip `quizinho.zip` on your Mac.
3. Upload, either:
   - **Terminal** (works on old macOS):
     ```bash
     cd ~/Downloads/quizinho
     git init -b main
     git add .
     git commit -m "Quizinho MVP"
     git remote add origin https://github.com/YOUR-USERNAME/quizinho.git
     git push -u origin main
     ```
     (Asks for a password → use a GitHub personal access token.)
   - or **GitHub Desktop** → Add existing repository → Publish.

The **CI** workflow starts automatically (Actions tab). It validates the data,
runs the analyzer and tests, and builds an Android APK. Green tick = the code compiles.
If it's red, send me the log.

## 2. Generate the iOS/Android project folders (2 min)

GitHub → **Actions** → **Bootstrap platform folders** → **Run workflow**.
It runs `flutter create` in the cloud and commits `ios/` and `android/` back to
your repo with Quizinho's settings (name, portrait, export-compliance flag).
Run it once.

## 3. Apple setup 🔑 (~15 min, all on the web)

**a. API key (lets Codemagic sign and upload for you)**
App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**
→ **Team Keys** → **+** → name `Codemagic`, access **App Manager** → Generate.
Download the `.p8` file (one chance only) and note the **Issuer ID** and **Key ID**.

**b. Bundle ID**
developer.apple.com → Certificates, IDs & Profiles → **Identifiers** → **+** →
App IDs → App → Description `Quizinho`, Bundle ID **Explicit**
`com.littlefortstudios.quizinho` → Continue → Register.

**c. App record**
App Store Connect → **Apps** → **+** → New App → iOS, Name `Quizinho`
(if taken, try `Quizinho: Football Party Game`), language English (UK),
bundle ID from (b), SKU `quizinho`, Full Access → Create.
Then **App Information** → copy the numeric **Apple ID** (e.g. `6741234567`).

## 4. Codemagic setup 🔑 (~15 min)

1. codemagic.io → sign up **with GitHub** → personal account (500 free macOS minutes/month ≈ 20 builds).
2. **Add application** → GitHub → `quizinho` → Flutter App → *codemagic.yaml*.
3. **Personal Account settings → Integrations → Developer Portal → Connect** →
   upload the `.p8`, Issuer ID, Key ID. **Name it exactly `Quizinho ASC key`**
   (the YAML refers to that name).
4. **Code signing identities → iOS certificates → Generate certificate** →
   type Apple Distribution, choose the key → Create. Save the certificate
   password somewhere safe.
5. **iOS provisioning profiles → Fetch profiles**. If none appear for the bundle
   ID: developer.apple.com → **Profiles** → **+** → **App Store Connect** → pick
   `com.littlefortstudios.quizinho` → pick the certificate Codemagic just
   created → name `Quizinho App Store` → Generate. Then **Fetch profiles** again in Codemagic.
6. In GitHub, edit `codemagic.yaml` (pencil icon in the browser): replace
   `APP_STORE_APPLE_ID: "0000000000"` with your number from 3c → Commit to `main`.

That commit triggers the first iOS build (or press **Start new build** in Codemagic).
It takes ~15–25 minutes: tests → sign → build → upload to TestFlight.

## 5. Install on your iPhone 🔑

1. App Store Connect → your app → **TestFlight**. The build shows "Processing"
   for 10–30 minutes after Codemagic finishes.
2. **Internal Testing → +** → create group `Me` → add yourself.
3. iPhone → install **TestFlight** from the App Store → open the invite → **Install**.

## 6. Updating

Change code → push to `main`. Codemagic builds automatically, picks the next
build number from TestFlight, and uploads. TestFlight on your phone updates.
Mates can be added under **External Testing** (needs a quick Apple beta review)
or as internal testers if they're on your developer team.

---

## If something fails

| Symptom | Likely fix |
|---|---|
| CI red at *Analyze* or *Test* | Send me the log — it's a code issue on my side. |
| Codemagic: *No matching profiles found* | Step 4.5 — create/fetch the App Store profile. |
| Codemagic: integration not found | Key name must be exactly `Quizinho ASC key`. |
| Upload rejected: bundle ID | Step 3b and the YAML `bundle_identifier` must match. |
| Build number already used | Check `APP_STORE_APPLE_ID` is the app's numeric ID. |

## Alternative: GitHub Actions instead of Codemagic

Possible (macOS runners have Xcode 26), but you'd manage certificates as
encrypted secrets yourself and private-repo macOS minutes are expensive
(10× multiplier on the 2,000 free minutes). Codemagic's automatic signing is
the simpler path from a browser-only setup, so it's the default here.
