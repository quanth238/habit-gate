#!/bin/zsh
set -eu
HG_PROJECT="${0:A:h:h}"
HG_ICON_TEMP="$(mktemp -d "${TMPDIR:-/tmp/}habitgate-icon.XXXXXX")"
trap 'rm -rf "$HG_ICON_TEMP"' EXIT
HG_ICONSET="$HG_ICON_TEMP/AppIcon.iconset"
mkdir -p "$HG_ICONSET"
swift "$HG_PROJECT/scripts/make-icon.swift" "$HG_PROJECT/Resources/AppIcon.png"
for HG_SIZE in 16 32 128 256 512; do
  sips -z "$HG_SIZE" "$HG_SIZE" "$HG_PROJECT/Resources/AppIcon.png" --out "$HG_ICONSET/icon_${HG_SIZE}x${HG_SIZE}.png" >/dev/null
  HG_RETINA=$((HG_SIZE * 2))
  sips -z "$HG_RETINA" "$HG_RETINA" "$HG_PROJECT/Resources/AppIcon.png" --out "$HG_ICONSET/icon_${HG_SIZE}x${HG_SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$HG_ICONSET" -o "$HG_PROJECT/Resources/AppIcon.icns"
print "Built: Resources/AppIcon.icns"
