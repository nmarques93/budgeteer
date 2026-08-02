# Budgeteer iOS app

A thin native wrapper around the live Budgeteer web app, built with
[Capacitor](https://capacitorjs.com). This is **not** a rewrite — there's no
separate UI or API. The native shell just loads
`https://budgeteer-marbled-snowfall-2406.fly.dev` (see `capacitor.config.json`'s
`server.url`) directly, the same LiveView app everyone already uses in a
browser, and layers on a few things a browser tab can't do: a real
Home Screen icon, push notifications, and native camera capture for
statement uploads.

Because of that "remote URL" mode, there is no local web build step here —
`mobile/www/` is a placeholder (Capacitor's tooling requires *some* local
`webDir` to exist, but it's never actually shown; see the comment in
`www/index.html`). Ordinary changes to the Phoenix app need **no changes
here at all** — they just show up the next time the app loads the page,
exactly like a browser refresh.

## What's genuinely native here

- **Camera capture for statement uploads** — `StatementLive.Upload` gets a
  "Take a photo" button when running inside this app (see the
  `.NativeCameraUpload` colocated hook in
  `lib/budgeteer_web/live/statement_live/upload.ex`). It calls
  `@capacitor/camera` directly via `window.Capacitor.Plugins.Camera`, then
  POSTs the captured photo to the existing `StatementController` upload
  endpoint — same server-side code path as the ordinary file-picker upload.
- **Push notifications** for budget alerts — see `Budgeteer.Push`,
  `Households.DeviceToken`, and the registration script in
  `root.html.heex`. Additive to the existing budget-alert *email*, never a
  replacement for it — see the caveat below.
- **No install banner** — the existing iOS "Add to Home Screen" nudge
  (`root.html.heex`) detects `window.Capacitor.isNativePlatform()` and
  never shows once you're already running the real app.

Everything else — every page, every form, real-time sync, translations —
is just the web app, unmodified.

## Prerequisites

- **Xcode** (full app, not just Command Line Tools) — install from the Mac
  App Store. This is the one hard requirement; nothing here works without
  it (building, signing, and the iOS Simulator all need it).
- Node.js (already installed if you're reading this from a working `npm
  install`).
- **CocoaPods is not needed** — this project uses Swift Package Manager
  for Capacitor's plugins (`ios/App/CapApp-SPM/`), which Xcode resolves
  automatically on first open.
- An Apple ID is enough to build and run in the Simulator. A paid Apple
  Developer Program membership ($99/yr) is only needed for installing on a
  real device, push notifications, and App Store/TestFlight distribution.

## First-time setup

```bash
cd mobile
npm install
open ios/App/App.xcodeproj
```

In Xcode: pick an iPhone simulator from the scheme selector, then hit Run
(▶). First launch will take a minute while Xcode resolves the Swift
packages. The app should open straight to the live Budgeteer landing page.

## Updating the native project

You only need to touch this directory (and re-run `npx cap sync ios`) when
changing something about the *native shell itself* — installing a new
Capacitor plugin, editing `capacitor.config.json`, or regenerating icons.
Everyday Phoenix/LiveView work never needs this.

```bash
cd mobile
npx cap sync ios
```

## Push notifications — what's left to do

The code path is fully wired (device-token registration, `Budgeteer.Push`'s
APNs JWT signing, the `BudgetAlertWorker` integration), but **it has never
sent a real push** — that needs credentials only you can generate:

1. In [Apple Developer](https://developer.apple.com/account) → Certificates,
   IDs & Profiles → **Keys**, create a new key with the "Apple Push
   Notifications service (APNs)" capability enabled. Download the `.p8`
   file **immediately** — Apple only lets you download it once.
2. Note the **Key ID** (shown on the key's page) and your **Team ID**
   (top-right of the Developer portal, or Membership Details).
3. Set three environment variables wherever the Phoenix app actually runs
   (e.g. `fly secrets set ...` for production):
   - `APNS_KEY` — the full contents of the `.p8` file
   - `APNS_KEY_ID`
   - `APNS_TEAM_ID`
   - (`APNS_TOPIC` defaults to `com.budgeteer.app`, matching this app's
     bundle id — only set it if you change the bundle id below)
4. In Xcode: select the `App` target → **Signing & Capabilities** → **+
   Capability** → **Push Notifications**. This is a one-click step in
   Xcode's UI that generates the required entitlements file and updates
   the project automatically — deliberately not hand-edited here, since
   getting an Xcode project's capability wiring right without Xcode itself
   to verify it would be guesswork.
5. Trigger a real budget alert (go over a category's budget) and confirm a
   push arrives on a real device running a build signed with your team.

Until all of that's done, `Budgeteer.Push` silently no-ops — nothing
breaks, the existing budget-alert *email* still sends normally either way.

## Distribution

Given this is a single-household app, the simplest path is **TestFlight
only** — skip the public App Store listing entirely:

1. Enroll in the Apple Developer Program (if not already, for push above).
2. In Xcode, set your Team under Signing & Capabilities, pick a real
   bundle id if `com.budgeteer.app` is already taken (unlikely, but
   update `capacitor.config.json`'s `appId` too if you do, then re-run
   `npx cap sync ios`).
3. Product → Archive, then use the Organizer window's "Distribute App" →
   TestFlight internal testing flow. Apple's review for TestFlight
   internal testing is much lighter than a full App Store submission.
4. Invite yourself (and any other household member) as an internal tester
   by email in App Store Connect.

If you do want a public App Store listing later: the "just a wrapped
website" rejection risk is real, so make sure push notifications and
camera capture (both already built) are actually working and visible in
your review notes/screenshots before submitting.

## Testing against a different server

To point the app at a local dev server or a staging environment instead of
production, edit `server.url` in `capacitor.config.json`, then
`npx cap sync ios`. For a local Phoenix server, use your Mac's LAN IP (not
`localhost` — the simulator/device needs a reachable address), e.g.
`https://192.168.1.23:4001` (matching the `https:` dev endpoint already
configured in `config/dev.exs`).
