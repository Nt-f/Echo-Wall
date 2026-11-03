"""Echo-Wall: the home screen app (Nt-f/Echo-Wall) in Home Assistant.  Each device's layout (home.py), the sidebar
panel "Echo-Wall" that arranges them (frontend/panel.js) beside the app itself built for the web (frontend/preview/,
tools/preview.sh), followed live by the app on every device.  Nothing of any other integration: an Echo Show running
hassmic is a device as any tablet is (docs/integration.md)."""
from __future__ import annotations

from pathlib import Path

from homeassistant.components import frontend, panel_custom
from homeassistant.components.http import StaticPathConfig
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant

from . import home
from .const import DOMAIN, PANEL_PATH, PANEL_URL, PREVIEW_URL

_STATIC = DOMAIN + "_static"


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    if DOMAIN not in hass.data:
        await home.async_setup(hass)            # the websocket commands stay registered once made
    if not hass.data.get(_STATIC):
        fe = Path(__file__).parent / "frontend"
        await hass.http.async_register_static_paths([StaticPathConfig(PANEL_URL, str(fe / "panel.js"), False),
                                                     StaticPathConfig(PREVIEW_URL, str(fe / "preview"), False)])
        hass.data[_STATIC] = True
    version = entry.version
    await panel_custom.async_register_panel(hass, webcomponent_name="echo-wall-panel", frontend_url_path=PANEL_PATH,
                                            module_url=f"{PANEL_URL}?v={_mtime()}", sidebar_title="Echo-Wall",
                                            sidebar_icon="mdi:tablet-dashboard", require_admin=True, config={"v": version})
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    frontend.async_remove_panel(hass, PANEL_PATH)
    return True


def _mtime() -> int:
    """the panel's file time: a new version is fetched, not the browser's cached one"""
    try:
        return int((Path(__file__).parent / "frontend" / "panel.js").stat().st_mtime)
    except OSError:
        return 0
