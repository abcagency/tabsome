#!/bin/sh
# PLAN.md §6.1 S1: Accessibility APIs may only appear in Core/AX/AXWindow.swift and
# Core/AX/AXApp.swift (and Core/AX/DockBadges.swift once it exists). The one exception is
# the trust check (AXIsProcessTrusted*) in Core/AX/Permissions.swift.
# Runs as a build phase and in CI; prints Xcode-style errors and fails the build on a violation.
set -eu
root="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root/Tabsome"

pattern='(AXUIElement|AXObserver|AXValue|AXError|AXIsProcessTrusted|AXCopy|AXMake|_AXUIElementGetWindow|kAX[A-Z][A-Za-z]*)'
allowed='^\./Core/AX/(AXWindow|AXApp|DockBadges)\.swift:'
trust_ok='^\./Core/AX/Permissions\.swift:[0-9]+:.*(AXIsProcessTrusted|kAXTrustedCheckOptionPrompt)'

violations=$(grep -rnE "$pattern" --include='*.swift' . | grep -vE "$allowed" | grep -vE "$trust_ok" || true)
if [ -n "$violations" ]; then
  echo "$violations" | while IFS= read -r line; do
    file=${line%%:*}; rest=${line#*:}; num=${rest%%:*}
    echo "$root/Tabsome/${file#./}:$num: error: Accessibility API used outside AXWindow.swift / AXApp.swift (PLAN.md §6.1 S1)"
  done
  exit 1
fi
echo "check-ax-usage: OK"
