# Echo-Wall

Home Assistant on an Amazon Echo Show running [hassmic](https://github.com/Nt-f/echo-dot-assist), in the manner of
Apple's HomeView: frosted-glass widgets over a photo, a page per room, a lock screen of photos the clock finds room on.
A fork of [Echo-Screen](https://github.com/Nt-f/Echo-Screen), the screen app template (its contract with
hassmic, its web screens, its keyboard, hassmic's clock, words and alarms drawn in the app's look); merge its `main`
for its fixes.

<img src="docs/screenshots/show5-home.png" width="480"> <img src="docs/screenshots/show5-controls.png" width="480">
<img src="docs/screenshots/show5-lock.png" width="480"> <img src="docs/screenshots/show5-edit.png" width="480">

## What it shows

- **Home**: an analog and a digital clock, the date and the weather, your favourites (a thermostat big, a camera's
  picture, scenes, locks, anything you star), what plays, and the other screens (Home Assistant's own UI, Music
  Assistant), with the house's summary beside the title (the temperature, lights on, locks open, what plays). Then a
  page per room (Home Assistant's areas), its temperature and humidity beside its name. Swiped sideways.
- **Tiles** as Home Assistant's tile card lays them out (the icon in a badge lit in its state's colour, the name, the
  state), on Apple's glass: a tap switches, a long press opens its detail. A tile gives a little under the finger.
- **The detail**: the tile grows into a card while the WallView dims behind it: Apple's tall pill for brightness,
  position and speed, live while you drag (a light's colours and whites as circles beside it); a thermostat's temperature big with − and + and its modes; one big round
  button for a switch or a lock; a speaker's artwork, buttons and volume. Swipe it down or tap beside it to close.
- **Editing**: hold the page dots. The widgets wobble; drag one to move it, ★ puts it on Home, − hides it; the bar picks
  the wallpaper (a photo, or amber, dusk, light) and lists what is hidden.
- **Categories**, as Apple's Home has them: beside Home's title, Lights, Climate, Security and Speakers say what they
  are doing; a tap shows just those devices on a sheet of glass (lights: "All off"). A room's lights the same way.
- **The forecast**: a tap on the date and weather shows today big and the next days (Home Assistant's
  weather.get_forecasts).
- **The voice assistant** on the glass, as Siri shows itself: while the Echo listens a glow of colour travels round the
  screen's edge; what you said and the answer rise on a card from the bottom; an alarm or a timer rings on glass over
  the dimmed WallView (a tap snoozes, a long press stops: hassmic reads the touch itself).
- **The lock screen**: left alone (2 minutes), the WallView rests behind a photo with the time, the date, the weather
  and the next alarm where the photo has room for them; swipe up to open. Its photos are your **Immich** library's, or
  the nature photos that come with the app.

## Photos from Immich

In Home Assistant: Echo Local › Configure on the Echo Show › "Screen app settings", one per line:

```
immich.url=http://192.168.1.20:2283
immich.key=<an Immich API key that may read assets and faces>
immich.album=<an album's id, optional: else your whole library>
photos.minutes=3
```

They reach the Echo sealed with its login (the key is a secret). The Echo reaches local addresses only, so Immich on
your network is fine; a photo service on the internet is not (hence the photos in the app).

**Where the clock goes**: each photo is read once (a 64-wide grid of its brightness): for nine places (left, middle,
right; top, middle, bottom) the clock could take, how busy the picture is there (edges, texture), how uneven, and
whether a face Immich found is under it (that most of all). The calmest place without a face wins; the clock is dark
on a bright sky or snow, white with a soft shadow elsewhere; the photo is cropped to the screen around its faces. On a
round Echo Spot the clock keeps to the middle.

## The glass

Apple's cards show what is behind them, blurred, its colour lifted. A live blur of the screen costs an Echo Show 5's
GPU (a Mali-T720 without Vulkan) half its frames; but behind the cards is the wallpaper, which does not move, so it is
rendered and blurred once (per photo and screen size) and every card draws its own piece of that blurred picture,
from where it is on the screen at each frame (`lib/home/backdrop.dart`). A bright photo (snow, a sky) is dimmed more under the glass, so that white on white
stays readable. The corners are Apple's continuous ones
(superellipses). The type is Inter (SIL OFL), the open face nearest San Francisco.

## On other Echo screens

The same app at each display Echo's resolution and density, in an Android emulator (`tools/screenshots.py`), with the
demo integration's made-up home; only the Echo Show 5 has run it for real.

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

## Build and install

Flutter 3.41.2. `flutter build apk --release --target-platform android-arm`, `adb install` it, and in Home Assistant:
Echo Local › Configure on the Echo › "Screen app": `io.github.nt_f.echowall`.

## Credits

The nature photos: CC0, from Wikimedia Commons (`assets/photos/credits.json`: authors and sources): David Marcu,
Johannes Groll, Marco Bonomo, Jörg Braukmann, Jebulon, Wilfredor, DimiTalen. Inter: Rasmus Andersson, SIL Open Font
License 1.1 (`assets/fonts/Inter-LICENSE.txt`). MIT licence for the rest.
