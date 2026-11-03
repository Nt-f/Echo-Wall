#!/bin/sh
# Echo-Wall built for the web, for the Echo-Wall integration's panel preview (docs/integration.md): lib/preview.dart
# compiled with Flutter, then what a browser loads copied into custom_components/echo_wall/frontend/preview/, served by
# the integration at /echo_wall/preview/.  CanvasKit goes along (Home Assistant may have no internet), its build for
# every browser only (web/flutter_bootstrap.js picks it), without debug symbols.  Rerun after a change to the WallView
# and commit the result with it.
#
#   tools/preview.sh
set -eu
app=$(cd "$(dirname "$0")/.." && pwd)
flutter=${FLUTTER:-$(command -v flutter || echo "$HOME/flutter/bin/flutter")}
out="$app/custom_components/echo_wall/frontend/preview"
(cd "$app" && "$flutter" build web -t lib/preview.dart --release --base-href /echo_wall/preview/ --no-web-resources-cdn \
    --no-source-maps --pwa-strategy=none)
src="$app/build/web"
rm -rf "$out"; mkdir -p "$out/canvaskit"
cp "$src/index.html" "$src/flutter_bootstrap.js" "$src/main.dart.js" "$out/"
cp -r "$src/assets" "$out/"
cp "$src/canvaskit/canvaskit.js" "$src/canvaskit/canvaskit.wasm" "$out/canvaskit/"
(cd "$app" && printf 'Echo-Wall %s%s, built %s\n' "$(git rev-parse --short HEAD)" "$(git diff --quiet || echo ' + changes')" \
    "$(date -u +%Y-%m-%dT%H:%MZ)") > "$out/BUILT_FROM"
du -sh "$out"
