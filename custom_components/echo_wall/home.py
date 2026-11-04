"""Echo-Wall's home screens, one per device: kept in Home Assistant, edited in the sidebar panel (frontend/panel.js),
followed live by the app on the device (lib/home/layout_sync.dart), exported to a file and imported again.
docs/integration.md is the whole design.

A *device* is one install of the app: an Echo Show running hassmic, or any Android tablet.  The app makes its id itself
(a random one, kept in its files) and says who it is at every login (echo_wall/register).  The first login binds the
device to the Home Assistant user it logged in as: that user (an Echo's own kiosk user, or the tablet's) may read and
change that device's layout and no other; administrators any.  So no device needs to know any other integration's
names, and an Echo's login cannot touch another device's Home.

Websocket:

    echo_wall/register   {device, name, model?, version?, screen?, screens?}  the device as it is now; binds it
    echo_wall/list                                   admin: the devices, the layout's fields (FIELDS)
    echo_wall/get        {device}                    the layout ({} none yet: the app's own choice)
    echo_wall/set        {device, layout}            replaces it (checked against FIELDS), told to every subscriber
    echo_wall/subscribe  {device}                    the layout now and at every change
    echo_wall/reset      {device}                    the layout gone: the app's own choice again
    echo_wall/forget     {device}                    admin: the device gone with its layout (it registers again)
    echo_wall/rename     {device, name}              admin: the name the panel shows
    echo_wall/apps/set   {device, apps}              the device's Android apps (package, label, icon: base64 PNG):
                                                     their tiles in the panel's preview
    echo_wall/apps/get   {device}                    {apps, updated}
"""
from __future__ import annotations

import json
import logging
import time
from typing import Any

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_connect, async_dispatcher_send
from homeassistant.helpers.storage import Store

from .const import DOMAIN, PREVIEW_URL, SIGNAL, STORE_KEY, STORE_VERSION

_LOGGER = logging.getLogger(__name__)

MAX_LAYOUT = 64 * 1024                  # bytes of JSON a layout may hold (a device's own login writes it)
MAX_IDS = 300                           # entity ids in one list
MAX_DEVICES = 64
MAX_PER_USER = 8                        # devices one non-administrator login may bind
MAX_APPS = 40
DEVICE = vol.All(str, vol.Match(r"^[A-Za-z0-9_-]{8,64}$"))
_id = vol.All(str, vol.Length(max=255))
_ids = vol.All([_id], vol.Length(max=MAX_IDS))

_walls = [["amber", "Amber"], ["dusk", "Dusk"], ["light", "Light"]]
# what a layout holds, as the panel draws its form: the fields Home Assistant checks (the app's own keys besides, as
# "place", "cards", "sizes", "custom_pages", are kept as they come, within the size cap).  `secret`: left out of exports
NAME = "Echo-Wall"
ABOUT = "The home screen of the Echo-Wall app on this device. It sends its layout here as it changes and follows what is saved here."
FIELDS: list[dict] = [
    {"key": "dashboard", "type": "dashboard", "label": "Dashboard after Home",
     "help": "Its sections as pages after Home, drawn in Echo-Wall's glass. None: a page per room. Hold a card on the device to resize "
             "it or take it off a page: that stays on the device, the dashboard is not changed."},
    {"key": "wallpaper", "type": "select", "label": "Wallpaper",
     "options": [["photo", "Photo (Immich)"], *_walls], "default": "photo"},
    {"key": "favorites", "type": "entities", "label": "Home's tiles", "ordered": True, "nullable": True,
     "help": "In order. A thermostat shows big, a camera its picture. Off: Echo-Wall picks."},
    {"key": "analog_clock", "type": "bool", "label": "Analog clock", "default": True},
    {"key": "digital_clock", "type": "bool", "label": "Digital clock", "default": True},
    {"key": "date_card", "type": "bool", "label": "Date", "default": True},
    {"key": "now_playing", "type": "bool", "label": "What plays, on Home", "default": True},
    {"key": "ambient", "type": "number", "label": "Lock screen after untouched", "min": 0, "max": 86400, "step": 10,
     "unit": "s", "default": 120},
    {"key": "hidden", "type": "entities", "label": "Hidden everywhere", "ordered": False},
    {"key": "hidden_screens", "type": "strings", "label": "Screens off Home", "help": "The device's other screens, by name."},
    {"key": "order", "type": "area_order", "label": "Rooms"},
    {"key": "immich_url", "type": "text", "label": "Immich address", "group": "Photos",
     "help": "For the photo wallpaper and the lock screen: https://photos.example.org. On an Echo, the Echo Local integration's screen app settings count where this is empty."},
    {"key": "immich_key", "type": "text", "label": "Immich API key", "group": "Photos", "secret": True,
     "help": "A key with access to the album. Kept in Home Assistant and on the device; never in an export."},
    {"key": "immich_album", "type": "text", "label": "Immich album id", "group": "Photos", "help": "Empty: random photos of the library."},
    {"key": "photos_minutes", "type": "number", "label": "A new photo every", "min": 1, "max": 1440, "unit": "min", "default": 3,
     "group": "Photos"},
]


def check(layout: Any) -> dict:
    """a layout as FIELDS has it: every field it names of its type, the rest kept within the size cap"""
    if not isinstance(layout, dict):
        raise vol.Invalid("a layout is an object")
    out = dict(layout)
    for f in FIELDS:
        k, t = f["key"], f["type"]
        if k not in out:
            continue
        v = out[k]
        if t == "select":
            ok = [o[0] for o in f.get("options", [])]
            if v not in ok:
                raise vol.Invalid(f"{k}: one of {ok}")
        elif t == "number":
            v = vol.Coerce(float)(v)
            if ("min" in f and v < f["min"]) or ("max" in f and v > f["max"]):
                raise vol.Invalid(f"{k}: {f.get('min')}..{f.get('max')}")
            out[k] = int(v) if v == int(v) else v
        elif t == "bool":
            if not isinstance(v, bool):
                raise vol.Invalid(f"{k}: true or false")
        elif t in ("text", "entity", "dashboard"):
            out[k] = _id(v) if v is not None else None
        elif t in ("entities", "strings"):
            if v is None and f.get("nullable"):
                continue
            out[k] = _ids(v)
        elif t == "area_order":
            out[k] = vol.All({_id: _ids}, vol.Length(max=200))(v)
    if len(json.dumps(out, separators=(",", ":"))) > MAX_LAYOUT:
        raise vol.Invalid(f"a layout is {MAX_LAYOUT // 1024} KB at most")
    return out


# ---------------------------------------------------------------- the store

def _data(hass: HomeAssistant) -> dict:
    return hass.data[DOMAIN]


async def async_setup(hass: HomeAssistant) -> None:
    store = Store(hass, STORE_VERSION, STORE_KEY)
    saved = await store.async_load() or {}
    hass.data[DOMAIN] = {"store": store, "devices": saved.get("devices", {}), "layouts": saved.get("layouts", {}),
                         "apps": saved.get("apps", {})}
    for c in (ws_register, ws_list, ws_get, ws_set, ws_subscribe, ws_reset, ws_forget, ws_rename, ws_apps_set, ws_apps_get):
        websocket_api.async_register_command(hass, c)


async def _save(hass: HomeAssistant) -> None:
    d = _data(hass)
    await d["store"].async_save({"devices": d["devices"], "layouts": d["layouts"], "apps": d["apps"]})


def get(hass: HomeAssistant, device: str) -> dict:
    return dict((_data(hass)["layouts"].get(device) or {}).get("layout") or {})


async def put(hass: HomeAssistant, device: str, layout: dict, by: str = "") -> dict:
    layout = check(layout)
    _data(hass)["layouts"][device] = {"layout": layout, "updated": time.time(), "by": by}
    await _save(hass)
    async_dispatcher_send(hass, SIGNAL, device, "layout")
    return layout


# ---------------------------------------------------------------- who may touch which device

def _may(hass: HomeAssistant, connection, msg: dict) -> bool:
    """an administrator any device; anyone else only one bound to them (echo_wall/register).  Refused: the error sent
    (not Unauthorized raised: in an async handler Home Assistant answers that with "unknown_error")"""
    if connection.user.is_admin:
        return True
    dev = _data(hass)["devices"].get(msg["device"])
    if dev and dev.get("user") == connection.user.id:
        return True
    connection.send_error(msg["id"], "unauthorized", "not this login's device")
    return False


def _by(connection) -> str:
    """who saved a layout, for the panel ("panel": an administrator, "app": the device's own login)"""
    return "panel" if connection.user.is_admin else "app"


# ---------------------------------------------------------------- commands

@websocket_api.websocket_command({
    vol.Required("type"): "echo_wall/register", vol.Required("device"): DEVICE,
    vol.Required("name"): vol.All(str, vol.Length(min=1, max=80)),
    vol.Optional("model", default=""): vol.All(str, vol.Length(max=80)),
    vol.Optional("version", default=""): vol.All(str, vol.Length(max=40)),
    vol.Optional("screen"): vol.All([vol.All(vol.Coerce(int), vol.Range(min=100, max=8000))], vol.Length(min=2, max=2)),
    vol.Optional("screens", default=[]): vol.All([vol.All(str, vol.Length(max=60))], vol.Length(max=20)),
    # the id this install had before (the app's lib/device.dart: a random one of an older version): moved to the new
    # one, layout, apps and all, when it is this login's and the new one is not known yet
    vol.Optional("replaces"): DEVICE,
})
@websocket_api.async_response
async def ws_register(hass: HomeAssistant, connection, msg: dict) -> None:
    d = _data(hass)
    dev = d["devices"].get(msg["device"])
    uid = connection.user.id
    old = msg.get("replaces")
    if dev is None and old and old != msg["device"] and old in d["devices"] \
            and (d["devices"][old].get("user") == uid or connection.user.is_admin):
        dev = d["devices"][msg["device"]] = d["devices"].pop(old)
        for k in ("layouts", "apps"):
            if old in d[k]:
                d[k][msg["device"]] = d[k].pop(old)
        _LOGGER.info("device %s is %s now (moved, layout and all)", old, msg["device"])
        async_dispatcher_send(hass, SIGNAL, old, "devices")
    if dev is None:
        if len(d["devices"]) >= MAX_DEVICES:
            connection.send_error(msg["id"], "invalid_format", f"{MAX_DEVICES} devices at most")
            return
        if not connection.user.is_admin and sum(1 for x in d["devices"].values() if x.get("user") == uid) >= MAX_PER_USER:
            connection.send_error(msg["id"], "invalid_format", f"{MAX_PER_USER} devices a login at most")
            return
        dev = d["devices"][msg["device"]] = {"user": uid, "added": time.time(), "name": msg["name"]}
    elif dev.get("user") != uid and not connection.user.is_admin:
        connection.send_error(msg["id"], "unauthorized", "another login's device")   # not taken over by naming its id
        return
    # what the device says of itself; a name given in the panel is kept
    dev.update({"model": msg["model"], "version": msg["version"], "seen": time.time(), "screens": msg["screens"],
                "user_name": connection.user.name or ""})
    if "screen" in msg:
        dev["screen"] = msg["screen"]
    if not dev.get("renamed"):
        dev["name"] = msg["name"]
    await _save(hass)
    async_dispatcher_send(hass, SIGNAL, msg["device"], "devices")
    connection.send_result(msg["id"], {"device": msg["device"], "name": dev["name"]})


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "echo_wall/list"})
@callback
def ws_list(hass: HomeAssistant, connection, msg: dict) -> None:
    d = _data(hass)
    out = []
    for k, dev in d["devices"].items():
        lay = d["layouts"].get(k) or {}
        out.append({"device": k, "name": dev.get("name", k), "model": dev.get("model", ""), "version": dev.get("version", ""),
                    "seen": dev.get("seen", 0), "screen": dev.get("screen"), "screens": dev.get("screens", []),
                    "user": dev.get("user", ""), "user_name": dev.get("user_name", ""), "updated": lay.get("updated", 0), "by": lay.get("by", "")})
    out.sort(key=lambda x: x["name"].lower())
    connection.send_result(msg["id"], {"devices": out, "name": NAME, "about": ABOUT, "fields": FIELDS, "preview": f"{PREVIEW_URL}/index.html",
                                       "limits": {"layout": MAX_LAYOUT, "ids": MAX_IDS}})


_dev = {vol.Required("device"): DEVICE}


@websocket_api.websocket_command({vol.Required("type"): "echo_wall/get", **_dev})
@callback
def ws_get(hass: HomeAssistant, connection, msg: dict) -> None:
    if not _may(hass, connection, msg):
        return
    connection.send_result(msg["id"], get(hass, msg["device"]))


@websocket_api.websocket_command({vol.Required("type"): "echo_wall/set", **_dev, vol.Required("layout"): dict})
@websocket_api.async_response
async def ws_set(hass: HomeAssistant, connection, msg: dict) -> None:
    if not _may(hass, connection, msg):
        return
    if msg["device"] not in _data(hass)["devices"]:
        connection.send_error(msg["id"], "not_found", "no such device: its app registers it")
        return
    try:
        layout = await put(hass, msg["device"], msg["layout"], _by(connection))
    except vol.Invalid as e:
        connection.send_error(msg["id"], "invalid_format", str(e))
        return
    connection.send_result(msg["id"], layout)


@websocket_api.websocket_command({vol.Required("type"): "echo_wall/subscribe", **_dev})
@callback
def ws_subscribe(hass: HomeAssistant, connection, msg: dict) -> None:
    device = msg["device"]
    if not _may(hass, connection, msg):
        return

    @callback
    def changed(dev: str, what: str) -> None:
        if dev == device and what == "layout":
            connection.send_message(websocket_api.event_message(msg["id"], {"layout": get(hass, device), "device": device}))

    connection.subscriptions[msg["id"]] = async_dispatcher_connect(hass, SIGNAL, changed)
    connection.send_result(msg["id"])
    connection.send_message(websocket_api.event_message(msg["id"], {"layout": get(hass, device), "device": device}))


@websocket_api.websocket_command({vol.Required("type"): "echo_wall/reset", **_dev})
@websocket_api.async_response
async def ws_reset(hass: HomeAssistant, connection, msg: dict) -> None:
    if not _may(hass, connection, msg):
        return
    if _data(hass)["layouts"].pop(msg["device"], None) is not None:
        await _save(hass)
        async_dispatcher_send(hass, SIGNAL, msg["device"], "layout")
    connection.send_result(msg["id"])


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "echo_wall/forget", **_dev})
@websocket_api.async_response
async def ws_forget(hass: HomeAssistant, connection, msg: dict) -> None:
    d = _data(hass)
    gone = d["devices"].pop(msg["device"], None)
    d["layouts"].pop(msg["device"], None)
    d["apps"].pop(msg["device"], None)
    if gone is not None:
        await _save(hass)
        async_dispatcher_send(hass, SIGNAL, msg["device"], "layout")
        async_dispatcher_send(hass, SIGNAL, msg["device"], "devices")
    connection.send_result(msg["id"])


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "echo_wall/rename", **_dev,
                                  vol.Required("name"): vol.All(str, vol.Length(min=1, max=80))})
@websocket_api.async_response
async def ws_rename(hass: HomeAssistant, connection, msg: dict) -> None:
    dev = _data(hass)["devices"].get(msg["device"])
    if dev is None:
        connection.send_error(msg["id"], "not_found", "no such device")
        return
    dev["name"], dev["renamed"] = msg["name"].strip(), True
    await _save(hass)
    connection.send_result(msg["id"])


LAUNCHER = vol.All([vol.Schema({
    vol.Required("package"): vol.All(str, vol.Match(r"^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$"), vol.Length(max=120)),
    vol.Required("label"): vol.All(str, vol.Length(max=80)),
    vol.Optional("icon", default=""): vol.All(str, vol.Length(max=64 * 1024), vol.Match(r"^[A-Za-z0-9+/=]*$")),
}, extra=vol.REMOVE_EXTRA)], vol.Length(max=MAX_APPS))


@websocket_api.websocket_command({vol.Required("type"): "echo_wall/apps/set", **_dev, vol.Required("apps"): list})
@websocket_api.async_response
async def ws_apps_set(hass: HomeAssistant, connection, msg: dict) -> None:
    if not _may(hass, connection, msg):
        return
    try:
        apps = LAUNCHER(msg["apps"])
    except vol.Invalid as e:
        connection.send_error(msg["id"], "invalid_format", str(e))
        return
    d = _data(hass)["apps"]
    if (d.get(msg["device"]) or {}).get("apps") != apps:
        d[msg["device"]] = {"apps": apps, "updated": time.time()}
        await _save(hass)
    connection.send_result(msg["id"])


@websocket_api.websocket_command({vol.Required("type"): "echo_wall/apps/get", **_dev})
@callback
def ws_apps_get(hass: HomeAssistant, connection, msg: dict) -> None:
    if not _may(hass, connection, msg):
        return
    a = _data(hass)["apps"].get(msg["device"]) or {}
    connection.send_result(msg["id"], {"apps": a.get("apps", []), "updated": a.get("updated", 0)})


