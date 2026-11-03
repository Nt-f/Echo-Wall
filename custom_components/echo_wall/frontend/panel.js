// Echo-Wall's sidebar panel (/echo-wall, registered in __init__.py; docs/integration.md has the design): every device
// running the Echo-Wall app, and its home screen, arranged graphically.
//
//   - left: the devices (each adds itself when its app logs in: home.py echo_wall/register)
//   - a form of the layout's fields (home.py FIELDS) beside a preview: Echo-Wall's own WallView built for the web
//     (frontend/preview/, the app's lib/preview.dart) in an iframe, whose edit mode (drag, resize, star, hide) edits
//     the draft here; the pages after Home listed, added, deleted, ordered
//   - Export (a .echowall.json file; Echo Local's .echohome.json files of Echo-Wall are read too), Import (a file,
//     another device), Copy to other devices, Reset (the layout gone: the app's own choice), Forget (the device gone)
//
// Only Home Assistant's websocket (this.hass.connection), as the rest of Home Assistant's own panels.  Nothing of the
// layout is saved until Save: a draft per device, and the device's own changes meanwhile are offered, not forced.
// Plain custom element, no build step (the integration's frontend files are served as they are).
'use strict';

const FORMAT = 'echo-wall-home';
const LEGACY = 'echo-local-home';                 // Echo Local's exports, of before Echo-Wall had its own integration
const ECHOWALL = 'io.github.nt_f.echowall';
// a device's window in Flutter's logical pixels where it did not say (the Show 5: 960 x 480 at density 160, the light
// band's rows off)
const SIZES = { 'Echo Show 5': [960, 470], 'Echo Show 8': [1280, 790], 'Echo Show': [1024, 590], 'Tablet 10″': [1280, 800], 'Tablet 8″': [1024, 640] };

const h = (tag, props, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k === 'style') e.style.cssText = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k in e && typeof v !== 'string') e[k] = v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat(Infinity)) if (c != null && c !== false) e.append(c.nodeType ? c : document.createTextNode(String(c)));
  return e;
};
const clone = (x) => JSON.parse(JSON.stringify(x == null ? {} : x));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const ago = (t) => {
  if (!t) return '';
  const s = Math.round(Date.now() / 1000 - t);
  return s < 60 ? 'just now' : s < 3600 ? `${Math.round(s / 60)} min ago` : s < 86400 ? `${Math.round(s / 3600)} h ago` : new Date(t * 1000).toLocaleDateString();
};
const domainOf = (id) => String(id).split('.')[0];
const CSS = `
:host { display: block; height: 100%; background: var(--primary-background-color); color: var(--primary-text-color);
  font-family: var(--ha-font-family-body, Roboto, sans-serif); --r: var(--ha-card-border-radius, 12px);
  --line: var(--divider-color, rgba(127,127,127,.25)); --soft: var(--secondary-background-color, rgba(127,127,127,.08));
  --accent: var(--primary-color, #03a9f4); --muted: var(--secondary-text-color, #888); }
* { box-sizing: border-box; }
header { height: var(--header-height, 56px); display: flex; align-items: center; gap: 8px; padding: 0 12px;
  background: var(--app-header-background-color, var(--primary-color)); color: var(--app-header-text-color, #fff);
  border-bottom: var(--app-header-border-bottom, none); position: sticky; top: 0; z-index: 3; }
header h1 { font-size: 20px; font-weight: 400; margin: 0 0 0 4px; flex: 1; }
header .menu { display: none; }
:host([narrow]) header .menu { display: inline-flex; }
.iconbtn { background: none; border: 0; color: inherit; width: 40px; height: 40px; border-radius: 50%; cursor: pointer; font-size: 22px; }
.iconbtn:hover { background: rgba(127,127,127,.15); }
.wrap { display: grid; grid-template-columns: 260px 1fr; min-height: calc(100% - var(--header-height, 56px)); }
:host([narrow]) .wrap { grid-template-columns: 1fr; }
nav { border-right: 1px solid var(--line); padding: 12px 8px; background: var(--card-background-color); }
:host([narrow]) nav { border-right: 0; border-bottom: 1px solid var(--line); display: flex; overflow-x: auto; gap: 6px; padding: 8px; }
nav .lbl { font-size: 12px; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 6px 10px 8px; }
:host([narrow]) nav .lbl { display: none; }
.echo { display: flex; gap: 10px; align-items: center; width: 100%; text-align: left; padding: 10px; border-radius: 10px; border: 0;
  background: none; color: inherit; cursor: pointer; font: inherit; }
:host([narrow]) .echo { width: auto; flex: none; border: 1px solid var(--line); }
.echo:hover { background: var(--soft); }
.echo.sel { background: color-mix(in srgb, var(--accent) 16%, transparent); }
.echo .dev { width: 36px; height: 24px; border-radius: 5px; border: 2px solid currentColor; opacity: .7; flex: none; position: relative; }
.echo .dev.on::after { content: ''; position: absolute; inset: 3px; border-radius: 2px; background: var(--accent); opacity: .7; }
.echo .t { font-weight: 500; } .echo .s { font-size: 12px; color: var(--muted); }
main { padding: 16px 20px 40px; min-width: 0; }
.tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--line); margin-bottom: 16px; }
.tab { background: none; border: 0; border-bottom: 2px solid transparent; padding: 10px 14px; font: inherit; color: var(--muted); cursor: pointer; }
.tab.sel { color: var(--accent); border-bottom-color: var(--accent); }
.apps { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 12px; }
.chip { border: 1px solid var(--line); background: var(--card-background-color); color: inherit; border-radius: 18px; padding: 6px 14px;
  font: inherit; font-size: 14px; cursor: pointer; display: inline-flex; gap: 6px; align-items: center; }
.chip.sel { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 14%, transparent); }
.chip .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--success-color, #4caf50); }
.chip .dot.none { background: var(--line); }
.bar { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 14px; }
.bar .grow { flex: 1; }
.status { font-size: 13px; color: var(--muted); }
.status.dirty { color: var(--warning-color, #ff9800); }
.btn { border: 1px solid var(--line); background: var(--card-background-color); color: inherit; border-radius: 8px; padding: 8px 14px;
  font: inherit; font-size: 14px; cursor: pointer; }
.btn:hover:not(:disabled) { background: var(--soft); }
.btn:disabled { opacity: .45; cursor: default; }
.btn.primary { background: var(--accent); border-color: var(--accent); color: var(--text-primary-color, #fff); }
.btn.danger { color: var(--error-color, #db4437); }
.btn.small { padding: 4px 10px; font-size: 13px; }
.grid { display: grid; grid-template-columns: minmax(320px, 1fr) minmax(320px, 1.25fr); gap: 16px; align-items: start; }
@media (max-width: 1100px) { .grid { grid-template-columns: 1fr; } }
.card { background: var(--card-background-color); border-radius: var(--r); border: 1px solid var(--line); padding: 4px 16px 12px;
  box-shadow: var(--ha-card-box-shadow, none); }
.card h2 { font-size: 16px; font-weight: 500; margin: 14px 0 4px; }
.card .about { font-size: 13px; color: var(--muted); margin-bottom: 6px; }
.row { padding: 12px 0; border-top: 1px solid var(--line); }
.row:first-of-type { border-top: 0; }
.row .head { display: flex; align-items: center; gap: 10px; }
.row .name { flex: 1; font-size: 15px; }
.row .help { font-size: 12px; color: var(--muted); margin-top: 3px; }
.seg { display: inline-flex; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
.seg button { border: 0; background: none; color: inherit; padding: 6px 12px; font: inherit; font-size: 13px; cursor: pointer; }
.seg button + button { border-left: 1px solid var(--line); }
.seg button.sel { background: var(--accent); color: var(--text-primary-color, #fff); }
input[type=text], input[type=number], input[type=url], select, textarea { font: inherit; font-size: 14px; color: inherit;
  background: var(--soft); border: 1px solid var(--line); border-radius: 8px; padding: 7px 10px; }
input[type=number] { width: 110px; }
textarea { width: 100%; min-height: 90px; font-family: var(--code-font-family, monospace); font-size: 13px; }
.switch { position: relative; width: 40px; height: 22px; flex: none; }
.switch input { opacity: 0; width: 0; height: 0; }
.switch span { position: absolute; inset: 0; border-radius: 11px; background: var(--line); cursor: pointer; transition: .15s; }
.switch span::after { content: ''; position: absolute; width: 16px; height: 16px; left: 3px; top: 3px; border-radius: 50%; background: #fff; transition: .15s; }
.switch input:checked + span { background: var(--accent); }
.switch input:checked + span::after { transform: translateX(18px); }
.list { margin-top: 8px; border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
.item { display: flex; align-items: center; gap: 8px; padding: 6px 8px; background: var(--card-background-color); border-top: 1px solid var(--line); }
.item:first-child { border-top: 0; }
.item.drag { opacity: .4; }
.item.over { box-shadow: inset 0 2px 0 var(--accent); }
.item .grip { cursor: grab; color: var(--muted); user-select: none; padding: 0 4px; }
.item .nm { flex: 1; min-width: 0; }
.item.page.off .nm { opacity: .55; }
.pagename { font: inherit; border: 1px solid var(--line); border-radius: 6px; padding: 4px 8px; background: transparent; color: inherit; width: 100%; box-sizing: border-box; }
.addpage { display: flex; gap: 8px; margin-top: 8px; }
.addpage .pagename { flex: 1; }
.appicon { width: 36px; height: 36px; border-radius: 9px; flex: none; }
.appicon.none { background: var(--secondary-background-color, #e6e6e6); }
.item .nm div { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.item .id { font-size: 12px; color: var(--muted); }
.item.unknown .nm div:first-child { color: var(--warning-color, #ff9800); }
.mini { background: none; border: 0; color: var(--muted); cursor: pointer; font-size: 16px; width: 28px; height: 28px; border-radius: 6px; }
.mini:hover { background: var(--soft); color: inherit; }
.mini:disabled { opacity: .3; }
.add { display: flex; gap: 6px; margin-top: 8px; }
.add input { flex: 1; }
.empty { padding: 10px; font-size: 13px; color: var(--muted); }
details.room { border: 1px solid var(--line); border-radius: 10px; margin-top: 8px; }
details.room summary { padding: 8px 12px; cursor: pointer; display: flex; gap: 8px; align-items: center; }
details.room summary .n { flex: 1; } details.room .list { margin: 0 8px 8px; }
.preview { position: sticky; top: calc(var(--header-height, 56px) + 12px); }
.screen { position: relative; border-radius: 14px; background: #111; padding: 10px; box-shadow: 0 6px 24px rgba(0,0,0,.25); }
.screen .vp { position: relative; overflow: hidden; border-radius: 4px; background: #000; }
.screen iframe { border: 0; transform-origin: 0 0; position: absolute; left: 0; top: 0; }
.screen .band { height: 4px; margin: 6px 30% 0; border-radius: 2px; background: color-mix(in srgb, var(--accent) 60%, #000); opacity: .6; }
.sketch { position: absolute; inset: 0; padding: 4%; display: grid; grid-template-columns: repeat(4, 1fr); grid-auto-rows: 22%; gap: 3%;
  background: linear-gradient(135deg, #3a2a1a, #120d08); }
.sketch.dusk { background: linear-gradient(135deg, #2a2848, #0b0a18); } .sketch.light { background: linear-gradient(135deg, #f2eee8, #cfc8bd); }
.sketch.photo { background: linear-gradient(135deg, #4a6a7a, #1b2a33 60%, #2f3a24); }
.sketch .w { border-radius: 12px; background: rgba(255,255,255,.14); backdrop-filter: blur(4px); color: #fff; font-size: 11px; padding: 8px;
  overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; }
.sketch.light .w { background: rgba(255,255,255,.6); color: #222; }
.sketch .w.big { grid-column: span 2; grid-row: span 2; font-size: 14px; }
.sketch .w .k { opacity: .7; font-size: 10px; }
.pbar { display: flex; gap: 8px; align-items: center; margin-top: 10px; flex-wrap: wrap; }
.note { font-size: 12px; color: var(--muted); }
.banner { border: 1px solid var(--warning-color, #ff9800); background: color-mix(in srgb, var(--warning-color, #ff9800) 12%, transparent);
  border-radius: 10px; padding: 10px 12px; display: flex; gap: 10px; align-items: center; margin-bottom: 12px; font-size: 14px; }
.banner .grow { flex: 1; }
.menuwrap { position: relative; display: inline-block; }
.pop { position: absolute; top: calc(100% + 4px); left: 0; z-index: 5; min-width: 260px; background: var(--card-background-color);
  border: 1px solid var(--line); border-radius: 10px; box-shadow: 0 8px 24px rgba(0,0,0,.2); padding: 6px; }
.pop button { display: block; width: 100%; text-align: left; border: 0; background: none; color: inherit; font: inherit; font-size: 14px;
  padding: 8px 10px; border-radius: 6px; cursor: pointer; }
.pop button:hover { background: var(--soft); }
.pop .sep { height: 1px; background: var(--line); margin: 4px 0; }
.pop .h { font-size: 12px; color: var(--muted); padding: 6px 10px 2px; }
.toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); background: var(--primary-text-color); color: var(--card-background-color, #fff);
  padding: 10px 16px; border-radius: 8px; z-index: 10; font-size: 14px; max-width: 90vw; }
.screens .item .nm { display: flex; align-items: center; gap: 8px; }
.kv { display: grid; grid-template-columns: 1fr; gap: 6px; margin-top: 8px; }
.kv input { width: 100%; }
.pushst { font-size: 13px; padding: 10px 12px; border-radius: 10px; margin-bottom: 12px; display: flex; gap: 10px; align-items: center;
  background: var(--soft); }
.pushst.bad { background: color-mix(in srgb, var(--error-color, #db4437) 12%, transparent); color: var(--error-color, #db4437); }
.pushst .grow { flex: 1; }
.app .nm div:first-child { font-family: var(--code-font-family, monospace); font-size: 14px; }
.prog { height: 6px; border-radius: 3px; background: var(--line); overflow: hidden; margin-top: 8px; }
.prog > div { height: 100%; background: var(--accent); transition: width .2s; }
.inst { margin-top: 10px; font-size: 14px; }
.inst.bad { color: var(--error-color, #db4437); }
.inst.good { color: var(--success-color, #4caf50); }
.card h3.group { font-size: 13px; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 18px 0 4px; font-weight: 600; }
`;


class EchoWallPanel extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this.state = { devices: [], desc: null, loaded: false, error: '' };
    this.dev = null;                  // the selected device's id
    this.drafts = new Map();          // device -> { saved, draft, incoming, sub }
    this.size = null;
    this.editOnScreen = false;
    this.launcher = {};               // device -> its Android apps as the app lists them (echo_wall/apps/get)
    this.pages = null;                // the pages after Home, as the preview last made them (echo-wall-pages)
    // the preview (the app's lib/preview.dart) asks the login, the draft and what the device's app would know from here
    window.echoWallPreview = {
      token: async () => { const a = this._hass.auth; if (a.expired) await a.refreshAccessToken(); return a.accessToken; },
      layout: () => (this.cur() || {}).draft,
      info: () => this.previewInfo(),
    };
    this.onMessage = (ev) => {
      if (ev.origin !== location.origin || !ev.data) return;
      if (ev.data.type === 'echo-wall-pages') {
        if (JSON.stringify(ev.data.pages) === JSON.stringify(this.pages)) return;
        this.pages = ev.data.pages;
        const r = this.shadowRoot.querySelector('.pagesrow'); const c = this.cur();
        if (r && c) r.replaceWith(this.pagesRow(c));
        return;
      }
      if (ev.data.type !== 'echo-wall-edit') return;
      const c = this.cur(); if (!c) return;
      c.draft = clone(ev.data.layout); this.refresh();      // not sent back: the preview has it
    };
  }

  // what the app on the device gets beside the layout: the clock's format, its other screens' names (their tiles)
  previewInfo() {
    const loc = this._hass.locale || {};
    const h24 = loc.time_format === '24' ? true : loc.time_format === '12' ? false
      : new Intl.DateTimeFormat(loc.language || undefined, { hour: 'numeric' }).resolvedOptions().hour12 === false;
    const info = this.devInfo() || {};
    return { h24, screens: info.screens || [], settings: {}, editing: this.editOnScreen, gallery: this.gallery, apps: this.launcher[this.dev] || [] };
  }

  set hass(h) { const first = !this._hass; this._hass = h; if (first) this.load(); }
  get hass() { return this._hass; }
  set narrow(n) { this.toggleAttribute('narrow', !!n); }

  connectedCallback() { addEventListener('message', this.onMessage); this.render(); }
  disconnectedCallback() {
    removeEventListener('message', this.onMessage);
    for (const d of this.drafts.values()) if (d.sub) d.sub.then((u) => u()).catch(() => {});
    this.drafts.clear();
  }

  ws(msg) { return this._hass.connection.sendMessagePromise(msg); }
  key(dev = this.dev) { return dev; }
  cur() { return this.drafts.get(this.dev); }
  desc() { return this.state.desc; }
  devInfo(dev = this.dev) { return this.state.devices.find((e) => e.device === dev); }
  toast(t) { const d = h('div', { class: 'toast' }, t); this.shadowRoot.append(d); setTimeout(() => d.remove(), 3500); }

  async load() {
    try {
      const r = await this.ws({ type: 'echo_wall/list' });
      this.state = { devices: r.devices, desc: { name: r.name, about: r.about, fields: r.fields, preview: r.preview }, limits: r.limits, loaded: true, error: '' };
      if (!this.dev || !this.devInfo()) this.dev = (r.devices[0] || {}).device || null;
    } catch (e) {
      this.state = { ...this.state, loaded: true, error: (e && e.message) || String(e) };
    }
    this.render();
    if (this.dev) this.select(this.dev);
  }

  async select(dev) {
    this.dev = dev;
    const info = this.devInfo(dev);
    this.size = info && info.screen ? [info.screen[0], info.screen[1]] : SIZES['Echo Show 5'];
    this.pages = null;                      // the new preview tells its own
    await this.open(dev);
    this.loadLauncher(dev);
    this.render();
  }

  // a device's layout followed live: the saved one from Home Assistant, a draft of our own
  async open(dev) {
    if (this.drafts.has(dev)) return;
    const d = { saved: null, draft: null, incoming: null, sub: null };
    this.drafts.set(dev, d);
    await new Promise((res) => {
      d.sub = this._hass.connection.subscribeMessage((ev) => {
        const lay = ev.layout || {};
        if (d.saved == null || same(d.saved, d.draft)) { d.saved = clone(lay); d.draft = clone(lay); d.incoming = null; }
        else if (!same(lay, d.saved)) d.incoming = clone(lay);   // the device changed it while we edit: offered
        res();
        if (this.dev === dev) { this.refresh(); this.pushPreview(); }
      }, { type: 'echo_wall/subscribe', device: dev });
      d.sub.catch((e) => { d.saved = {}; d.draft = {}; this.toast('Not readable: ' + ((e && e.message) || e)); res(); });
    });
  }

  dirty(c = this.cur()) { return !!c && c.saved != null && !same(c.saved, c.draft); }

  // a field changed: the toolbar and the preview follow; the form is left as it is (focus stays where it is)
  changed(rebuild) {
    if (rebuild) this.refresh(); else this.renderBar();
    this.pushPreview();
  }

  // the draft changed or came anew: the form, the banner and the bar drawn again, the preview left alone (an iframe
  // rebuilt or moved loads again: Flutter would start over)
  refresh() {
    const grid = this.shadowRoot.querySelector('.grid');
    const c = this.cur();
    if (!grid || grid.dataset.key !== this.dev + '|' + this.size || !c || c.draft == null) { this.render(); return; }
    grid.firstChild.replaceWith(this.form(c, this.desc()));
    this.shadowRoot.querySelector('.incoming').replaceWith(this.banner(c));
    this.renderBar();
  }

  // the device's Android apps with their labels and icons, as its app sent them: their tiles in the preview
  async loadLauncher(dev) {
    try {
      const r = await this.ws({ type: 'echo_wall/apps/get', device: dev });
      this.launcher[dev] = r.apps || [];
    } catch (e) { return; }
    if (dev !== this.dev) return;
    const f = this.shadowRoot.querySelector('iframe');
    if (f && f.contentWindow) f.contentWindow.postMessage({ type: 'echo-wall-apps', apps: this.launcher[dev] }, location.origin);
  }

  pushPreview() {
    const f = this.shadowRoot.querySelector('iframe');
    const c = this.cur();
    if (f && f.contentWindow && c) f.contentWindow.postMessage({ type: 'echo-wall-layout', layout: c.draft }, location.origin);
  }

  async save() {
    const c = this.cur(); if (!c) return;
    try {
      const lay = await this.ws({ type: 'echo_wall/set', device: this.dev, layout: c.draft });
      c.saved = clone(lay); c.draft = clone(lay); c.incoming = null;
      this.toast('Saved: the device shows it now');
      this.refreshList();
    } catch (e) { this.toast('Not saved: ' + ((e && e.message) || e)); }
    this.refresh();
  }

  async refreshList() {
    try {
      const r = await this.ws({ type: 'echo_wall/list' });
      this.state.devices = r.devices;
      this.renderNav();
      this.renderBar();
    } catch (e) { /* the next save tells */ }
  }

  // ---------------------------------------------------------------- import and export

  exportFile() {
    const c = this.cur(); if (!c) return;
    const secret = (this.desc().fields || []).filter((f) => f.secret).map((f) => f.key);
    const layout = clone(c.draft); for (const k of secret) delete layout[k];
    const info = this.devInfo();
    const doc = { format: FORMAT, version: 1, app: ECHOWALL, device: this.dev, device_name: info ? info.name : this.dev,
      exported: new Date().toISOString(), layout };
    const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json' });
    const a = h('a', { href: URL.createObjectURL(blob), download: `${(info ? info.name : this.dev).replace(/[^\w-]+/g, '-')}.echowall.json` });
    this.shadowRoot.append(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  pickFile() {
    const i = h('input', { type: 'file', accept: '.json,application/json', style: 'display:none' });
    i.onchange = async () => {
      const f = i.files[0]; i.remove(); if (!f) return;
      try {
        if (f.size > 256 * 1024) throw new Error('larger than a home screen can be');
        const doc = JSON.parse(await f.text());
        const ok = typeof doc.layout === 'object' && (doc.format === FORMAT || (doc.format === LEGACY && doc.app === ECHOWALL));
        if (!ok) throw new Error('not an Echo-Wall home screen file');
        this.take(doc.layout, `${doc.device_name || doc.echo_name || 'a file'}`);
      } catch (e) { this.toast('Not imported: ' + e.message); }
    };
    this.shadowRoot.append(i); i.click();
  }

  // another layout into this device's draft: as it is, this device's secrets (the Immich key) kept
  take(layout, what) {
    const c = this.cur(); if (!c) return;
    const next = clone(layout);
    for (const f of this.desc().fields) if (f.secret && !(f.key in next) && f.key in (c.draft || {})) next[f.key] = c.draft[f.key];
    c.draft = next;
    const unknown = this.ids(next).filter((x) => !this._hass.states[x]);
    this.toast(`Imported from ${what}: Save to send it to the device` + (unknown.length ? ` (${unknown.length} entities not in this Home Assistant, kept)` : ''));
    this.changed(true);
  }

  ids(lay) {
    const out = [];
    for (const f of this.desc().fields) {
      const v = lay[f.key];
      if (f.type === 'entities' && Array.isArray(v)) out.push(...v);
      else if (f.type === 'entity' && v && v !== f.none) out.push(v);
      else if (f.type === 'area_order' && v) for (const l of Object.values(v)) out.push(...l);
    }
    return [...new Set(out)];
  }

  async fromDevice(dev) {
    try {
      const lay = await this.ws({ type: 'echo_wall/get', device: dev });
      this.take(lay, (this.devInfo(dev) || {}).name || dev);
    } catch (e) { this.toast('Not read: ' + ((e && e.message) || e)); }
  }

  async copyTo(devs) {
    const c = this.cur(); if (!c || !devs.length) return;
    let n = 0;
    for (const dev of devs) {
      try {
        const there = await this.ws({ type: 'echo_wall/get', device: dev });
        const lay = clone(c.draft);
        for (const f of this.desc().fields) if (f.secret) { if (f.key in there) lay[f.key] = there[f.key]; else delete lay[f.key]; }
        await this.ws({ type: 'echo_wall/set', device: dev, layout: lay }); n++;
      } catch (e) { this.toast(`${dev}: ${(e && e.message) || e}`); }
    }
    this.toast(`Copied to ${n} device${n === 1 ? '' : 's'}`);
    this.refreshList();
  }

  async reset() {
    if (!confirm('Forget this device’s layout? Its app starts again from its own choice.')) return;
    await this.ws({ type: 'echo_wall/reset', device: this.dev }).catch((e) => this.toast(String(e && e.message || e)));
    const c = this.cur(); if (c) { c.saved = null; c.draft = null; }
    this.refreshList();
  }

  async forget() {
    const info = this.devInfo();
    if (!confirm(`Forget ${info ? info.name : this.dev}? Its layout goes with it; the device comes back here the next time its app logs in.`)) return;
    try { await this.ws({ type: 'echo_wall/forget', device: this.dev }); } catch (e) { this.toast(String(e && e.message || e)); return; }
    const d = this.drafts.get(this.dev); if (d && d.sub) d.sub.then((u) => u()).catch(() => {});
    this.drafts.delete(this.dev);
    this.dev = null;
    this.load();
  }

  async rename() {
    const info = this.devInfo(); if (!info) return;
    const n = prompt('The device’s name here', info.name);
    if (!n || !n.trim()) return;
    try { await this.ws({ type: 'echo_wall/rename', device: this.dev, name: n.trim() }); this.refreshList(); }
    catch (e) { this.toast(String(e && e.message || e)); }
  }

  // ---------------------------------------------------------------- drawing

  render() {
    const root = this.shadowRoot;
    root.textContent = '';
    root.append(h('style', null, CSS));
    root.append(h('header', null,
      h('button', { class: 'iconbtn menu', title: 'Menu', onclick: () => this.dispatchEvent(new Event('hass-toggle-menu', { bubbles: true, composed: true })) }, '☰'),
      h('h1', null, 'Echo-Wall')));
    if (!this.state.loaded) { root.append(h('main', null, h('div', { class: 'empty' }, 'Loading…'))); return; }
    if (this.state.error) { root.append(h('main', null, h('div', { class: 'banner' }, 'Echo-Wall did not answer: ' + this.state.error))); return; }
    const wrap = h('div', { class: 'wrap' }, h('nav'), h('main'));
    root.append(wrap);
    this.renderNav();
    this.renderMain();
  }

  renderNav() {
    const nav = this.shadowRoot.querySelector('nav'); if (!nav) return;
    nav.textContent = '';
    nav.append(h('div', { class: 'lbl' }, 'Devices'));
    for (const e of this.state.devices) {
      const fresh = e.seen && Date.now() / 1000 - e.seen < 600;
      nav.append(h('button', { class: 'echo' + (e.device === this.dev ? ' sel' : ''), onclick: () => this.select(e.device) },
        h('span', { class: 'dev' + (fresh ? ' on' : '') }),
        h('span', null, h('div', { class: 't' }, e.name), h('div', { class: 's' }, [e.model, e.seen ? 'seen ' + ago(e.seen) : ''].filter(Boolean).join(' · ')))));
    }
    if (!this.state.devices.length) nav.append(h('div', { class: 'empty' }, 'No device yet. Install the Echo-Wall app on an Echo Show (with hassmic) or a tablet and log it in to this Home Assistant: it appears here.'));
  }

  renderMain() {
    const main = this.shadowRoot.querySelector('main'); if (!main) return;
    main.textContent = '';
    if (!this.devInfo()) { main.append(h('div', { class: 'empty' }, 'Pick a device on the left.')); return; }
    const c = this.cur();
    if (!c || c.draft == null) {         // being read (a reset: until the subscription brings the empty one)
      if (!c) this.open(this.dev).then(() => this.render());
      main.append(h('div', { class: 'empty' }, 'Loading…'));
      return;
    }
    main.append(this.banner(c));
    main.append(h('div', { class: 'bar' }));
    const d = this.desc();
    const grid = h('div', { class: 'grid' }, this.form(c, d), this.previewPane(c, d));
    grid.dataset.key = this.dev + '|' + this.size;
    main.append(grid);
    queueMicrotask(() => this.renderBar());
  }

  banner(c) {
    const b = h('div', { class: 'incoming' });
    if (c.incoming) b.append(h('div', { class: 'banner' },
      h('span', { class: 'grow' }, 'The device saved a change of its own while you edit (someone arranged it on the screen).'),
      h('button', { class: 'btn small', onclick: () => { c.saved = c.incoming; c.draft = clone(c.incoming); c.incoming = null; this.changed(true); } }, 'Take the device’s'),
      h('button', { class: 'btn small', onclick: () => { c.saved = c.incoming; c.incoming = null; this.changed(true); } }, 'Keep mine')));
    return b;
  }

  renderBar() {
    const bar = this.shadowRoot.querySelector('.bar'); if (!bar) return;
    const c = this.cur(); if (!c) return;
    bar.textContent = '';
    const dirty = this.dirty(c);
    const info = this.devInfo() || {};
    const st = info.updated ? `Saved ${ago(info.updated)}${info.by === 'app' ? ' by the device' : info.by === 'panel' ? ' here' : ''}` : 'Nothing saved yet: the app’s own choice';
    const others = this.state.devices.filter((e) => e.device !== this.dev);
    bar.append(...[
      h('button', { class: 'btn primary', disabled: !dirty, onclick: () => this.save() }, 'Save'),
      h('button', { class: 'btn', disabled: !dirty, onclick: () => { c.draft = clone(c.saved); this.changed(true); } }, 'Revert'),
      h('span', { class: 'status' + (dirty ? ' dirty' : '') }, dirty ? 'Unsaved changes' : st),
      h('span', { class: 'grow' }),
      this.menu('Import', () => {
        const items = [h('button', { onclick: () => this.pickFile() }, 'From a file…')];
        const had = others.filter((e) => e.updated);
        if (had.length) items.push(h('div', { class: 'sep' }), h('div', { class: 'h' }, 'Another device'),
          ...had.map((e) => h('button', { onclick: () => this.fromDevice(e.device) }, e.name)));
        return items;
      }),
      h('button', { class: 'btn', onclick: () => this.exportFile() }, 'Export'),
      others.length ? this.menu('Copy to', () => [h('div', { class: 'h' }, 'Saves this draft there (their own Immich key kept)'),
        ...others.map((e) => h('button', { onclick: () => this.copyTo([e.device]) }, e.name)),
        others.length > 1 && h('button', { onclick: () => this.copyTo(others.map((e) => e.device)) }, 'Every other device')]) : null,
      this.menu('Device', () => [h('button', { onclick: () => this.rename() }, 'Rename…'),
        h('button', { onclick: () => this.reset(), disabled: !info.updated }, 'Reset its layout'),
        h('button', { onclick: () => this.forget() }, 'Forget this device')]),
    ].filter(Boolean));
  }

  menu(label, items) {
    const w = h('span', { class: 'menuwrap' });
    const b = h('button', { class: 'btn', onclick: (ev) => {
      ev.stopPropagation();
      const open = w.querySelector('.pop'); if (open) { open.remove(); return; }
      const pop = h('div', { class: 'pop' }, items());
      pop.addEventListener('click', () => pop.remove());
      w.append(pop);
      const close = (e) => { if (!e.composedPath().includes(w)) { pop.remove(); removeEventListener('click', close, true); } };
      addEventListener('click', close, true);
    } }, label + ' ▾');
    w.append(b);
    return w;
  }

  form(c, d) {
    const card = h('div', { class: 'card' });
    card.append(h('h2', null, d.name), d.about && h('div', { class: 'about' }, d.about));
    let group = '';
    for (const f of d.fields) {
      if ((f.group || '') !== group) { group = f.group || ''; if (group) card.append(h('h3', { class: 'group' }, group)); }
      card.append(this.field(c, f));
      if (f.key === 'dashboard') card.append(this.pagesRow(c));
    }
    card.append(h('details', { class: 'room', style: 'margin-top:12px' }, h('summary', null, h('span', { class: 'n' }, 'All of it, as JSON')), h('div', { style: 'padding:0 12px 12px' }, this.jsonRow(c))));
    return card;
  }

  // Echo-Wall's pages after Home (the preview tells which there are: rooms, a dashboard's sections, the owner's own):
  // in their order, moved up and down (page_order), the owner's renamed or deleted (custom_pages), the others taken
  // off and shown again (hidden_pages), a new one added.  All of it in the draft: Save sends it to the Echo
  pagesRow(c) {
    const lay = c.draft;
    const row = h('div', { class: 'row pagesrow' }, h('div', { class: 'head' }, h('span', { class: 'name' }, 'Pages after Home')));
    const pages = this.pages;
    if (!pages) { row.append(h('div', { class: 'help' }, 'The preview lists them once it has started.')); return row; }
    const done = () => this.changed(true);
    const order = () => pages.map((p) => p.group);
    const own = (g) => (lay.custom_pages || []).find((p) => 'page:' + p.id === g);
    const list = h('div', { class: 'list' });
    if (!pages.length) list.append(h('div', { class: 'empty' }, 'None: Home only.'));
    pages.forEach((p, i) => {
      const move = (d) => { const o = order(); [o[i], o[i + d]] = [o[i + d], o[i]]; lay.page_order = o; this.pages = o.map((g) => pages.find((x) => x.group === g)); done(); };
      const name = p.kind === 'own'
        ? h('input', { class: 'pagename', value: p.title, 'aria-label': 'Page name', onchange: (e) => { const cp = own(p.group); if (cp && e.target.value.trim()) { cp.name = e.target.value.trim(); done(); } } })
        : h('div', null, p.title);
      list.append(h('div', { class: 'item page' + (p.hidden ? ' off' : '') },
        h('div', { class: 'nm' }, name, h('div', { class: 'id' }, (p.kind === 'own' ? 'Your page' : p.kind === 'dashboard' ? 'Dashboard section' : 'Room') + (p.hidden ? ' · taken off' : ''))),
        h('button', { class: 'btn small', disabled: i === 0, title: 'Earlier', 'aria-label': 'Move up', onclick: () => move(-1) }, '↑'),
        h('button', { class: 'btn small', disabled: i === pages.length - 1, title: 'Later', 'aria-label': 'Move down', onclick: () => move(1) }, '↓'),
        p.kind === 'own'
          ? h('button', { class: 'btn small danger', onclick: () => {
              if (!confirm(`Delete the page “${p.title}”? Its cards go with it.`)) return;
              lay.custom_pages = (lay.custom_pages || []).filter((x) => 'page:' + x.id !== p.group);
              for (const k of ['cards', 'place', 'sizes', 'exclude']) if (lay[k]) delete lay[k][p.group];
              lay.page_order = (lay.page_order || []).filter((g) => g !== p.group);
              this.pages = pages.filter((x) => x.group !== p.group); done(); } }, 'Delete')
          : h('button', { class: 'btn small' + (p.hidden ? '' : ' danger'), onclick: () => {
              const hp = new Set(lay.hidden_pages || []); p.hidden ? hp.delete(p.group) : hp.add(p.group);
              lay.hidden_pages = [...hp]; p.hidden = !p.hidden; done(); } }, p.hidden ? 'Show' : 'Remove')));
    });
    const nm = h('input', { class: 'pagename', placeholder: 'New page’s name' });
    const add = () => {
      const n = nm.value.trim() || `Page ${(lay.custom_pages || []).length + 1}`;
      const id = Date.now().toString(36);
      lay.custom_pages = [...(lay.custom_pages || []), { id, name: n }];
      lay.page_order = [...order(), 'page:' + id];
      this.pages = [...pages, { group: 'page:' + id, title: n, kind: 'own', hidden: false }];
      done();
    };
    nm.addEventListener('keydown', (e) => { if (e.key === 'Enter') add(); });
    row.append(list, h('div', { class: 'addpage' }, nm, h('button', { class: 'btn small', onclick: add }, '+ Add page')),
      h('div', { class: 'help' }, 'A page of your own starts empty: add cards to it in the preview’s edit mode (+ Add) or on the Echo. A room or a dashboard section taken off stays off until shown again.'));
    return row;
  }

  jsonRow(c) {
    const t = h('textarea', { spellcheck: false });
    t.value = JSON.stringify(c.draft, null, 2);
    const msg = h('div', { class: 'help' });
    t.addEventListener('input', () => {
      try { c.draft = JSON.parse(t.value); msg.textContent = ''; this.changed(false); } catch (e) { msg.textContent = 'Not JSON yet: ' + e.message; }
    });
    t.addEventListener('change', () => this.changed(true));
    return h('div', { class: 'row' }, t, msg);
  }

  field(c, f) {
    const lay = c.draft;
    const has = f.key in lay && lay[f.key] !== undefined;
    const val = has ? lay[f.key] : f.default;
    const set = (v, rebuild) => { if (v === undefined) delete lay[f.key]; else lay[f.key] = v; this.changed(rebuild); };
    const row = h('div', { class: 'row' });
    const head = h('div', { class: 'head' }, h('span', { class: 'name' }, f.label || f.key));
    row.append(head);
    if (f.type === 'select') {
      const opts = f.options || [];
      if (opts.length <= 4) {
        const seg = h('div', { class: 'seg' });
        for (const [v, l] of opts) seg.append(h('button', { class: v === val ? 'sel' : '', onclick: () => { set(v); [...seg.children].forEach((b) => b.classList.toggle('sel', b.textContent === l)); } }, l));
        head.append(seg);
      } else {
        const s = h('select', { onchange: () => set(s.value) }, opts.map(([v, l]) => h('option', { value: v, selected: v === val }, l)));
        head.append(s);
      }
    } else if (f.type === 'number') {
      const i = h('input', { type: 'number', min: f.min, max: f.max, step: f.step || 1 });
      i.value = val == null ? '' : val;
      i.addEventListener('input', () => { if (i.value === '') set(undefined); else if (i.checkValidity()) set(+i.value); });
      head.append(i, f.unit ? h('span', { class: 'note' }, f.unit) : null);
    } else if (f.type === 'bool') {
      head.append(this.switch(!!val, (on) => set(on)));
    } else if (f.type === 'dashboard') {
      // the Home Assistant dashboards (lovelace/dashboards/list) and Overview; the field's value is the url path
      const s = h('select', { onchange: () => set(s.value || undefined) }, h('option', { value: '' }, 'None: a page per room'));
      const add = (v, l) => s.append(h('option', { value: v, selected: v === (val || '') }, l));
      add('lovelace', 'Overview');
      this.ws({ type: 'lovelace/dashboards/list' }).then((ds) => {
        for (const d of ds) add(d.url_path, d.title || d.url_path);
        if (val && ![...s.options].some((o) => o.value === val)) add(val, val + ' (not found)');
        s.value = val || '';
      }).catch(() => { if (val && val !== 'lovelace') add(val, val); s.value = val || ''; });
      head.append(s);
    } else if (f.type === 'text') {
      const i = h('input', { type: f.secret ? 'password' : 'text', autocomplete: 'off', style: 'min-width:220px' }); i.value = val || '';
      i.addEventListener('input', () => set(i.value || undefined));
      head.append(i);
    } else if (f.type === 'entity') {
      head.append(this.entityInput(val && val !== f.none ? val : '', f.domain, (v) => set(v || (f.none != null ? f.none : undefined)), f.none != null ? 'None' : 'The app picks'));
    } else if (f.type === 'entities') {
      const auto = f.nullable && !Array.isArray(val);
      if (f.nullable) head.append(h('span', { class: 'note' }, 'The app picks'), this.switch(auto, (on) => set(on ? null : this.autoPick(), true)));
      if (!auto) row.append(this.entityList(Array.isArray(val) ? val : [], f.ordered !== false, (list, rebuild) => set(list, rebuild)));
    } else if (f.type === 'strings') {
      row.append(this.stringList(Array.isArray(val) ? val : [], (list) => set(list, true)));
    } else if (f.type === 'area_order') {
      row.append(this.areaOrder(val || {}, (v, rebuild) => set(v, rebuild)));
    }
    if (f.help) row.append(h('div', { class: 'help' }, f.help));
    return row;
  }

  switch(on, cb) {
    const i = h('input', { type: 'checkbox', checked: on });
    i.addEventListener('change', () => cb(i.checked));
    return h('label', { class: 'switch' }, i, h('span'));
  }

  // what Echo-Wall picks itself (a thermostat, a camera, scenes, locks): a start for a list of one's own
  autoPick() {
    const s = this._hass.states, ids = Object.keys(s);
    const out = [];
    const cl = ids.find((x) => domainOf(x) === 'climate' && s[x].attributes.temperature != null); if (cl) out.push(cl);
    const cam = ids.find((x) => domainOf(x) === 'camera' && s[x].state !== 'unavailable'); if (cam) out.push(cam);
    out.push(...ids.filter((x) => domainOf(x) === 'scene').slice(0, 3), ...ids.filter((x) => domainOf(x) === 'lock'));
    return out;
  }

  name(id) { const s = this._hass.states[id]; return (s && s.attributes.friendly_name) || id; }

  entityInput(val, domain, cb, placeholder) {
    const listId = 'el-' + Math.random().toString(36).slice(2);
    const i = h('input', { type: 'text', list: listId, placeholder: placeholder || 'entity id or name', style: 'min-width:220px' });
    i.value = val || '';
    const dl = h('datalist', { id: listId });
    for (const id of Object.keys(this._hass.states).filter((x) => !domain || domainOf(x) === domain).sort())
      dl.append(h('option', { value: id }, this.name(id)));
    i.addEventListener('change', () => {
      const v = i.value.trim();
      const id = v === '' || this._hass.states[v] ? v : Object.keys(this._hass.states).find((x) => this.name(x).toLowerCase() === v.toLowerCase()) || v;
      i.value = id; cb(id);
    });
    return h('span', null, i, dl);
  }

  // a list of entities: drag (or the arrows) to order, × to remove, a picker to add
  entityList(list, ordered, cb) {
    const wrap = h('div');
    const draw = () => {
      wrap.textContent = '';
      const box = h('div', { class: 'list' });
      if (!list.length) box.append(h('div', { class: 'empty' }, 'None yet.'));
      list.forEach((id, i) => {
        const known = !!this._hass.states[id];
        const it = h('div', { class: 'item' + (known ? '' : ' unknown'), draggable: ordered ? 'true' : null },
          ordered && h('span', { class: 'grip', title: 'Drag' }, '⠿'),
          h('div', { class: 'nm' }, h('div', null, this.name(id)), h('div', { class: 'id' }, known ? id : id + ' · not in this Home Assistant')),
          ordered && h('button', { class: 'mini', title: 'Up', disabled: i === 0, onclick: () => { list.splice(i - 1, 0, list.splice(i, 1)[0]); cb(list); draw(); } }, '↑'),
          ordered && h('button', { class: 'mini', title: 'Down', disabled: i === list.length - 1, onclick: () => { list.splice(i + 1, 0, list.splice(i, 1)[0]); cb(list); draw(); } }, '↓'),
          h('button', { class: 'mini', title: 'Remove', onclick: () => { list.splice(i, 1); cb(list); draw(); } }, '×'));
        if (ordered) this.dnd(it, i, list, () => { cb(list); draw(); });
        box.append(it);
      });
      wrap.append(box);
      const add = h('div', { class: 'add' });
      add.append(this.entityInput('', null, (v) => { if (v && !list.includes(v)) { list.push(v); cb(list); draw(); } }, 'Add: entity id or name'));
      wrap.append(add);
    };
    list = list.slice(); draw();
    return wrap;
  }

  dnd(it, i, list, done) {
    it.addEventListener('dragstart', (ev) => { this._drag = { list, i }; it.classList.add('drag'); ev.dataTransfer.effectAllowed = 'move'; ev.dataTransfer.setData('text/plain', String(i)); });
    it.addEventListener('dragend', () => { it.classList.remove('drag'); this._drag = null; });
    it.addEventListener('dragover', (ev) => { if (this._drag && this._drag.list === list) { ev.preventDefault(); it.classList.add('over'); } });
    it.addEventListener('dragleave', () => it.classList.remove('over'));
    it.addEventListener('drop', (ev) => {
      ev.preventDefault(); it.classList.remove('over');
      const g = this._drag; if (!g || g.list !== list || g.i === i) return;
      const [x] = list.splice(g.i, 1); list.splice(i, 0, x); done();
    });
  }

  stringList(list, cb) {
    list = list.slice();
    const wrap = h('div', { class: 'apps', style: 'margin-top:8px' });
    const draw = () => {
      wrap.textContent = '';
      list.forEach((s, i) => wrap.append(h('span', { class: 'chip' }, s, h('button', { class: 'mini', onclick: () => { list.splice(i, 1); cb(list); draw(); } }, '×'))));
      const i = h('input', { type: 'text', placeholder: 'Add…', style: 'width:140px' });
      i.addEventListener('change', () => { const v = i.value.trim(); if (v && !list.includes(v)) { list.push(v); cb(list); draw(); } });
      wrap.append(i);
    };
    draw();
    return wrap;
  }

  // each room's tiles in order: Home Assistant's areas, their entities (by entity or device area), the saved order first
  areaOrder(order, cb) {
    order = clone(order);
    const H = this._hass;
    const areas = Object.values(H.areas || {}).sort((a, b) => a.name.localeCompare(b.name));
    const areaOf = (id) => { const e = (H.entities || {})[id]; if (!e) return null; return e.area_id || (e.device_id && (H.devices || {})[e.device_id] ? H.devices[e.device_id].area_id : null); };
    const TILE = ['light', 'switch', 'fan', 'cover', 'lock', 'media_player', 'climate', 'binary_sensor', 'scene', 'script', 'camera'];
    const wrap = h('div');
    if (!areas.length) { wrap.append(h('div', { class: 'empty' }, 'No areas in Home Assistant: rooms come from them.')); return wrap; }
    for (const a of areas) {
      const ids = Object.keys(H.states).filter((x) => areaOf(x) === a.area_id && TILE.includes(domainOf(x)) && !(H.entities[x] || {}).hidden);
      const own = order[a.area_id] || [];
      const list = [...own.filter((x) => ids.includes(x) || !H.states[x]), ...ids.filter((x) => !own.includes(x)).sort((x, y) => this.name(x).localeCompare(this.name(y)))];
      const d = h('details', { class: 'room' }, h('summary', null, h('span', { class: 'n' }, a.name), h('span', { class: 'note' }, own.length ? 'own order' : 'the app’s order'),
        own.length ? h('button', { class: 'btn small', onclick: (ev) => { ev.preventDefault(); delete order[a.area_id]; cb(clone(order), true); } }, 'Reset') : null));
      const box = h('div', { class: 'list' });
      const draw = () => {
        box.textContent = '';
        list.forEach((id, i) => {
          const it = h('div', { class: 'item', draggable: 'true' }, h('span', { class: 'grip' }, '⠿'),
            h('div', { class: 'nm' }, h('div', null, this.name(id)), h('div', { class: 'id' }, id)),
            h('button', { class: 'mini', disabled: i === 0, onclick: () => { list.splice(i - 1, 0, list.splice(i, 1)[0]); commit(); } }, '↑'),
            h('button', { class: 'mini', disabled: i === list.length - 1, onclick: () => { list.splice(i + 1, 0, list.splice(i, 1)[0]); commit(); } }, '↓'));
          this.dnd(it, i, list, commit);
          box.append(it);
        });
        if (!list.length) box.append(h('div', { class: 'empty' }, 'Nothing for the screen in this room.'));
      };
      const commit = () => { order[a.area_id] = list.slice(); cb(clone(order)); draw(); };
      draw();
      d.append(box);
      wrap.append(d);
    }
    return wrap;
  }


  previewPane(c, d) {
    const [w, hgt] = this.size || SIZES['Echo Show 5'];
    const pane = h('div', { class: 'preview' });
    const vp = h('div', { class: 'vp' });
    const screen = h('div', { class: 'screen' }, vp, h('div', { class: 'band' }));
    pane.append(screen);
    const fit = () => { const cw = vp.clientWidth || 560; vp.style.height = (cw * hgt / w) + 'px'; const f = vp.querySelector('iframe'); if (f) f.style.transform = `scale(${cw / w})`; };
    const f = h('iframe', { src: `${d.preview}?device=${encodeURIComponent(this.dev)}`, title: 'Preview', style: `width:${w}px;height:${hgt}px` });
    f.dataset.key = this.dev;
    f.addEventListener('load', () => { this.pushPreview(); if (this.editOnScreen) f.contentWindow.postMessage({ type: 'echo-wall-editmode', on: true }, location.origin); });
    vp.append(f);
    new ResizeObserver(fit).observe(vp);
    requestAnimationFrame(fit);
    const info = this.devInfo() || {};
    const own = info.screen ? { [`This device (${info.screen[0]}×${info.screen[1]})`]: info.screen } : {};
    const all = { ...own, ...SIZES };
    const sizeSel = h('select', { onchange: () => { this.size = all[sizeSel.value]; this.render(); } },
      Object.entries(all).map(([k, v]) => h('option', { value: k }, own[k] ? k : `${k} (${v[0]}×${v[1]})`)));
    sizeSel.value = (Object.entries(all).find(([, v]) => same(v, this.size)) || [''])[0];   // the first that matches: this device's own
    const bar = h('div', { class: 'pbar' }, sizeSel);
    bar.append(h('label', { class: 'note', style: 'display:flex;gap:6px;align-items:center' },
      this.switch(this.editOnScreen, (on) => { this.editOnScreen = on; const f = vp.querySelector('iframe'); if (f) f.contentWindow.postMessage({ type: 'echo-wall-editmode', on }, location.origin); }),
      'Edit on the screen: drag cards, ⤡ to resize, ★ for Home, − to hide'));
    bar.append(h('label', { class: 'note', style: 'display:flex;gap:6px;align-items:center' },
      this.switch(!!this.gallery, (on) => { this.gallery = on; const f = vp.querySelector('iframe'); if (f) f.contentWindow.postMessage({ type: 'echo-wall-gallery', on }, location.origin); }),
      'Card sizes: every card at every size, with your devices'));
    bar.append(h('span', { class: 'note' }, 'The app itself, live with this Home Assistant’s states. Drag or scroll sideways for the pages, or click beside the dots; hold a card for its menu.'));
    pane.append(bar);
    return pane;
  }
}

customElements.get('echo-wall-panel') || customElements.define('echo-wall-panel', EchoWallPanel);
