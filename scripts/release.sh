#!/bin/zsh
# Builds a release (PLAN.md §7 Phases 7b, 7c): archive, Developer ID export through the company
# team's cloud-managed certificate, signature checks, notarization and stapling of the app, a DMG
# that is notarized and stapled too, and the DMG's entry in Sparkle's update feed
# (docs/appcast.xml), signed with the EdDSA key in the login keychain. Nothing is published:
# scripts/publish.sh does that.
#   scripts/release.sh [version]          version defaults to the project's MARKETING_VERSION
#   scripts/release.sh --no-notarize ...  stop after the signed export (no upload to Apple)
# Release notes for the feed and the GitHub release go in docs/releases/<version>.md (Markdown).
# The build number is the commit count, so every release from a new commit is newer for Sparkle.
# Needs the notarytool keychain profile "tabsome" (or $NOTARY_PROFILE):
#   xcrun notarytool store-credentials tabsome --apple-id <Apple ID> --team-id Y6BK74SSGR
set -euo pipefail
cd "${0:A:h}/.."

TEAM=Y6BK74SSGR
PROFILE=${NOTARY_PROFILE:-tabsome}
NOTARIZE=1
if [[ ${1:-} == --no-notarize ]]; then NOTARIZE=0; shift; fi
VERSION=${1:-$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Tabsome.xcodeproj/project.pbxproj | head -1)}
BUILD=$(git rev-list --count HEAD)
OUT=build/release/$VERSION
APP=$OUT/export/Tabsome.app
DMG=$OUT/Tabsome-$VERSION.dmg
NOTES=docs/releases/$VERSION.md
SPARKLE_KEY=tabsome   # the login keychain account generate_keys stored the key under

step() { print -P "\n%B==> $1%b" }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1 }

[[ -z $(git status --porcelain) ]] || print -P "%F{yellow}warning:%f the working tree has uncommitted changes; this build won't match a commit"
if (( NOTARIZE )); then
  [[ -f $NOTES ]] || fail "write the release notes first: $NOTES"
  step "Checking the notary profile \"$PROFILE\""
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "no notarytool profile \"$PROFILE\". Run: xcrun notarytool store-credentials $PROFILE --apple-id <Apple ID> --team-id $TEAM"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

step "Archiving $VERSION ($BUILD)"
xcodebuild archive -project Tabsome.xcodeproj -scheme Tabsome -configuration Release \
  -archivePath "$OUT/Tabsome.xcarchive" -derivedDataPath build/release-derived \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates -quiet

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$OUT/Tabsome.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates -quiet

step "Checking the signature"
codesign --verify --deep --strict "$APP" || fail "the signature doesn't verify"
details=$(codesign -dvv "$APP" 2>&1)
[[ $details == *"Developer ID Application:"*"($TEAM)"* ]] || fail "not signed with the team's Developer ID"
[[ $details == *"flags=0x10000(runtime)"* ]] || fail "hardened runtime is off"
entitlements=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
[[ $entitlements != *get-task-allow* ]] || fail "the build allows debugging (get-task-allow)"
print -r -- "$details" | grep -E "^Authority=Developer ID Application|^TeamIdentifier"

if (( ! NOTARIZE )); then
  step "Done (signed, not notarized): $APP"
  exit 0
fi

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$OUT/Tabsome.zip"
xcrun notarytool submit "$OUT/Tabsome.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$OUT/Tabsome.zip"

step "Building the DMG"
stage=$OUT/dmg
mkdir -p "$stage"
ditto "$APP" "$stage/Tabsome.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Tabsome $VERSION" -srcfolder "$stage" -fs APFS -format ULFO -ov "$DMG" -quiet
rm -rf "$stage"

step "Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# The DMG isn't code-signed: signing anything outside Xcode's export needs a Developer ID
# certificate on this Mac, and the team's is cloud-managed. It is notarized and stapled, which is
# what Gatekeeper checks when a downloaded disk image opens, and the app inside is fully signed.
step "Checking with Gatekeeper"
spctl --assess --type execute --verbose=2 "$APP"
xcrun stapler validate "$DMG"
mount=$(mktemp -d)
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$mount" -quiet
spctl --assess --type execute --verbose=2 "$mount/Tabsome.app" || { hdiutil detach "$mount" -quiet; fail "the app in the DMG doesn't pass Gatekeeper"; }
xcrun stapler validate "$mount/Tabsome.app"
hdiutil detach "$mount" -quiet

# Signed after stapling: the EdDSA signature covers the final bytes people download.
step "Adding $VERSION to the update feed"
sparkle=build/release-derived/SourcePackages/artifacts/sparkle/Sparkle/bin
signature=$("$sparkle/sign_update" --account "$SPARKLE_KEY" -p "$DMG")
python3 -I scripts/appcast.py docs/appcast.xml "$VERSION" "$BUILD" \
  "https://github.com/abcagency/tabsome/releases/download/v$VERSION/Tabsome-$VERSION.dmg" \
  "$(stat -f %z "$DMG")" "$signature" "$NOTES"
"$sparkle/sign_update" --account "$SPARKLE_KEY" docs/appcast.xml >/dev/null
"$sparkle/sign_update" --account "$SPARKLE_KEY" --verify docs/appcast.xml || fail "the feed's signature doesn't verify"
"$sparkle/sign_update" --account "$SPARKLE_KEY" --verify "$DMG" "$signature" || fail "the DMG's update signature doesn't verify"

step "Done (not published; run scripts/publish.sh $VERSION)"
print "  $DMG"
print "  version $VERSION, build $BUILD"
print "  sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
