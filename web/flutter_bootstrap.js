{{flutter_js}}
{{flutter_build_config}}

// The Echo Local panel's preview (lib/preview.dart): CanvasKit served by Home Assistant itself (no CDN: a Home
// Assistant may have no internet), its one build that runs in every browser, and no service worker (the page is
// Home Assistant's origin: nothing of ours should stay behind in it).
_flutter.loader.load({ config: { canvasKitVariant: "full" } });
