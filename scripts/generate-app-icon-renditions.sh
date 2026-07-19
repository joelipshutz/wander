#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
icon_dir="$repo_root/Wander/Resources/Assets.xcassets/AppIcon.appiconset"
canonical_master="$icon_dir/Icon-1024.png"
source_master=${1:-$canonical_master}

if [ ! -f "$source_master" ]; then
  echo "Icon master not found: $source_master" >&2
  exit 1
fi

if [ "$source_master" != "$canonical_master" ]; then
  cp "$source_master" "$canonical_master"
fi

sips -z 1024 1024 "$canonical_master" --out "$canonical_master" >/dev/null

for rendition in \
  "Icon-20@2x.png:40" \
  "Icon-20@3x.png:60" \
  "Icon-29@2x.png:58" \
  "Icon-29@3x.png:87" \
  "Icon-40@2x.png:80" \
  "Icon-40@3x.png:120" \
  "Icon-60@2x.png:120" \
  "Icon-60@3x.png:180"
do
  filename=${rendition%%:*}
  pixels=${rendition##*:}
  sips -z "$pixels" "$pixels" "$canonical_master" --out "$icon_dir/$filename" >/dev/null
done

for rendition in \
  "Icon-20@2x.png:40" \
  "Icon-20@3x.png:60" \
  "Icon-29@2x.png:58" \
  "Icon-29@3x.png:87" \
  "Icon-40@2x.png:80" \
  "Icon-40@3x.png:120" \
  "Icon-60@2x.png:120" \
  "Icon-60@3x.png:180" \
  "Icon-1024.png:1024"
do
  filename=${rendition%%:*}
  pixels=${rendition##*:}
  metadata=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$icon_dir/$filename")
  echo "$metadata" | grep -q "pixelWidth: $pixels"
  echo "$metadata" | grep -q "pixelHeight: $pixels"
  echo "$metadata" | grep -q "hasAlpha: no"
done

echo "Generated and validated rec.me app icon renditions."
