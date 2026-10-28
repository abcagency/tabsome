#!/bin/zsh
# Publishes a release that scripts/release.sh built (PLAN.md §7 Phase 7c). This is the only step
# that makes anything public, and it asks first:
#   1. pushes main, so the release's tag points at code that's on GitHub
#   2. creates the GitHub release v<version> with the DMG and the release notes
#   3. commits and pushes the update feed (docs/appcast.xml), which GitHub Pages serves
# The DMG goes up before the feed, so the feed never points at a file that isn't there yet.
#   scripts/publish.sh <version>
set -euo pipefail
cd "${0:A:h}/.."

REPO=abcagency/tabsome
VERSION=${1:?usage: scripts/publish.sh <version>}
DMG=build/release/$VERSION/Tabsome-$VERSION.dmg
NOTES=docs/releases/$VERSION.md
sparkle=build/release-derived/SourcePackages/artifacts/sparkle/Sparkle/bin

fail() { print -P "%F{red}error:%f $1" >&2; exit 1 }

[[ -f $DMG ]] || fail "no $DMG; run scripts/release.sh $VERSION first"
[[ -f $NOTES ]] || fail "no release notes at $NOTES"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" docs/appcast.xml || fail "docs/appcast.xml has no entry for $VERSION"
"$sparkle/sign_update" --account tabsome --verify docs/appcast.xml || fail "the feed's signature doesn't verify"
xcrun stapler validate -q "$DMG" || fail "the DMG has no notarization ticket"
[[ $(git branch --show-current) == main ]] || fail "not on main"
others=$(git status --porcelain | grep -v -E " docs/(appcast\.xml|releases/|\.nojekyll)" || true)
[[ -z $others ]] || fail "commit or stash other changes first:\n$others"
gh release view "v$VERSION" --repo $REPO >/dev/null 2>&1 && fail "v$VERSION is already released"
gh api "repos/$REPO/pages" >/dev/null 2>&1 || print -P "%F{yellow}warning:%f GitHub Pages isn't on for $REPO, so the feed won't be served yet"

print "About to publish Tabsome $VERSION:"
print "  - push main to github.com/$REPO"
print "  - create release v$VERSION with $(basename $DMG) ($(du -h "$DMG" | cut -f1 | tr -d ' ')) and $NOTES"
print "  - commit and push docs/appcast.xml (live at https://abcagency.github.io/tabsome/appcast.xml)"
read -q "?Publish? [y/N] " || { print "\nNothing published."; exit 1 }
print

git push origin main
gh release create "v$VERSION" "$DMG" --repo $REPO --target "$(git rev-parse HEAD)" \
  --title "Tabsome $VERSION" --notes-file "$NOTES"
git add docs/appcast.xml docs/releases docs/.nojekyll
git commit -m "Release $VERSION: update feed"
git push origin main
print "Published. GitHub Pages updates the feed within a minute or two."
