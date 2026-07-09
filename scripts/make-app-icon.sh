#!/bin/bash
# Regenerates Resources/AppIcon.icns from logo.png.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
ICONSET="$TMPDIR/AppIcon.iconset"
mkdir -p "$ICONSET"

while read -r name pixels; do
    sips -z "$pixels" "$pixels" "$ROOT/logo.png" --out "$ICONSET/$name.png" >/dev/null
done <<'SIZES'
icon_16x16 16
icon_16x16@2x 32
icon_32x32 32
icon_32x32@2x 64
icon_128x128 128
icon_128x128@2x 256
icon_256x256 256
icon_256x256@2x 512
icon_512x512 512
icon_512x512@2x 1024
SIZES

mkdir -p "$ROOT/Resources"
python3 - "$ICONSET" "$ROOT/Resources/AppIcon.icns" <<'PY'
from pathlib import Path
import struct
import sys

iconset = Path(sys.argv[1])
output = Path(sys.argv[2])
chunks = [
    (b"ic04", "icon_16x16.png"),
    (b"ic05", "icon_32x32.png"),
    (b"ic11", "icon_16x16@2x.png"),
    (b"ic12", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic13", "icon_128x128@2x.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic14", "icon_256x256@2x.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]

body = bytearray()
for icon_type, filename in chunks:
    data = (iconset / filename).read_bytes()
    body += icon_type + struct.pack(">I", len(data) + 8) + data

output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY
echo "Wrote Resources/AppIcon.icns - rebuild the bundle to apply."
