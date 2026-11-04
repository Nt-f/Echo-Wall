# Echo-Wall

**Your Home Assistant as a wall of glass: an Echo Show's home screen, or any Android tablet's.**

Frosted widgets over your own photos, a page per room, a tap to switch, a hold for the controls. On an Echo Show
running [echo-dot-assist](https://github.com/Nt-f/echo-dot-assist) it is the screen the Echo comes home to, with the
voice assistant, alarms and timers drawn on its glass; on a tablet it logs in to Home Assistant by itself.

<img src="docs/screenshots/show5-home.png" width="49%"> <img src="docs/screenshots/show5-controls.png" width="49%">
<img src="docs/screenshots/show5-lock.png" width="49%"> <img src="docs/screenshots/show5-edit.png" width="49%">

## What you get

|                          |                                                                                        |
|--------------------------|----------------------------------------------------------------------------------------|
| **Home**                 | clocks, the weather, your favourites, what plays, the house's summary at a glance      |
| **Rooms**                | a page per Home Assistant area, tiles in Apple's glass, live sliders on a hold         |
| **Your dashboard**       | its sections as pages after Home, drawn in glass (the rest opens Home Assistant's own) |
| **Lock screen**          | your Immich photos (or the ones it ships with), the clock placed where no face is      |
| **Arrange it**           | on the device (hold a card) or from Home Assistant's sidebar, beside the app running live |
| **On an Echo Show**      | the voice assistant's glow and words, alarms and timers on glass (tap snoozes, hold stops), the Echo's login: nothing to type |
| **Every screen size**    | Echo Show 5 to 21, the round Echo Spot, any tablet                                     |

Every feature in detail: [docs/guide.md](docs/guide.md). How the app, the integration and the panel fit together:
[docs/integration.md](docs/integration.md).

## Install

### On an Echo Show (with [echo-dot-assist](https://github.com/Gamer92000/echo-dot-assist))

1. **The app.** Download `Echo-Wall.apk` from the [latest release](https://github.com/Nt-f/Echo-Wall/releases/latest).
   In Home Assistant: **Echo Local** (sidebar) › your Echo › **Apps** › *From this computer* › pick the APK › **Install**.
   (Or the Echo's settings page: **Screen** › **Add an app**.)
2. **Make it the home app.** Echo Local › your Echo › **Screen**: **App** = Echo-Wall, switch on **Connect it to Home
   Assistant**, **Save**. The Echo opens Echo-Wall and hands it Home Assistant's address and a login of its own.
3. **The integration** (for arranging its Home): HACS › ⋮ › **Custom repositories** › `https://github.com/Nt-f/Echo-Wall`,
   type **Integration** › install › restart Home Assistant › Settings › Devices & services › **Add integration** ›
   Echo-Wall. Echo Local's **Home** tab then arranges the Echo's Home.

### On a tablet

1. Install `Echo-Wall.apk` from the [latest release](https://github.com/Nt-f/Echo-Wall/releases/latest) (allow installs
   from your browser or file manager).
2. Open it, give Home Assistant's address and log in (a user of its own, not an administrator, is best). Make it the
   tablet's home app if it is to be the screen.
3. The integration as in step 3 above: the tablet shows up in the Echo-Wall panel by itself.

Updates: a newer release's APK installs over the old one the same way; nothing is lost (the layout lives in Home
Assistant). Even a reinstall keeps the device in Home Assistant: on an Echo its id comes from the Echo,
on a tablet from Android (Echo-Wall 1.1.1 on; an older install's id is moved over at its first login). Echo-Wall built by yourself (below) is signed with your own key and cannot update a released one in place:
uninstall it first.

## Build

Flutter 3.41.2. `flutter build apk --release` (Echo Show: `--target-platform android-arm`), `adb install` it.
`flutter test` runs the app's tests, every card at every size included.

<details><summary>The integration, the panel's live preview, the tests in a real Home Assistant</summary>


The integration is `custom_components/echo_wall/` (`hacs.json` at the top makes the repository HACS's). The same
WallView also runs in Home Assistant, as the panel's preview: `lib/preview.dart` built for the web (`web/`; the app's
files import `lib/io/io.dart`, which is `dart:io` on a device and stand-ins over the browser's fetch and WebSocket on
the web). `tools/preview.sh` builds it into `custom_components/echo_wall/frontend/preview/`; rerun it after a change to
the WallView and commit the result with it. `tools/ha_test.py` tests the integration and the panel in a real Home
Assistant (echo-dot-assist's `build/ha-venv`, or `ECHO_WALL_HA_PYTHON`).

</details>

<details><summary>On every Echo screen (emulator)</summary>

| Model | Home | A room | Detail | A category | Forecast | A request | An alarm | Editing | Lock screen |
|---|---|---|---|---|---|---|---|---|---|
| Echo Show 5 (960 × 480) | <img src="docs/screenshots/show5-home.png" width="160"> | <img src="docs/screenshots/show5-room.png" width="160"> | <img src="docs/screenshots/show5-controls.png" width="160"> | <img src="docs/screenshots/show5-category.png" width="160"> | <img src="docs/screenshots/show5-weather.png" width="160"> | <img src="docs/screenshots/show5-request.png" width="160"> | <img src="docs/screenshots/show5-alarm.png" width="160"> | <img src="docs/screenshots/show5-edit.png" width="160"> | <img src="docs/screenshots/show5-lock.png" width="160"> |
| Echo Show 8 / 10 / Hub (1280 × 800) | <img src="docs/screenshots/show8-home.png" width="160"> | <img src="docs/screenshots/show8-room.png" width="160"> | <img src="docs/screenshots/show8-controls.png" width="160"> | <img src="docs/screenshots/show8-category.png" width="160"> | <img src="docs/screenshots/show8-weather.png" width="160"> | <img src="docs/screenshots/show8-request.png" width="160"> | <img src="docs/screenshots/show8-alarm.png" width="160"> | <img src="docs/screenshots/show8-edit.png" width="160"> | <img src="docs/screenshots/show8-lock.png" width="160"> |
| Echo Show 8 2025 (1340 × 800) | <img src="docs/screenshots/show8-2025-home.png" width="160"> | <img src="docs/screenshots/show8-2025-room.png" width="160"> | <img src="docs/screenshots/show8-2025-controls.png" width="160"> | <img src="docs/screenshots/show8-2025-category.png" width="160"> | <img src="docs/screenshots/show8-2025-weather.png" width="160"> | <img src="docs/screenshots/show8-2025-request.png" width="160"> | <img src="docs/screenshots/show8-2025-alarm.png" width="160"> | <img src="docs/screenshots/show8-2025-edit.png" width="160"> | <img src="docs/screenshots/show8-2025-lock.png" width="160"> |
| Echo Show 11 (1920 × 1200) | <img src="docs/screenshots/show11-home.png" width="160"> | <img src="docs/screenshots/show11-room.png" width="160"> | <img src="docs/screenshots/show11-controls.png" width="160"> | <img src="docs/screenshots/show11-category.png" width="160"> | <img src="docs/screenshots/show11-weather.png" width="160"> | <img src="docs/screenshots/show11-request.png" width="160"> | <img src="docs/screenshots/show11-alarm.png" width="160"> | <img src="docs/screenshots/show11-edit.png" width="160"> | <img src="docs/screenshots/show11-lock.png" width="160"> |
| Echo Show 15 / 21 (1920 × 1080) | <img src="docs/screenshots/show15-home.png" width="160"> | <img src="docs/screenshots/show15-room.png" width="160"> | <img src="docs/screenshots/show15-controls.png" width="160"> | <img src="docs/screenshots/show15-category.png" width="160"> | <img src="docs/screenshots/show15-weather.png" width="160"> | <img src="docs/screenshots/show15-request.png" width="160"> | <img src="docs/screenshots/show15-alarm.png" width="160"> | <img src="docs/screenshots/show15-edit.png" width="160"> | <img src="docs/screenshots/show15-lock.png" width="160"> |
| Echo Show 15, upright | <img src="docs/screenshots/show15-portrait-home.png" width="160"> | <img src="docs/screenshots/show15-portrait-room.png" width="160"> | <img src="docs/screenshots/show15-portrait-controls.png" width="160"> | <img src="docs/screenshots/show15-portrait-category.png" width="160"> | <img src="docs/screenshots/show15-portrait-weather.png" width="160"> | <img src="docs/screenshots/show15-portrait-request.png" width="160"> | <img src="docs/screenshots/show15-portrait-alarm.png" width="160"> | <img src="docs/screenshots/show15-portrait-edit.png" width="160"> | <img src="docs/screenshots/show15-portrait-lock.png" width="160"> |
| Echo Show 1st gen (1024 × 600) | <img src="docs/screenshots/show1-home.png" width="160"> | <img src="docs/screenshots/show1-room.png" width="160"> | <img src="docs/screenshots/show1-controls.png" width="160"> | <img src="docs/screenshots/show1-category.png" width="160"> | <img src="docs/screenshots/show1-weather.png" width="160"> | <img src="docs/screenshots/show1-request.png" width="160"> | <img src="docs/screenshots/show1-alarm.png" width="160"> | <img src="docs/screenshots/show1-edit.png" width="160"> | <img src="docs/screenshots/show1-lock.png" width="160"> |
| Echo Spot 1st gen, round (480 × 480) | <img src="docs/screenshots/spot-home.png" width="160"> | <img src="docs/screenshots/spot-room.png" width="160"> | <img src="docs/screenshots/spot-controls.png" width="160"> | <img src="docs/screenshots/spot-category.png" width="160"> | <img src="docs/screenshots/spot-weather.png" width="160"> | <img src="docs/screenshots/spot-request.png" width="160"> | <img src="docs/screenshots/spot-alarm.png" width="160"> | <img src="docs/screenshots/spot-edit.png" width="160"> | <img src="docs/screenshots/spot-lock.png" width="160"> |
| Echo Spot 2024 (320 × 240) | <img src="docs/screenshots/spot2024-home.png" width="160"> | <img src="docs/screenshots/spot2024-room.png" width="160"> | <img src="docs/screenshots/spot2024-controls.png" width="160"> | <img src="docs/screenshots/spot2024-category.png" width="160"> | <img src="docs/screenshots/spot2024-weather.png" width="160"> | <img src="docs/screenshots/spot2024-request.png" width="160"> | <img src="docs/screenshots/spot2024-alarm.png" width="160"> | <img src="docs/screenshots/spot2024-edit.png" width="160"> | <img src="docs/screenshots/spot2024-lock.png" width="160"> |

</details>

## Credits

The nature photos: CC0, from Wikimedia Commons (`assets/photos/credits.json`: authors and sources): David Marcu,
Johannes Groll, Marco Bonomo, Jörg Braukmann, Jebulon, Wilfredor, DimiTalen. Inter: Rasmus Andersson, SIL Open Font
License 1.1 (`assets/fonts/Inter-LICENSE.txt`). MIT licence for the rest.
