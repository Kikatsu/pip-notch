#!/bin/sh
# Records Pip's demo mode on your main display for the hybrid reveal shot.
# Tidy your desktop first; the whole screen is recorded. Needs Screen Recording permission for your terminal.
set -e
APP="${PIP_APP:-../build/DerivedData/Build/Products/Debug/Pip.app}"
OUT="public/footage/pip-demo.mov"
mkdir -p public/footage
osascript -e 'quit app "Pip"' 2>/dev/null || true
sleep 1
open "$APP" --args --demo
sleep 1
echo "Recording 20 s to $OUT…"
screencapture -v -V 20 -k "$OUT"
echo "Done. Set REAL_FOOTAGE = 'footage/pip-demo.mov' in src/config.ts."
