"""One entry, nothing to ask: the panel and the devices' layouts (a device adds itself when its app logs in)."""
from __future__ import annotations

from homeassistant import config_entries

from .const import DOMAIN


class EchoWallFlow(config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_user(self, user_input=None):
        if self._async_current_entries():
            return self.async_abort(reason="single_instance_allowed")
        if user_input is not None:
            return self.async_create_entry(title="Echo-Wall", data={})
        return self.async_show_form(step_id="user")
