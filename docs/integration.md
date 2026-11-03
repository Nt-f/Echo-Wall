# The Echo-Wall integration

Echo-Wall is a home screen app for Home Assistant: an Echo Show running hassmic, or any Android tablet. This
integration (`custom_components/echo_wall/`, installed from this repository with HACS) keeps each device's home
screen in Home Assistant and arranges it from a sidebar panel, "Echo-Wall", beside the app itself running in the page.

It knows nothing of any other integration. On an Echo Show, hassmic and the Echo Local integration (echo-dot-assist)
give the app Home Assistant's address and a login and run the Echo's own features (alarms, the voice assistant's words
and rings on the screen, the Echo's other Android apps); here an Echo is one device like any tablet.

## The pieces

| piece | where | what |
|---|---|---|
| store | `home.py` | `echo_wall` in `.storage`: `devices` (who each is, the login it is bound to), `layouts` (one per device), `apps` (each device's Android apps, for the preview) |
| websocket | `home.py` | `echo_wall/*` (below) |
| panel | `frontend/panel.js` | the sidebar panel `/echo-wall`, administrators only |
| preview | `frontend/preview/` | the app's `lib/preview.dart` built for the web by `tools/preview.sh`, served at `/echo_wall/preview/` |
| the app's side | `lib/home/layout_sync.dart`, `lib/device.dart`, `lib/login.dart` | registers, follows its layout, sends its own edits; logs in by itself where there is no hassmic |
| test | `tools/ha_test.py` | all of the above in a real Home Assistant with its demo devices, the panel in headless Chrome |

## Devices

A device is one install of the app (`lib/device.dart`): an id it makes once (20 random letters and digits, kept in the
app's files; a reinstall is a new device) and what it says of itself at every login, `echo_wall/register {device,
name, model, version, screen: [w, h] in logical pixels, screens: its other screens' names}`.

**Who may touch which device.** The first registration binds the device to the Home Assistant user it logged in as.
That login (an Echo's own kiosk user, made by Echo Local; a tablet's own user) may read and write that device's layout
and none other; administrators any. Another login naming the id is refused, so knowing a device's id is not enough to
change its Home. A login binds 8 devices at most, the store 64. Forget (panel) frees the id: the next registration binds
it anew.

**Logging in without hassmic** (`lib/login.dart`). The app asks hassmic's `/kiosk/config` as before; when it does
not answer twice (about five seconds) the device has no hassmic, and the app logs in by itself: Home Assistant's own
login page in a WebView, as Home Assistant's apps do it (IndieAuth with the client id on Home Assistant's own origin,
so nothing to register: `client_id = <ha>/`, `redirect_uri = <ha>/?auth_callback=1`), the code taken off the redirect,
exchanged at `/auth/token`. The refresh token is kept in the app's files; access tokens last 30 minutes, so the app
renews one when Home Assistant refuses it (`Ha.renew`) and every 20 minutes for the cameras' requests
(`Ha.freshToken`). If hassmic answers later after all (it started late), its login takes over.

## Websocket

| command | fields | answer |
|---|---|---|
| `echo_wall/register` | `device`, `name`, `model?`, `version?`, `screen?`, `screens?` | `{device, name}`; binds on the first; a name given in the panel stays |
| `echo_wall/list` | — | admin. `{devices: [{device, name, model, version, seen, screen, screens, user_name, updated, by}], name, about, fields, preview, limits}` |
| `echo_wall/get` | `device` | the layout; `{}` if none (the app's own choice) |
| `echo_wall/set` | `device`, `layout` | the layout as stored (checked against `FIELDS`); every subscriber gets it |
| `echo_wall/subscribe` | `device` | result, then an event `{layout, device}` now and at every change |
| `echo_wall/reset` | `device` | the layout gone: the app's own choice again |
| `echo_wall/forget` | `device` | admin. The device gone with its layout and apps |
| `echo_wall/rename` | `device`, `name` | admin. The name the panel shows |
| `echo_wall/apps/set` | `device`, `apps: [{package, label, icon}]` | the device's Android apps (icon: base64 PNG, 64 dp; 40 at most) |
| `echo_wall/apps/get` | `device` | `{apps, updated}` |

A refusal is the error `unauthorized`, sent by the handler (an `Unauthorized` raised in an async handler reaches the
client as `unknown_error`).

**The layout** is checked against `home.py` `FIELDS`: the panel's form (dashboard, wallpaper, Home's tiles, the
clocks, date, what plays, the lock screen's delay, hidden entities and screens, the rooms' order, and the photos:
`immich_url`, `immich_key` (secret: never in an export), `immich_album`, `photos_minutes`). Keys it does not name are
the app's own (`place`, `sizes`, `cards`, `exclude`, `custom_pages`, `page_order`, `hidden_pages`, `player`) and are kept
as they come under a 64 KB cap. The app keeps keys it does not know too (`Layout.extra`), so a newer integration's field
survives an older app's save. The photo fields win over the Echo Local "screen app settings" an Echo may also have
(`Layout.settingsOver`).

## How the app follows its layout (`lib/home/layout_sync.dart`)

- **At each login**: register, then subscribe. The first event is what Home Assistant has: empty → the app sends its
  own (the first start with this integration, so a layout made before, kept in the app's file, comes along); different
  from its own → it takes Home Assistant's (the panel saved while it was not running), unless its own changed since this
  start and never got through (then its own goes: the last change wins).
- **After each save of its own** (500 ms after the last change): sent, unless it is what just came in.
- **Each later event**: taken, drawn, written to the file without being sent back.
- **Without the integration** (not installed, or Home Assistant still loading it right after a restart: Home
  Assistant answers the websocket's login before custom integrations are loaded) the app keeps its file and asks again
  every 15 s.
- **Its Android apps** go up at each login and when they change, for the preview's tiles.

## The sidebar panel (`frontend/panel.js`)

Registered by `__init__.py` (`panel_custom`, path `echo-wall`, element `echo-wall-panel`, `require_admin`). A plain
custom element, no build step; Home Assistant's theme through its CSS variables, only `hass.connection`.

- **Left**: the devices, each with its model and when it was last seen (a green dot: within ten minutes).
- **Bar**: Save (only with changes), Revert, the status ("Unsaved changes" / "Saved 2 min ago by the device"),
  Import ▾ (a file, another device), Export, Copy to ▾ (another device, every other; their own Immich key kept),
  Device ▾ (Rename, Reset its layout, Forget this device).
- **Form**: a row per field, the photo fields under "Photos" (the key as a password field), "Pages after Home" under
  the dashboard (every page after Home as the preview made it: up and down, rename and delete one's own, take a room or
  a dashboard section off and show it again, add a page), then "All of it, as JSON".
- **Preview**: the app itself at the device's own screen size (as it registered; the Echo Show's and tablets' sizes to
  pick from), scaled to the column. "Edit on the screen" turns the app's own edit mode on (drag, resize, ★, −, + Add,
  + Page; each change lands in the draft and the form follows); "Card sizes" shows every card at every size with this
  Home Assistant's devices. Pages swipe with the mouse, a trackpad, or a click beside the page dots.

A form change redraws the form and the bar only: the iframe stays (rebuilt or moved, it would load again and Flutter
would start over). Each device opened is subscribed; a change from the device while the panel has an unsaved draft is
offered in a banner ("Take the device's" / "Keep mine"), never forced.

## Your dashboard, drawn natively (`lib/lovelace/`)

Asked 2026-11-03 after comparing it with Home Assistant's own UI on the Show (previews:
`build/lovelace-previews/`, made by its `shoot.py` against a demo Home Assistant): Echo-Wall draws a Home Assistant
dashboard itself, in its own glass, instead of Lovelace in a WebView. The layout field **`dashboard`** (the form's
"Dashboard after Home", a list of `lovelace/dashboards/list` plus Overview) names it by url path; empty is a page per
room, as before.

- **Pages.** Home stays Echo-Wall's own (the clocks, date and weather, the favourites, what plays, the screens and apps).
  After it, every section of every view of the dashboard is a page, its heading the page's name (the view's title
  beside it when the dashboard has several views); a section whose heading is an area's name gets that room's chips.
  Then the owner's own pages (edit mode's "+ Page", or the panel's "Pages after Home"). `page_order` moves any of them.
- **Reading it.** `LovelaceSource` asks `lovelace/config {url_path}` over Echo-Wall's own websocket (a device's login (an
  Echo's kiosk user, a tablet's) reads any dashboard not limited to administrators) and again on the event `lovelace_updated` for that
  dashboard: a save in Home Assistant's editor shows on the device at once. A strategy dashboard (Overview never edited:
  Home Assistant makes it up as it draws) has no views to read: Echo-Wall then shows its room pages.
- **Cards.** tile, button, light, sensor, entity: Echo-Wall's tile. thermostat: its thermostat. media-control: its media
  card on that player (`Kind.media`). picture-entity / picture-glance of a camera: its camera card, live. entities,
  glance, weather-forecast: `NativeCard` (a glass list, a row of readings, the weather). Anything else (HACS cards,
  markdown, graphs) is a tile naming the card that opens that view in Home Assistant's own UI on the device
  (`WallView.onDashboard` → `main.dart` `_openPath`); drawing them would take a browser per card, which the Show 5
  cannot afford. Stacks are flattened: their cards become cards of the section.
- **Sizes.** Lovelace's `grid_options` (columns of 12, rows of 56 px) map to Echo-Wall's four sizes (`LCard.cardSize`:
  a half-width one-row tile small, a full-width one wide, three rows or more large, a whole section's worth extra
  large), never Lovelace's half-height strips. Each card then takes the nearest of its own sizes that fits the grid
  (`fitted`). The big cards are placed first, so a thermostat after four tiles still finds its two rows on the page.
- **The Echo's own changes, kept in Echo-Wall's layout, never written into the dashboard** (saving a dashboard needs an
  administrator, the device's login is not one, and the owner's dashboard stays as made): per page group
  (`ll:<view path or index>/<section heading or index>`), `place` (where each card was dragged), `sizes`, `exclude`
  (a card taken off this page here), `cards` (one added here: an entity, Echo-Wall's own clock, date, media, an app).
- **Performance.** The same widgets and glass as Echo-Wall's own pages (the wallpaper blurred once, each card copying
  its piece); the config a few kilobytes, read once and on each save; pages built as they are swiped to. No WebView:
  that is what the Show 5 cannot carry (Home Assistant's UI 150–250 MB against Echo-Wall's 62 MB).

**Holding a card** (`_Hold`, an iPhone's way): half a second shows its menu beside it (an overlay, not a route: a
route would cancel the finger still on the card): Controls, its sizes, Move to… (another page), Edit Home Screen,
Remove from this page. Held on to 1.3 s without moving: the edit mode. An empty place held, or the page dots: the edit
mode too. In the edit mode each card has − (off this page), ★ (on Home) and ⤡ (its next size) as 48 px targets, and a
tap shows its menu. The bar has + Add (to this page: devices, Echo-Wall's own cards, a dashboard card taken off
before), + Page, and on an own page Rename and Delete page, on a room's or a section's Remove page (`hidden_pages`).

**Moving and resizing** (`wall_view.dart` `pack`, `_grid`, `_drop`, `_resize`): a drop keeps every card of the page
group where it is (`place`); a card pushed aside goes to the dragged one's old place, else the free place nearest its
own on its own page, then the pages after, never back to a gap on the group's first page. Held 0.6 s at the screen's
edge the pages turn, across groups: over another group's page the card is drawn where it would land (that group packed
with it), and the drop moves it there as "Move to…" does (`_removeFrom`, `_addTo`, its size with it); a dashboard's
card stays in its section, a screen's tile on Home. Only the card's own group gets an empty page at its end while
dragging, and the page looked at is followed by group and index (`_viewing`), so pages coming and going before it do
not move the view. A resize keeps the card's top-left (moved in only as far as the page's edge makes it) and saves the
group's places (`_commit`). A card taken off pulls the next page's first cards into the room it left (`_pullBack`, one
page ahead); Clear page saves the group's places first and pulls nothing. + Add places the card on the page it was
opened on.

**Thermostats** show what they do: orange heating, blue cooling (the card glows from below in that colour, its line
"Heating to 21°" white over it), "Idle", "Off" dimmed; a heat/cool (dual) one shows its range with the low end orange
and the high blue, "Cooling to 24°" naming the end it works towards, and its arrows move both ends.

**Every card at every size** (`lib/home/gallery.dart`): `test/gallery_test.dart` draws all of them at the Show 5's
cell and fails on any overflow (it found two: the wide media card's buttons, the wide dual thermostat's name);
`test/goldens/cards.png` is the picture, rewritten each run. The panel's preview shows the same gallery with the
Home Assistant's own devices ("Card sizes" under the preview).

## The preview (`frontend/preview/`, `lib/preview.dart`)

The preview is not a re-drawing of the app: it is its own `WallView`, compiled for the web. `tools/preview.sh` runs
`flutter build web -t lib/preview.dart --release --base-href /echo_wall/preview/ --no-web-resources-cdn
--pwa-strategy=none` and copies what a browser loads into `custom_components/echo_wall/frontend/preview/` (17 MB:
CanvasKit, Inter and the stock photos go along, since a Home Assistant may have no internet; no service worker on Home
Assistant's origin), with `BUILT_FROM`. Rerun it after a change to the WallView and commit the result with it: code
and preview live in one repository, so they cannot drift apart.

**One code base for both.** Echo-Wall's files import `lib/io/io.dart` instead of `dart:io`: on the device that is
`dart:io` itself (`io_native.dart`), on the web `io_web.dart`, stand-ins with the same names over the browser's
`fetch` and `WebSocket` (the few members the app uses: `HttpClient.getUrl/openUrl`, headers, `close()`, the response
as a byte stream; `WebSocket.connect/listen/add/close`; a `File` that never exists). Home Assistant is the page's own
origin, so its websocket, camera stills and streams work as on the device; Immich (another origin) only if it allows
CORS, else the stock photos, as when Immich is unreachable on the device. Method channels (Android's) fail on the web
and the app already treats them as optional.

**`lib/preview.dart`** is the web entry point: a `WallView` with `preview: true` (never the lock screen) and an
`editMode` notifier (the panel's switch; the bar's Done turns the switch back off). It takes from the panel, through
`window.parent.echoWallPreview` (same origin):

| from | what | |
|---|---|---|
| `token()` | the panel's own access token (refreshed by `hass.auth` when expired) | asked again when Home Assistant refuses it |
| `layout()` | the draft to start with | |
| `info()` | `{h24, screens, settings, editing, gallery, apps}`: Home Assistant's clock format, the other screens' names (their tiles on Home), the edit switch, the card sizes switch, the device's Android apps (`echo_wall/apps/get`) | |
| message `echo-wall-apps` | those apps, when the panel has them after the preview started | |
| posts `echo-wall-pages` | the pages after Home as the WallView made them, taken off ones too: `[{group, title, kind: own\|room\|dashboard, hidden}]` | the form's "Pages after Home": order (`page_order`), add, rename and delete one's own (`custom_pages`, its `cards`/`place`/`sizes` with it), take a room or dashboard section off and show it again (`hidden_pages`) |
| message `echo-wall-layout` | a new draft (the form changed) | applied without being sent back |
| message `echo-wall-editmode` | the switch | |
| posts `echo-wall-edit` | the layout after an edit in the preview (Echo-Wall's own save, 500 ms after the last change) | the panel's draft |

Objects of the panel's frame are read through `JSON.stringify` (`dartify()` and `isA<JSObject>()` know only the
frame's own `Object`), and every message is checked against `location.origin`. The preview turns on Flutter's
semantics tree, so the browser's accessibility nodes name what is drawn (and the test finds the tiles by name).


## Export and import

**The file** (`<device>.echowall.json`): `{"format": "echo-wall-home", "version": 1, "app": "io.github.nt_f.echowall",
"device": …, "device_name": …, "exported": …, "layout": {…}}`, the layout whole except the secret fields. **Import**
reads these and Echo Local's `.echohome.json` files of Echo-Wall (`format: "echo-local-home"`, `app` Echo-Wall's): the
layout into the draft, this device's own Immich key kept; Save sends it. Entities this Home Assistant lacks are counted
in the message and kept.

## From Echo Local

Until 2026-11-03 Echo-Wall's layouts lived in Echo Local (echo-dot-assist's integration, `echo_local/home/*`, its
store `echo_local.wall`). Echo-Wall became an app of its own, installable on any tablet, so its integration moved here
and Echo Local kept what is hassmic's (alarms, the screen's setup, the Echo's apps). No store is migrated: at its first
login to this integration the app finds nothing here and sends the layout it kept in its own file, which is the last
one Echo Local had. `echo_local.wall` stays in `.storage` unused; an Echo Local export file imports here.

**Order of an update** on an Echo: install this integration (HACS, custom repository) and add it; then update Echo
Local (its home screen part removed); then the app. An app of before this split asks `echo_local/home/*` and keeps its
file while that is gone; one after it asks `echo_wall/*` and waits (every 15 s) until it is there.

## What was decided and why

- **A device, not an Echo.** The app runs on tablets too, so the integration may not know hassmic's nodes: the app
  names itself, and the login binds it.
- **The login decides, not a parameter.** A non-administrator reaches only devices bound to it; the id alone opens
  nothing.
- **The preview is the app.** What the owner arranges is what the device shows, grid and all; the price is 17 MB in
  the integration, rebuilt with the app.
- **A fixed set of checked fields, everything else kept.** The app's own keys (where each card was dragged) are kept as
  they come under a size cap; the app keeps keys it does not know, so either side may be the newer.
- **A draft and Save** in the panel, not saving each change: the owner tries things against the preview and the device
  should not flicker through them.

## Limits and open ends

- 64 KB a layout, 300 ids a list, 64 devices, 8 a login, 40 apps a device.
- The preview's photos are the app's stock ones (Immich only if it answers the browser with CORS headers).
- No undo beyond Revert; the export file is the backup.
- The panel is administrators only; others arrange their device's Home on the device itself.
