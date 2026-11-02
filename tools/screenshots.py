#!/usr/bin/env python3
"""Screenshots of hassmic-screen on Echo screens, for the README (docs/screenshots/).

Every model is an Android emulator with that screen's resolution and density (not Fire OS: layouts and resolution are
what this shows, not the Echo's speed); what it shows comes from a Home Assistant with the demo integration (made-up
devices, nothing of anyone's home) and a stand-in for hassmic's config (docs/screen-apps.md in echo-dot-assist),
both forwarded into the emulator with `adb reverse`, as hassmic and Home Assistant would be reached on an Echo.

    python3 tools/screenshots.py --serial emulator-5554 [--ha-python PY] [--only show5,spot] [--apk APK]

  --ha-python  a Python with Home Assistant installed (pip install homeassistant), default: echo-dot-assist's
               build/ha-venv (its tests/ha_real_dropin.py --setup makes one)
  --apk        an x86_64 build (flutter build apk --release --target-platform android-x64), the default path
Needs a running Android emulator adb is authorized for (x86_64, API 34+: its screen is set to each model's by `wm
size`/`wm density` and put back afterwards, the app uninstalled), adb, Pillow; aiohttp.
"""
import argparse, asyncio, json, os, shutil, signal, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SDK = os.environ.get("ANDROID_HOME", os.path.expanduser("~/Android/Sdk"))
ADB, EMU = os.path.join(SDK, "platform-tools", "adb"), os.path.join(SDK, "emulator", "emulator")
HA_PORT, HASSMIC_PORT, SERIAL = 18123, 28931, "emulator-5554"
PKG = "org.hassmic.screen"

# (id, name, width, height, density, density known or estimated, round)
MODELS = [
    ("show5", "Echo Show 5 (all three)", 960, 480, 160, "measured", False),
    ("show8", "Echo Show 8 (1st-3rd gen), Show 10, Echo Hub", 1280, 800, 213, "measured on the 1st gen", False),
    ("show8-2025", "Echo Show 8 (2025)", 1340, 800, 213, "estimated", False),
    ("show11", "Echo Show 11 (2025)", 1920, 1200, 240, "estimated", False),
    ("show15", "Echo Show 15 / 21, landscape", 1920, 1080, 160, "estimated", False),
    ("show15-portrait", "Echo Show 15, hung upright", 1080, 1920, 160, "estimated", False),
    ("show1", "Echo Show (1st gen)", 1024, 600, 160, "estimated", False),
    ("spot", "Echo Spot (1st gen), round", 480, 480, 240, "estimated", True),
    ("spot2024", "Echo Spot (2024)", 320, 240, 120, "estimated", False),
]


def sh(*a, check=True, **kw):
    return subprocess.run(a, check=check, capture_output=True, text=True, **kw).stdout


def adb(*a, check=True):
    return sh(ADB, "-s", SERIAL, *a, check=check)


# ---------------------------------------------------------------- Home Assistant with the demo's things

def ha_start(py, tmp):
    conf = os.path.join(tmp, "ha"); os.makedirs(os.path.join(conf, ".storage"))
    open(os.path.join(conf, "configuration.yaml"), "w").write(
        "homeassistant:\n  name: Home\n  unit_system: metric\n  time_zone: Europe/Berlin\n  latitude: 52.5\n  longitude: 13.4\n"
        "  elevation: 0\n  country: DE\n  internal_url: http://127.0.0.1:%d\nfrontend:\nconfig:\napi:\nonboarding:\ndemo:\n"
        "logger:\n  default: error\n" % HA_PORT)
    json.dump({"version": 2, "minor_version": 2, "key": "http", "data": {
        "stable": {"server_port": HA_PORT, "server_host": ["127.0.0.1"], "cors_allowed_origins": [], "login_attempts_threshold": -1,
                   "ip_ban_enabled": False, "ssl_profile": "modern", "use_x_frame_options": True,
                   "created_at": "2026-10-11T00:00:00+00:00", "error": None, "error_message": None},
        "pending": None, "yaml_migration_done": True}}, open(os.path.join(conf, ".storage", "http"), "w"))
    log = open(os.path.join(tmp, "ha.log"), "w")
    return subprocess.Popen([py, "-m", "homeassistant", "-c", conf, "--skip-pip"], stdout=log, stderr=subprocess.STDOUT, cwd=conf)


async def ha_token():
    """onboarded, and a long-lived token: the kind hassmic's integration gives an Echo"""
    import aiohttp
    base = f"http://127.0.0.1:{HA_PORT}"
    async with aiohttp.ClientSession() as s:
        for _ in range(300):
            try:
                async with s.get(f"{base}/api/onboarding") as r:
                    if r.status == 200: break
            except aiohttp.ClientError: pass
            await asyncio.sleep(0.5)
        async with s.post(f"{base}/api/onboarding/users", json={"client_id": f"{base}/", "name": "Home", "username": "home",
                                                                 "password": "home-home-home", "language": "en"}) as r:
            code = (await r.json())["auth_code"]
        async with s.post(f"{base}/auth/token", data={"grant_type": "authorization_code", "code": code, "client_id": f"{base}/"}) as r:
            tok = (await r.json())["access_token"]
        for step in ("core_config", "analytics", "integration"):
            async with s.post(f"{base}/api/onboarding/{step}", headers={"Authorization": f"Bearer {tok}"},
                              json={"client_id": f"{base}/", "redirect_uri": f"{base}/?auth_callback=1"}) as r: pass
        ws = await s.ws_connect(f"{base}/api/websocket")
        await ws.receive_json(); await ws.send_json({"type": "auth", "access_token": tok}); await ws.receive_json()
        await ws.send_json({"id": 1, "type": "auth/long_lived_access_token", "client_name": "screenshots", "lifespan": 10})
        r = await ws.receive_json()
        await ws.close()
        return r["result"]


# ---------------------------------------------------------------- hassmic's config, as hassmic hands it out

class Hassmic:
    def __init__(self):
        self.cfg = {}
        self.state, self.changed = {"v": 1, "running": False, "words": False, "heard": "", "reply": "", "ringing": "",
                                    "ringing_alarm": False, "h24": False, "clock_set": True,
                                    "next_alarm": {"at": int(time.time()) + 50000, "text": "Alarm 7:30 AM on weekdays", "label": "Gym"},
                                    "display": "always"}, threading.Condition()
        me = self

        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path.startswith("/kiosk/state"):
                    # the long poll: /kiosk/state/<v> waits until the version is another (as hassmic's)
                    want = self.path[len("/kiosk/state/"):] if self.path.startswith("/kiosk/state/") else ""
                    with me.changed:
                        if want.isdigit(): me.changed.wait_for(lambda: me.state["v"] != int(want), timeout=25)
                        b = json.dumps(me.state).encode()
                else:
                    b = json.dumps(me.cfg).encode()
                self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
                self.end_headers(); self.wfile.write(b)

            def log_message(self, *a): pass
        self.srv = ThreadingHTTPServer(("127.0.0.1", HASSMIC_PORT), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def set_state(self, **kw):
        with self.changed:
            self.state = {**self.state, **kw, "v": self.state["v"] + 1}
            self.changed.notify_all()

    def screens(self, token, first, clock=False):
        base = f"http://127.0.0.1:{HA_PORT}"
        s = [{"name": "Home Assistant", "url": f"{base}/lovelace/0"}, {"name": "Map", "url": f"{base}/map"},
             # another origin of the same Home Assistant: no token there, its sign-in page (the keyboard's shot)
             {"name": "Sign in", "url": f"http://localhost:{HA_PORT}/"}]
        s = s[first:] + s[:first]
        if clock: s = [{"name": "Clock", "url": "hassmic:clock"}] + s
        self.cfg = {"enabled": True, "ha": base, "has_token": True, "token": token, "app": PKG, "default": 0, "return": 0, "screens": s}


# ---------------------------------------------------------------- the emulator: one, every model's screen by override

def screen(w, h, dpi):
    """the model's screen on the running emulator: its size and density, turned to fit (wm overrides; screencap then
    gives that size), the app started again for its new metrics"""
    # the override is the display's natural size: no turning on top of it
    adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
    adb("shell", "settings", "put", "system", "user_rotation", "0")
    # Android's "Viewing full screen" tip would cover the first shot (an Echo has no such tip)
    adb("shell", "settings", "put", "secure", "immersive_mode_confirmations", "confirmed")
    # no input method, as on an Echo: the app's own keyboard comes, not the emulator's
    # (Android keeps one enabled while its app is there: the apps themselves off, back on at the end)
    for ime in adb("shell", "ime", "list", "-s", check=False).split():
        pkg = ime.split("/")[0]
        if pkg not in DISABLED:
            adb("shell", "pm", "disable-user", "--user", "0", pkg, check=False); DISABLED.add(pkg)
    adb("shell", "wm", "size", f"{w}x{h}")
    adb("shell", "wm", "density", str(dpi))
    adb("shell", "am", "force-stop", PKG)
    time.sleep(3)


DISABLED = set()


def restore():
    adb("shell", "setprop", "debug.hassmic.round", "0", check=False)
    for pkg in DISABLED: adb("shell", "pm", "enable", pkg, check=False)
    for c in (("wm", "size", "reset"), ("wm", "density", "reset"), ("settings", "put", "system", "accelerometer_rotation", "1"),
              ("settings", "delete", "secure", "immersive_mode_confirmations")):
        adb("shell", *c, check=False)
    adb("uninstall", PKG, check=False)


async def field_center():
    """where the sign-in page's user name field is on the screen (px), through the WebView's debugging socket: the
    page draws it in shadow roots, at a place of its own on every screen size"""
    import aiohttp
    pid = adb("shell", "pidof", PKG).strip().split()[0]
    sh(ADB, "-s", SERIAL, "forward", "tcp:9339", f"localabstract:webview_devtools_remote_{pid}")
    async with aiohttp.ClientSession() as s:
        async with s.get("http://127.0.0.1:9339/json") as r:
            pages = [p for p in await r.json(content_type=None) if p.get("type") == "page"]
        ws = await s.ws_connect(pages[0]["webSocketDebuggerUrl"])
        js = ("(() => { const find = (r) => { const e = r.querySelector('input[name=username],input[autocomplete=username]'); if (e) return e;"
              " for (const n of r.querySelectorAll('*')) if (n.shadowRoot) { const f = find(n.shadowRoot); if (f) return f; } return null; };"
              " const e = find(document); if (!e) return null; const b = e.getBoundingClientRect();"
              " return [(b.left + b.width / 2) * devicePixelRatio, (b.top + b.height / 2) * devicePixelRatio]; })()")
        await ws.send_json({"id": 1, "method": "Runtime.evaluate", "params": {"expression": js, "returnByValue": True}})
        r = await ws.receive_json()
        await ws.close()
    sh(ADB, "-s", SERIAL, "forward", "--remove", "tcp:9339", check=False)
    return (r.get("result", {}).get("result") or {}).get("value")


def shot(path, round_):
    png = subprocess.run([ADB, "-s", SERIAL, "exec-out", "screencap", "-p"], capture_output=True, check=True).stdout
    open(path, "wb").write(png)
    if round_:                                  # the Spot's round glass: what is outside the circle cannot be seen
        from PIL import Image, ImageDraw
        im = Image.open(path).convert("RGBA"); mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, im.size[0] - 1, im.size[1] - 1), fill=255)
        out = Image.new("RGBA", im.size, (0, 0, 0, 0)); out.paste(im, (0, 0), mask); out.save(path)


def main():
    global SERIAL
    ap = argparse.ArgumentParser()
    ap.add_argument("--ha-python", default=os.path.expanduser("~/echo-dot-assist/build/ha-venv/bin/python"))
    ap.add_argument("--apk", default=os.path.join(ROOT, "build/app/outputs/flutter-apk/app-release.apk"))
    ap.add_argument("--serial", default="emulator-5554", help="a running emulator adb is authorized for (x86_64, API 34+)")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    SERIAL = a.serial
    out = os.path.join(ROOT, "docs", "screenshots"); os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="hassmic-shots-")
    ha = ha_start(a.ha_python, tmp)
    try:
        token = asyncio.run(ha_token())
        hm = Hassmic()
        for port in (HA_PORT, HASSMIC_PORT): adb("reverse", f"tcp:{port}", f"tcp:{port}")
        adb("install", "-r", a.apk)
        for m in MODELS:
            if a.only and m[0] not in a.only.split(","): continue
            mid, title, w, h, dpi, _, round_ = m
            print(f"{title}: {w} x {h} @ {dpi}", flush=True)
            adb("shell", "setprop", "debug.hassmic.round", "1" if round_ else "0")      # the app's round layout
            screen(w, h, dpi)
            hm.screens(token, 0)
            adb("shell", "am", "start", "-a", "org.hassmic.action.SCREEN", "-c", "android.intent.category.DEFAULT", PKG)
            time.sleep(25)                      # Home Assistant's frontend in the WebView
            shot(os.path.join(out, f"{mid}-dashboard.png"), round_)
            adb("shell", "input", "tap", str(w // 2), str(max(4, 12 * dpi // 160)))        # the handle
            time.sleep(2)
            shot(os.path.join(out, f"{mid}-switcher.png"), round_)
            hm.screens(token, 2)                # the sign-in page first, its user name field tapped: the keyboard comes
            time.sleep(20)
            at = asyncio.run(field_center())
            if at:
                adb("shell", "input", "tap", str(int(at[0])), str(int(at[1])))
                time.sleep(2)
            shot(os.path.join(out, f"{mid}-keyboard.png"), round_)
            # hassmic's own pictures, drawn by the app (docs/screen-apps.md): the clock, a request, an alarm ringing
            hm.screens(token, 0, clock=True)
            time.sleep(4)
            shot(os.path.join(out, f"{mid}-clock.png"), round_)
            hm.set_state(running=True, words=True, heard="turn on the kitchen lights and dim the living room",
                         reply="Turned on the kitchen lights and set the living room to 30 percent.")
            time.sleep(2)
            shot(os.path.join(out, f"{mid}-request.png"), round_)
            hm.set_state(running=False, words=False, heard="", reply="", ringing="Alarm 7:30 AM", ringing_alarm=True)
            time.sleep(2)
            shot(os.path.join(out, f"{mid}-alarm.png"), round_)
            hm.set_state(ringing="", ringing_alarm=False)
    except Exception:
        print(open(os.path.join(tmp, "ha.log"), errors="replace").read()[-3000:], file=sys.stderr)
        raise
    finally:
        restore()
        ha.send_signal(signal.SIGTERM)
        try: ha.wait(30)
        except subprocess.TimeoutExpired: ha.kill()
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
