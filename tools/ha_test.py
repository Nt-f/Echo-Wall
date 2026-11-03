#!/usr/bin/env python3
"""The Echo-Wall integration (custom_components/echo_wall; docs/integration.md) in a real Home Assistant, with its demo
devices, and its panel in headless Chrome:

  - set up from the integrations page (one entry), the panel and the preview served, administrators only
  - a device registered by its own login (a user that is no administrator, logged in as the app does: Home Assistant's
    own login flow, an authorization code, tokens): bound to that login; another login cannot take it, read it or
    write it; the list only for administrators
  - the layout checked (a wallpaper there is none of, the size cap), kept as it comes otherwise (the app's own keys)
  - the app's first login with nothing in Home Assistant: its own file goes up (layout_sync.dart), and the panel's
    saves come to the app as events
  - its Android apps, rename, reset, forget
  - the panel: the device listed, the form, Echo-Wall itself as the preview drawing this Home Assistant's devices,
    Save, Export (no Immich key in it), Import of an Echo Local .echohome.json, the pages after Home

    python3 tools/ha_test.py           Home Assistant's Python: ECHO_WALL_HA_PYTHON, else ../echo-dot-assist/build/ha-venv
                                       (echo-dot-assist's tests/ha_real_dropin.py --setup makes it); screenshots in
                                       build/ha-test/
Runs in a network namespace of its own (unshare -rn): Home Assistant on 127.0.0.1:18124 only."""
import asyncio, base64, json, os, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HA_PY = os.environ.get("ECHO_WALL_HA_PYTHON") or os.path.join(ROOT, "..", "echo-dot-assist", "build", "ha-venv", "bin", "python")
PORT = 18124
HA = f"http://127.0.0.1:{PORT}"
SHOTS = os.path.join(ROOT, "build", "ha-test")
DEV = "dev_test_0001"
ICON = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGN4YGAARwzEcQATUhQB4NTEHgAAAABJRU5ErkJggg=="
failed = False


def check(cond, what):
    global failed
    print(("ok   " if cond else "FAIL ") + what, flush=True)
    if not cond: failed = True


def write_config(conf):
    os.makedirs(os.path.join(conf, ".storage"))
    os.makedirs(os.path.join(conf, "custom_components"))
    os.symlink(os.path.join(ROOT, "custom_components", "echo_wall"), os.path.join(conf, "custom_components", "echo_wall"))
    open(os.path.join(conf, "configuration.yaml"), "w").write(
        "homeassistant:\n  name: Test\n  unit_system: metric\n  time_zone: UTC\n  latitude: 0\n  longitude: 0\n  elevation: 0\n"
        "  country: DE\n  internal_url: http://127.0.0.1:%d\napi:\nconfig:\nonboarding:\nlogger:\n  default: warning\ndemo:\n" % PORT)
    json.dump({"version": 2, "minor_version": 2, "key": "http", "data": {
        "stable": {"server_port": PORT, "server_host": ["127.0.0.1"], "cors_allowed_origins": [], "login_attempts_threshold": -1,
                   "ip_ban_enabled": False, "ssl_profile": "modern", "use_x_frame_options": True,
                   "created_at": "2026-10-11T00:00:00+00:00", "error": None, "error_message": None},
        "pending": None, "yaml_migration_done": True}}, open(os.path.join(conf, ".storage", "http"), "w"))


class Ws:
    """one websocket login"""
    def __init__(self): self.n = 0

    @classmethod
    async def open(cls, session, token):
        w = cls()
        w.sock = await session.ws_connect(f"{HA}/api/websocket", max_msg_size=0)
        await w.sock.receive_json(); await w.sock.send_json({"type": "auth", "access_token": token})
        w.ok = (await w.sock.receive_json()).get("type") == "auth_ok"
        w.events = []
        return w

    async def __call__(self, **msg):
        self.n += 1; i = self.n
        await self.sock.send_json({"id": i, **msg})
        while True:
            r = await self.sock.receive_json()
            if r.get("type") == "event": self.events.append(r); continue
            if r.get("id") == i: break
        if not r.get("success"): raise RuntimeError(json.dumps(r.get("error")))
        return r.get("result")

    async def fails(self, **msg):
        try: await self(**msg); return ""
        except RuntimeError as e: return str(e)

    async def subscribe(self, **msg):
        self.n += 1
        await self.sock.send_json({"id": self.n, **msg})

    async def event(self, secs=5, want=None):
        """the next event (`want`: the next one it is true of; those before it dropped)"""
        while self.events:
            r = self.events.pop(0)
            if want is None or want(r): return r
        try:
            while True:
                r = await asyncio.wait_for(self.sock.receive_json(), secs)
                if r.get("type") == "event" and (want is None or want(r)): return r
        except asyncio.TimeoutError:
            return None


async def onboard(session):
    async with session.post(f"{HA}/api/onboarding/users", json={"client_id": f"{HA}/", "name": "Test", "username": "test",
                                                                "password": "test-test-test", "language": "en"}) as r:
        code = (await r.json())["auth_code"]
    async with session.post(f"{HA}/auth/token", data={"grant_type": "authorization_code", "code": code, "client_id": f"{HA}/"}) as r:
        tok = (await r.json())["access_token"]
    for step in ("core_config", "analytics"):
        async with session.post(f"{HA}/api/onboarding/{step}", headers={"Authorization": f"Bearer {tok}"}, json={}) as r: pass
    async with session.post(f"{HA}/api/onboarding/integration", headers={"Authorization": f"Bearer {tok}"},
                            json={"client_id": f"{HA}/", "redirect_uri": f"{HA}/?auth_callback=1"}) as r: pass
    return tok


async def login(session, username, password):
    """Home Assistant's login flow as the app runs it (lib/login.dart): client id and redirect on HA's own origin, an
    authorization code, then tokens (access + refresh)"""
    cid, redirect = f"{HA}/", f"{HA}/?auth_callback=1"
    async with session.post(f"{HA}/auth/login_flow", json={"client_id": cid, "handler": ["homeassistant", None], "redirect_uri": redirect}) as r:
        flow = await r.json()
    async with session.post(f"{HA}/auth/login_flow/{flow['flow_id']}", json={"username": username, "password": password, "client_id": cid}) as r:
        res = await r.json()
    async with session.post(f"{HA}/auth/token", data={"grant_type": "authorization_code", "code": res["result"], "client_id": cid}) as r:
        return await r.json()


async def user(admin, name, username):
    u = await admin(type="config/auth/create", name=name, group_ids=["system-users"], local_only=True)
    await admin(type="config/auth_provider/homeassistant/create", user_id=u["user"]["id"], username=username, password="pw-" + username)


async def browser(session, token):
    chrome = shutil.which("google-chrome") or shutil.which("chromium") or shutil.which("chromium-browser")
    if not chrome:
        print("note: no Chrome here, the panel is not drawn"); return None
    prof = tempfile.mkdtemp(prefix="echo-wall-chrome-")
    proc = subprocess.Popen([chrome, "--headless=new", "--no-sandbox", "--disable-gpu", "--remote-debugging-port=9335",
                             f"--user-data-dir={prof}", "--window-size=1500,1000", "--force-device-scale-factor=1", "about:blank"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out = {}
    try:
        for _ in range(100):
            try:
                async with session.get("http://127.0.0.1:9335/json") as r:
                    tabs = await r.json(); break
            except Exception: await asyncio.sleep(0.2)
        page = next(t for t in tabs if t.get("type") == "page")
        ws = await session.ws_connect(page["webSocketDebuggerUrl"], max_msg_size=0)
        n = [0]
        async def cdp(method, **params):
            n[0] += 1; i = n[0]
            await ws.send_json({"id": i, "method": method, "params": params})
            while True:
                m = await ws.receive_json()
                if m.get("id") == i: return m.get("result", m.get("error"))
        async def js(expr):
            r = await cdp("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
            if r and r.get("exceptionDetails"): return {"error": json.dumps(r["exceptionDetails"])[:400]}
            return (r.get("result") or {}).get("value")
        async def shot(name):
            r = await cdp("Page.captureScreenshot", format="png")
            if r and r.get("data"):
                os.makedirs(SHOTS, exist_ok=True); open(os.path.join(SHOTS, name + ".png"), "wb").write(base64.b64decode(r["data"]))
        await cdp("Page.enable"); await cdp("Runtime.enable")
        await cdp("Emulation.setDeviceMetricsOverride", width=1500, height=1000, deviceScaleFactor=1, mobile=False)
        await cdp("Page.navigate", url=f"{HA}/echo_wall/x-404"); await asyncio.sleep(1)
        tokens = {"access_token": token, "token_type": "Bearer", "expires_in": 1800, "hassUrl": HA, "clientId": HA + "/",
                  "expires": 4102444800000, "refresh_token": ""}
        await js(f"localStorage.setItem('hassTokens', {json.dumps(json.dumps(tokens))})")
        await cdp("Page.navigate", url=f"{HA}/echo-wall")
        find = """(() => { const walk = (r) => { if (!r) return null; const p = r.querySelector('echo-wall-panel'); if (p) return p;
            for (const e of r.querySelectorAll('*')) { if (e.shadowRoot) { const f = walk(e.shadowRoot); if (f) return f; } } return null; };
            return walk(document); })()"""
        labels = f"""(() => {{ const f = {find}.shadowRoot.querySelector('iframe'); const d = f && f.contentDocument; if (!d) return [];
            return [...d.querySelectorAll('flt-semantics')].map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean); }})()"""
        for _ in range(120):
            await asyncio.sleep(0.5)
            out = await js(f"""(() => {{ const p = {find}; if (!p) return {{}}; const r = p.shadowRoot;
                const f = r.querySelector('iframe'); const d = f && f.contentDocument;
                return {{ devices: [...r.querySelectorAll('nav .echo .t')].map(e => e.textContent), fields: r.querySelectorAll('.card .row').length,
                         groups: [...r.querySelectorAll('.card h3.group')].map(e => e.textContent), secret: !!r.querySelector('input[type=password]'),
                         flutter: !!(d && d.querySelector('flutter-view')) }}; }})()""") or {}
            out["labels"] = await js(labels) or []
            if out.get("flutter") and len(out["labels"]) > 3: break
        await asyncio.sleep(2)
        out["labels"] = await js(labels) or []
        out["dirty_at_start"] = await js(f"(() => {find}.dirty())()")
        out["pages"] = await js(f"""(async () => {{ const p = {find}; for (let i = 0; i < 40 && !p.pages; i++) await new Promise(r => setTimeout(r, 250));
            return (p.pages || []).map(x => x.title); }})()""")
        await shot("panel")
        # a field changed, saved: the device's login gets it (checked by the caller)
        out["saved"] = await js(f"""(async () => {{ const p = {find}; p.cur().draft.wallpaper = 'dusk'; p.cur().draft.immich_key = 'secret-key'; p.changed(true);
            await new Promise(r => setTimeout(r, 300)); p.shadowRoot.querySelector('.bar .primary').click();
            await new Promise(r => setTimeout(r, 1500)); return {{ dirty: p.dirty(), status: p.shadowRoot.querySelector('.bar .status').textContent }}; }})()""")
        out["export"] = await js(f"""(async () => {{ const p = {find}; const o = URL.createObjectURL;
            let text = null; URL.createObjectURL = (b) => {{ b.text().then(t => text = t); return 'blob:x'; }};
            p.exportFile(); URL.createObjectURL = o; for (let i = 0; i < 20 && !text; i++) await new Promise(r => setTimeout(r, 100));
            return JSON.parse(text); }})()""")
        # an Echo Local export of Echo-Wall's Home, as the panel there wrote them
        old = {"format": "echo-local-home", "version": 1, "app": "io.github.nt_f.echowall", "echo_name": "Echo Show 5 a1b2c3",
               "layout": {"wallpaper": "light", "favorites": ["light.ceiling_lights"], "analog_clock": False}}
        out["import"] = await js(f"""(async () => {{ const p = {find}; const doc = {json.dumps(old)};
            p.take(doc.layout, doc.echo_name); await new Promise(r => setTimeout(r, 500));
            return {{ draft: p.cur().draft, dirty: p.dirty() }}; }})()""")
        await shot("panel-import")
        await js(f"(() => {{ const p = {find}; p.cur().draft = JSON.parse(JSON.stringify(p.cur().saved)); p.changed(true); }})()")
        return out
    finally:
        proc.terminate(); shutil.rmtree(prof, ignore_errors=True)


async def run(tmp):
    import aiohttp
    conf = os.path.join(tmp, "ha")
    write_config(conf)
    halog = open(os.path.join(tmp, "ha.log"), "w")
    hass = subprocess.Popen([HA_PY, "-m", "homeassistant", "-c", conf, "--skip-pip"], stdout=halog, stderr=subprocess.STDOUT, cwd=conf)
    try:
        async with aiohttp.ClientSession() as session:
            for _ in range(600):
                try:
                    async with session.get(f"{HA}/api/onboarding") as r:
                        if r.status == 200: break
                except aiohttp.ClientError: pass
                await asyncio.sleep(0.5)
            tok = await onboard(session)
            hdr = {"Authorization": f"Bearer {tok}"}
            async with session.post(f"{HA}/api/config/config_entries/flow", headers=hdr, json={"handler": "echo_wall"}) as r: f = await r.json()
            async with session.post(f"{HA}/api/config/config_entries/flow/{f['flow_id']}", headers=hdr, json={}) as r: f = await r.json()
            check(f.get("type") == "create_entry", f"Echo-Wall added from the integrations page ({f.get('type')})")
            async with session.post(f"{HA}/api/config/config_entries/flow", headers=hdr, json={"handler": "echo_wall"}) as r: f2 = await r.json()
            check(f2.get("type") == "abort", "... once only")
            await asyncio.sleep(1)
            admin = await Ws.open(session, tok)
            panels = await admin(type="get_panels")
            check((panels.get("echo-wall") or {}).get("require_admin") is True, "the sidebar panel, administrators only")
            for path in ("/echo_wall/panel.js", "/echo_wall/preview/index.html", "/echo_wall/preview/main.dart.js"):
                async with session.get(f"{HA}{path}") as r: check(r.status == 200, f"{path} served")

            # a device's own login, as the app makes it: not an administrator, Home Assistant's login flow
            await user(admin, "Kitchen tablet", "kitchen")
            await user(admin, "Hall tablet", "hall")
            t1 = await login(session, "kitchen", "pw-kitchen")
            check(bool(t1.get("access_token") and t1.get("refresh_token")), "the app's login: an authorization code, then access and refresh tokens")
            async with session.post(f"{HA}/auth/token", data={"grant_type": "refresh_token", "refresh_token": t1["refresh_token"], "client_id": f"{HA}/"}) as r:
                t1b = await r.json()
            check(bool(t1b.get("access_token")), "... a new access token from the refresh token (they last 30 minutes)")
            k = await Ws.open(session, t1b["access_token"])
            r = await k(type="echo_wall/register", device=DEV, name="Kitchen", model="Fire HD 10", version="1.0.0", screen=[1280, 800],
                        screens=["Home Assistant", "Music"])
            check(r == {"device": DEV, "name": "Kitchen"}, f"a device registers itself ({r})")
            check((await k(type="echo_wall/get", device=DEV)) == {}, "its layout: none yet (the app's own choice)")
            e = await k.fails(type="echo_wall/list")
            check("unauthorized" in e.lower(), "the list: administrators only")
            hall = await Ws.open(session, (await login(session, "hall", "pw-hall"))["access_token"])
            e = await hall.fails(type="echo_wall/register", device=DEV, name="Mine now")
            check("unauthorized" in e.lower(), f"another login cannot take that device by naming it ({e or 'it could'})")
            e = await hall.fails(type="echo_wall/get", device=DEV)
            check("unauthorized" in e.lower(), "... nor read it")
            e = await hall.fails(type="echo_wall/set", device=DEV, layout={"wallpaper": "dusk"})
            check("unauthorized" in e.lower(), "... nor write it")
            e = await k.fails(type="echo_wall/set", device=DEV, layout={"wallpaper": "neon"})
            check("one of" in e, "a wallpaper there is none of: refused")
            e = await k.fails(type="echo_wall/set", device=DEV, layout={"place": {"x": "y" * 70000}})
            check("64 KB" in e, "over the size cap: refused")

            # the app's first login with nothing here: its file goes up (layout_sync.dart's first event), the panel follows
            await k.subscribe(type="echo_wall/subscribe", device=DEV)
            first = await k.event()
            check(first and first["event"]["layout"] == {}, "the app's subscription: what Home Assistant has (nothing)")
            mine = {"wallpaper": "amber", "favorites": ["light.kitchen_lights"], "place": {"home": {"clock": [0, 0, 0]}}, "custom_pages": [{"id": "p1", "name": "Mine"}]}
            got = await k(type="echo_wall/set", device=DEV, layout=mine)
            check(got == mine, "... so it sends its own file; the app's own keys kept as they come")
            await admin.subscribe(type="echo_wall/subscribe", device=DEV)
            ev = await admin.event()
            check(ev and ev["event"]["layout"] == mine, "an administrator follows it")
            await admin(type="echo_wall/set", device=DEV, layout={**mine, "wallpaper": "light"})
            ev = await k.event(want=lambda r: r["event"]["layout"].get("wallpaper") == "light")
            check(ev is not None, "the panel's save reaches the app at once")
            await k(type="echo_wall/apps/set", device=DEV, apps=[{"package": "org.schabi.newpipe", "label": "NewPipe", "icon": ICON}])
            a = await admin(type="echo_wall/apps/get", device=DEV)
            check([x["label"] for x in a["apps"]] == ["NewPipe"], "its Android apps, for the preview")
            lst = await admin(type="echo_wall/list")
            d0 = lst["devices"][0] if lst["devices"] else {}
            check(d0.get("name") == "Kitchen" and d0.get("model") == "Fire HD 10" and d0.get("screen") == [1280, 800] and d0.get("by") == "panel"
                  and any(f["key"] == "immich_key" and f.get("secret") for f in lst["fields"]),
                  f"the list: the device as it said, who saved last, the fields ({ {k: d0.get(k) for k in ('name', 'model', 'screen', 'by')} })")
            await admin(type="echo_wall/rename", device=DEV, name="Kitchen wall")
            await k(type="echo_wall/register", device=DEV, name="Kitchen", model="Fire HD 10")
            lst = await admin(type="echo_wall/list")
            check(lst["devices"][0]["name"] == "Kitchen wall", "a name given in the panel stays through the app's next login")

            out = await browser(session, tok)
            if out is not None:
                check(out.get("devices") == ["Kitchen wall"] and out.get("fields", 0) >= 12 and out.get("groups") == ["Photos"] and out.get("secret"),
                      f"the panel: the device, the form with its Photos part, the key as a password ({out.get('devices')}, {out.get('fields')}, {out.get('groups')})")
                lab = " ".join(out.get("labels") or [])
                check(out.get("flutter") and ("Kitchen" in lab or "Living Room" in lab or "Ceiling" in lab),
                      f"Echo-Wall itself as the preview, with this Home Assistant's devices ({(out.get('labels') or [])[:8]})")
                check(out.get("dirty_at_start") is False, "opened, nothing changed: no unsaved changes (the preview's remembered player is no edit)")
                check("Mine" in (out.get("pages") or []), f"the pages after Home, from the preview (the device's own page among them: {out.get('pages')})")
                ev = await k.event(want=lambda r: r["event"]["layout"].get("wallpaper") == "dusk")
                check((out.get("saved") or {}).get("dirty") is False and ev is not None,
                      f"Save in the panel: the app gets it ({out.get('saved')})")
                x = out.get("export") or {}
                check(x.get("format") == "echo-wall-home" and x.get("layout", {}).get("wallpaper") == "dusk" and "immich_key" not in x.get("layout", {}),
                      f"Export: the file, without the Immich key ({ {k: x.get(k) for k in ('format', 'device_name')} })")
                im = out.get("import") or {}
                check((im.get("draft") or {}).get("wallpaper") == "light" and (im.get("draft") or {}).get("immich_key") == "secret-key" and im.get("dirty"),
                      "Import of an Echo Local .echohome.json: the layout, this device's key kept, Save offered")

            await k(type="echo_wall/reset", device=DEV)
            check((await admin(type="echo_wall/get", device=DEV)) == {}, "reset: the app's own choice again")
            e = await k.fails(type="echo_wall/forget", device=DEV)
            check("unauthorized" in e.lower(), "forget: administrators only")
            await admin(type="echo_wall/forget", device=DEV)
            check((await admin(type="echo_wall/list"))["devices"] == [], "forgotten: gone from the list")
            r = await hall(type="echo_wall/register", device=DEV, name="Hall")
            check(r["name"] == "Hall", "... and free for whoever registers it next")
            errs = [l for l in open(os.path.join(tmp, "ha.log")).read().splitlines() if "echo_wall" in l and ("ERROR" in l or "Traceback" in l)]
            check(not errs, f"no errors of echo_wall in Home Assistant's log ({errs[:3]})")
    finally:
        hass.terminate()
        try: hass.wait(30)
        except subprocess.TimeoutExpired: hass.kill()


def main():
    if os.environ.get("ECHO_WALL_IN_NETNS") != "1":
        if not os.path.exists(HA_PY):
            print(f"skipped: no Home Assistant at {HA_PY} (ECHO_WALL_HA_PYTHON)"); sys.exit(0)
        env = dict(os.environ, ECHO_WALL_IN_NETNS="1")
        sys.exit(subprocess.run(["unshare", "-rn", HA_PY, os.path.abspath(__file__), *sys.argv[1:]], env=env).returncode)
    subprocess.run(["ip", "link", "set", "lo", "multicast", "on", "up"], check=True)
    subprocess.run(["ip", "route", "add", "224.0.0.0/4", "dev", "lo"], check=True)
    tmp = tempfile.mkdtemp(prefix="echo-wall-ha-")
    try: asyncio.run(run(tmp))
    finally:
        if failed: shutil.copy(os.path.join(tmp, "ha.log"), os.path.join(ROOT, "build", "ha-test.log")) if os.path.isdir(os.path.join(ROOT, "build")) else None
        shutil.rmtree(tmp, ignore_errors=True)
    print("FAILED" if failed else "all good")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
