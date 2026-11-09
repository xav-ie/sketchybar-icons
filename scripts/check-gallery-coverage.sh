#!/usr/bin/env bash
# Fails when an example plugin draws an SF Symbol the README gallery doesn't
# show, so a new state can't ship without its picture.
#   check-gallery-coverage.sh [repo root]
set -euo pipefail
cd "${1:-.}"

# Gallery tiles: the symbol argument of each wifi/sysicon/appicon call, plus a
# wifi tile's badge (its fifth argument).
gallery=$(awk '$1 ~ /^(wifi|sysicon|appicon)$/ && NF >= 2 { print $2 } $1 == "wifi" && NF >= 6 { print $6 }' scripts/render-gallery.sh | tr -d '"' | sort -u)

# Drawn by the examples: `sym:`/`badge:` specs, and front_app's fallback table.
used=$({
  grep -ohE '(sym|badge): "[^"]+"' examples/*.nu | sed -E 's/(sym|badge): "(.*)"/\2/'
  sed -n '/^const FALLBACK_SYMBOLS = {/,/^}/p' examples/front_app.nu | awk 'NF >= 2 && $1 ~ /:$/ { print $2 }'
} | sort -u)

missing=$(comm -23 <(echo "$used") <(echo "$gallery"))
if [ -n "$missing" ]; then
  echo "gallery: these symbols are drawn by examples/ but missing from scripts/render-gallery.sh:" >&2
  echo "$missing" | sed 's/^/  /' >&2
  exit 1
fi
echo "gallery covers all $(echo "$used" | wc -l | tr -d ' ') symbols the examples draw."
