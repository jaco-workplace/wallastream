#!/bin/zsh
# Bouwt een zelfstandige Wallastream.app (met OwnTone en alle libraries erin) plus een zip om te delen.
# OwnTone moet eerst gebouwd zijn: ./scripts/build-owntone.sh
set -euo pipefail
ROOT="${0:A:h}"
APP="$ROOT/build/Wallastream.app"
OT="$APP/Contents/Resources/owntone"
VERSION="${VERSION:-1.2}"

[ -x "$ROOT/runtime/usr/sbin/owntone" ] || { echo "OwnTone ontbreekt, draai eerst ./scripts/build-owntone.sh"; exit 1; }

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$OT"
cp .build/release/Wallastream "$APP/Contents/MacOS/Wallastream"
cp runtime/usr/sbin/owntone runtime/usr/lib/owntone/owntone-sqlext.so "$OT/"
cp Resources/owntone.conf.template "$OT/"
cp LICENSE "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"  # opnieuw maken: zie scripts/make-icon.swift
cp vendor/owntone-server/COPYING "$OT/COPYING"

# Alle niet-systeemlibraries (Homebrew, libinotify) in de app kopiëren en de verwijzingen omzetten.
dylibbundler -of -b -cd -ns -x "$OT/owntone" -x "$OT/owntone-sqlext.so" \
  -d "$OT/lib" -p @executable_path/lib/ >/dev/null

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Wallastream</string>
    <key>CFBundleIdentifier</key><string>nl.wallastream.app</string>
    <key>CFBundleExecutable</key><string>Wallastream</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$(vtool -show-build "$OT/owntone" | awk '/minos/ {print $2; exit}')</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Wallastream vangt de geluidsuitvoer van je Mac op om die naar je AirPlay-speakers te sturen.</string>
</dict>
</plist>
EOF

# Ad-hoc ondertekenen, van binnen naar buiten. Zet SIGN_ID voor een Developer ID-certificaat.
SIGN_ID="${SIGN_ID:--}"
for f in "$OT"/lib/*.dylib "$OT/owntone-sqlext.so" "$OT/owntone"; do
  codesign --force --sign "$SIGN_ID" --timestamp=none "$f"
done
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"

ditto -c -k --keepParent "$APP" "$ROOT/build/Wallastream-$VERSION.zip"
echo "Klaar: $APP ($(du -sh "$APP" | cut -f1)), zip: build/Wallastream-$VERSION.zip"
