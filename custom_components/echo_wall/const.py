"""Echo-Wall's integration: constants (docs/integration.md has the design)."""
DOMAIN = "echo_wall"
PANEL_PATH = "echo-wall"                      # the sidebar panel's address: /echo-wall
PANEL_URL = "/echo_wall/panel.js"             # its custom element (frontend/panel.js)
PREVIEW_URL = "/echo_wall/preview"            # Echo-Wall built for the web (frontend/preview/, tools/preview.sh)
STORE_KEY = "echo_wall"
STORE_VERSION = 1
SIGNAL = "echo_wall_changed"                  # (device, what): "layout" or "devices"
