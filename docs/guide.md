# Echo-Wall in detail

What the app shows and how, beyond the [README](../README.md).

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
- **Editing**: hold the page dots (or any card, on past its menu). The widgets wobble; drag one to move it (held at the
  screen's edge, onto another page, room or Home), ⤡ resizes it in place, ★ puts it on Home, − hides it; the bar picks
  the wallpaper (a photo, or amber, dusk, light) and lists what is hidden. The layout is kept in Home Assistant too
  (Echo-Wall's integration): its sidebar panel "Echo-Wall" edits it beside the app itself, exports it to a file,
  imports it and copies it to other devices; a save there shows here at once (`lib/home/layout_sync.dart`,
  [integration.md](integration.md)).
- **Your dashboard**: pick one of your Home Assistant dashboards in the Echo-Wall panel and its sections become pages after
  Home, drawn here in glass (tiles, thermostats, players, cameras, entities, glance, weather; other cards open the
  dashboard). Changes in Home Assistant show at once. Hold a card for its menu (controls, sizes, move, remove); hold on
  to edit. What you change on the Echo stays in the app's layout, never in the dashboard.
- **Every card in the sizes that suit it**: small, wide, large, extra large (`lib/home/sizes.dart`);
  `test/gallery_test.dart` draws every one at every size and fails on an overflow (`test/goldens/cards.png`).
- **Categories**, as Apple's Home has them: beside Home's title, Lights, Climate, Security and Speakers say what they
  are doing; a tap shows just those devices on a sheet of glass (lights: "All off"). A room's lights the same way.
- **The forecast**: a tap on the date and weather shows today big and the next days (Home Assistant's
  weather.get_forecasts).
- **The voice assistant** on the glass, as Siri shows itself: while the Echo listens a glow of colour travels round the
  screen's edge; what you said and the answer rise on a card from the bottom; an alarm or a timer rings on glass over
  the dimmed WallView: a tap snoozes (a timer stops), a hold stops, and the Echo does it (on an Echo Show).
- **The lock screen**: left alone (2 minutes), the WallView rests behind a photo with the time, the date, the weather
  and the next alarm where the photo has room for them; swipe up to open. Its photos are your **Immich** library's, or
  the nature photos that come with the app.

## Photos from Immich

In Home Assistant's Echo-Wall panel: the device › Photos (the address, an API key, an album, how often). On an Echo
Show, Echo Local's "Screen app settings" work too (the panel's win where both are set), one per line:

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

