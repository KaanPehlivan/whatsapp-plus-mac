#!/bin/sh
# Builds "WhatsApp+.app" and installs it to /Applications. Never change the bundle id in Info.plist:
# the WhatsApp logins and the notification/microphone permissions are tied to it.
set -e
cd "$(dirname "$0")"
APP="WhatsApp+.app"
[ -f AppIcon.icns ] || { swift make-icon.swift && iconutil -c icns AppIcon.iconset && rm -r AppIcon.iconset; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O main.swift -o "$APP/Contents/MacOS/WhatsApp+"
cp Info.plist "$APP/Contents/"
cp navy.css AppIcon.icns "$APP/Contents/Resources/"
# An Apple Development certificate keeps permissions across rebuilds; without one, sign ad hoc.
SIGN=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}') # first one, by hash
[ -n "$SIGN" ] || SIGN=-
codesign --force --sign "$SIGN" "$APP"
rm -rf "/Applications/$APP"
ditto "$APP" "/Applications/$APP"
echo "Installed /Applications/$APP"
