# Launch checklist

Things to come back to before Quizinho goes live. Tick them off as they're done.

## When quizinho.app is bought
- [ ] DNS records added; GitHub Pages switched to quizinho.app (base href `/`)
- [ ] Join link / QR code: `joinPageUrl` in `lib/multiplayer/rooms_config.dart`
- [ ] Privacy policy URL → https://quizinho.app/privacy/ in Play Console (App content → Privacy policy) and App Store Connect (App Privacy)
- [ ] Support URL → https://quizinho.app/support/ in both stores
- [ ] Play Data safety → Delete data URL → https://quizinho.app/privacy/#delete
- [ ] Play Store settings → contact Website → https://quizinho.app/

## Google Play Console
- [ ] Re-check every App content answer before submitting
- [ ] App access ("Full game unlock (promo code)"): create a promo code for the £2.99 product (Monetise → Promo codes) and put it in place of `[CODE]`
- [ ] Data safety form (answers from Claude, matching the privacy policy)
- [ ] Trader status declared (company address + quizinho@littlefortstudios.com)
- [ ] Payments profile (Little Fort Studios Ltd, company bank account)
- [ ] In-app product `com.littlefortstudios.quizinho.fullgame`, £2.99 (needs a build uploaded first)
- [ ] Store listing: "Quizinho: Football Party Quiz", text, icon, feature graphic, screenshots
- [ ] Android build + signing in Codemagic (Claude)
- [ ] Android manifest: strip the AD_ID permission (Play is told the app uses no advertising ID)

## App Store Connect
- [ ] Paid Applications Agreement, bank and tax (W-8BEN-E)
- [ ] App Store Small Business Program (15% instead of 30%)
- [ ] In-app purchase `com.littlefortstudios.quizinho.fullgame`, non-consumable, £2.99, with a paywall review screenshot
- [ ] Name "Quizinho: Football Party Quiz", subtitle, keywords, description, screenshots (iPhone 6.9", iPad 13")
- [ ] App Privacy answers (from Claude)
- [ ] Age rating, category (Games → Trivia)

## After launch
- [ ] Under-13s: the target audience is 13+ at launch. To aim at younger players, keep typed names and voice misses on the phone (or get consent), add a children's section to the privacy policy, then add the under-13 age groups in Play (Families policy)

## In the app
- [ ] `appStoreUrl` in `lib/core/app_links.dart`, which shows the "Download the app" line on joined phones. Finalise its copy: "Download the app to never hear the same questions twice and better voice recognition"
- [ ] Purchases switched on (`Purchases.enabled` in `lib/core/purchases.dart`)
