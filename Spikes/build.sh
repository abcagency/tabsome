#!/bin/zsh
# Builds Spikes/out/TabsomeSpikes.app and Spikes/out/SpikeHelper.app.
# Signs with the first "Apple Development" identity (stable TCC grants across rebuilds);
# falls back to ad-hoc signing, in which case macOS forgets permissions on every rebuild.
set -euo pipefail
cd "${0:A:h}"
OUT=out
mkdir -p $OUT/logs

# xcodebuild/xcrun refuse to run until the Xcode license is accepted; the CLT toolchain works regardless.
if ! xcrun --find swiftc >/dev/null 2>&1 || ! xcrun swiftc --version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
SWIFTC=(xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0)

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [[ -z "$IDENTITY" ]]; then
  echo "warning: no Apple Development identity found; ad-hoc signing (permissions reset on each rebuild)"
  IDENTITY=-
fi

bundle() { # name bundleID sources...
  local name=$1 bid=$2; shift 2
  local app=$OUT/$name.app
  rm -rf $app; mkdir -p $app/Contents/MacOS
  cat > $app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$bid</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><$([[ $name == TabsomeSpikes ]] && echo true || echo false)/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
  "${SWIFTC[@]}" "$@" -o $app/Contents/MacOS/$name
  codesign --force --options runtime --timestamp=none -s "$IDENTITY" -i $bid $app
  echo "built $app (signed: ${IDENTITY})"
}

bundle TabsomeSpikes com.tabsome.spikes TabsomeSpikes/*.swift
bundle SpikeHelper com.tabsome.spikehelper SpikeHelper/main.swift
