# hassmic-screen

A screen app for an Amazon Echo Show running [hassmic](https://github.com/Nt-f/echo-dot-assist), in Flutter: what
the Echo Show's screen shows when it is not hassmic's (the clock, a request's words, a ringing alarm stay hassmic's).

This is the template. It does what hassmic's built-in Java kiosk does, so that you can start from something that
works and make it yours:

- the screens Home Assistant's hassmic integration lists (Home Assistant's dashboards, Music Assistant, any page) in
  a WebView, logged into Home Assistant with the Echo's own token (no typing: the integration made a user for it)
- a handle at the top edge: tap it for the screens and a reload
- back to the start screen after the time the integration says, untouched
- an on-screen keyboard (the Echo has no input method): it comes up when a text field in the page has the focus and
  types with real key events (`MainActivity.kt`); on a device with a keyboard of its own, that one comes instead
- round screens (Echo Spot): the switcher and the keyboard kept inside the circle
- hassmic's own pictures in the app's look (it polls `/front/draws`, so hassmic leaves the screen to it): the clock as
  a screen ("Clock" in the integration's options), a request's words, an alarm or timer ringing, from hassmic's state
  feed (`/kiosk/state`, a long poll: words appear as hassmic has them); taps on a ring still reach hassmic

The contract with hassmic (how the app is started, where its config comes from, what it tells hassmic) is in
echo-dot-assist's [docs/screen-apps.md](https://github.com/Nt-f/echo-dot-assist/blob/main/docs/screen-apps.md);
`lib/hassmic.dart` is this app's side of it. The config also carries Home Assistant's address and a token for its
websocket API, for screens drawn in Flutter instead of a WebView.

## On other Echo screens

The same app at each display Echo's resolution and density, in an Android emulator (`tools/screenshots.py`), with
the demo integration's made-up home: Home Assistant's dashboard, the switcher (the handle tapped), the keyboard on a
sign-in page. Only the Echo Show 5 has run it for real so far; the emulator shows layout, not speed. On a round
screen (Android's `isScreenRound`) the switcher sits lower and the keyboard's rows follow the circle. The Echo Dots
with a clock have LED segments, no screen for this.

| Model | Screen | dpi | Dashboard | Switcher | Keyboard |
|---|---|---|---|---|---|
| Echo Show 5 (all three) | 960 × 480 | 160 (measured) | <img src="docs/screenshots/show5-dashboard.png" width="220"> | <img src="docs/screenshots/show5-switcher.png" width="220"> | <img src="docs/screenshots/show5-keyboard.png" width="220"> |
| Echo Show 8 (1st–3rd gen), Show 10, Echo Hub | 1280 × 800 | 213 (measured, 1st gen) | <img src="docs/screenshots/show8-dashboard.png" width="220"> | <img src="docs/screenshots/show8-switcher.png" width="220"> | <img src="docs/screenshots/show8-keyboard.png" width="220"> |
| Echo Show 8 (2025) | 1340 × 800 | 213 (estimated) | <img src="docs/screenshots/show8-2025-dashboard.png" width="220"> | <img src="docs/screenshots/show8-2025-switcher.png" width="220"> | <img src="docs/screenshots/show8-2025-keyboard.png" width="220"> |
| Echo Show 11 (2025) | 1920 × 1200 | 240 (estimated) | <img src="docs/screenshots/show11-dashboard.png" width="220"> | <img src="docs/screenshots/show11-switcher.png" width="220"> | <img src="docs/screenshots/show11-keyboard.png" width="220"> |
| Echo Show 15 / 21 | 1920 × 1080 | 160 (estimated) | <img src="docs/screenshots/show15-dashboard.png" width="220"> | <img src="docs/screenshots/show15-switcher.png" width="220"> | <img src="docs/screenshots/show15-keyboard.png" width="220"> |
| Echo Show 15, hung upright | 1080 × 1920 | 160 (estimated) | <img src="docs/screenshots/show15-portrait-dashboard.png" width="220"> | <img src="docs/screenshots/show15-portrait-switcher.png" width="220"> | <img src="docs/screenshots/show15-portrait-keyboard.png" width="220"> |
| Echo Show (1st gen) | 1024 × 600 | 160 (estimated) | <img src="docs/screenshots/show1-dashboard.png" width="220"> | <img src="docs/screenshots/show1-switcher.png" width="220"> | <img src="docs/screenshots/show1-keyboard.png" width="220"> |
| Echo Spot (1st gen), round | 480 × 480 | 240 (estimated) | <img src="docs/screenshots/spot-dashboard.png" width="220"> | <img src="docs/screenshots/spot-switcher.png" width="220"> | <img src="docs/screenshots/spot-keyboard.png" width="220"> |
| Echo Spot (2024) | 320 × 240 | 120 (estimated) | <img src="docs/screenshots/spot2024-dashboard.png" width="220"> | <img src="docs/screenshots/spot2024-switcher.png" width="220"> | <img src="docs/screenshots/spot2024-keyboard.png" width="220"> |

And what hassmic would otherwise draw over the app, drawn by it (the `hassmic:clock` screen, a request's words,
an alarm ringing; `/kiosk/state`):

| Model | Clock | Request | Alarm |
|---|---|---|---|
| Echo Show 5 | <img src="docs/screenshots/show5-clock.png" width="220"> | <img src="docs/screenshots/show5-request.png" width="220"> | <img src="docs/screenshots/show5-alarm.png" width="220"> |
| Echo Show 8 / 10 / Hub | <img src="docs/screenshots/show8-clock.png" width="220"> | <img src="docs/screenshots/show8-request.png" width="220"> | <img src="docs/screenshots/show8-alarm.png" width="220"> |
| Echo Show 8 (2025) | <img src="docs/screenshots/show8-2025-clock.png" width="220"> | <img src="docs/screenshots/show8-2025-request.png" width="220"> | <img src="docs/screenshots/show8-2025-alarm.png" width="220"> |
| Echo Show 11 | <img src="docs/screenshots/show11-clock.png" width="220"> | <img src="docs/screenshots/show11-request.png" width="220"> | <img src="docs/screenshots/show11-alarm.png" width="220"> |
| Echo Show 15 / 21 | <img src="docs/screenshots/show15-clock.png" width="220"> | <img src="docs/screenshots/show15-request.png" width="220"> | <img src="docs/screenshots/show15-alarm.png" width="220"> |
| Echo Show 15, upright | <img src="docs/screenshots/show15-portrait-clock.png" width="220"> | <img src="docs/screenshots/show15-portrait-request.png" width="220"> | <img src="docs/screenshots/show15-portrait-alarm.png" width="220"> |
| Echo Show (1st gen) | <img src="docs/screenshots/show1-clock.png" width="220"> | <img src="docs/screenshots/show1-request.png" width="220"> | <img src="docs/screenshots/show1-alarm.png" width="220"> |
| Echo Spot (1st gen) | <img src="docs/screenshots/spot-clock.png" width="220"> | <img src="docs/screenshots/spot-request.png" width="220"> | <img src="docs/screenshots/spot-alarm.png" width="220"> |
| Echo Spot (2024) | <img src="docs/screenshots/spot2024-clock.png" width="220"> | <img src="docs/screenshots/spot2024-request.png" width="220"> | <img src="docs/screenshots/spot2024-alarm.png" width="220"> |

Again: `flutter build apk --release --target-platform android-x64`, start an emulator, then
`python3 tools/screenshots.py --serial emulator-5554` (its header says what it needs).

## Build

Flutter 3.41.2 (the Echo Show 5 is Android 7.1, 32-bit ARM, a Mali-T720 GPU without Vulkan: Flutter draws with Skia on
OpenGL ES there, at 60 fps; keep full-screen live blurs out, they cost half of that).

```sh
flutter build apk --release --target-platform android-arm
```

Release builds are signed with Flutter's debug key unless you set up your own
([Flutter's docs](https://docs.flutter.dev/deployment/android#sign-the-app)); an update must be signed with the same
key as the installed app. CI builds the APK on every push and attaches it to a release for each `v*` tag.

## Install

```sh
adb install build/app/outputs/flutter-apk/app-release.apk
```

Then in Home Assistant: Settings › Devices & services › hassmic › Configure on the Echo Show, "Screen app":
`org.hassmic.screen` (your fork: its `applicationId`). Empty brings hassmic's own kiosk back. hassmic starts the app
by the intent `org.hassmic.action.SCREEN` and hands its config to that app alone.

## Make it yours

Fork it, change `applicationId` in `android/app/build.gradle.kts`, and replace the WebView in `lib/main.dart` with
your own screens. Measured on an Echo Show 5: this app with Home Assistant in its WebView takes 81 MB; the whole
Echo has 1 GB for Android, hassmic and the screen.

MIT licence.
