#!/bin/bash
# Runs the StoreKitTest paywall suite in TestHost/ (macOS host app).
# SKTestSession needs an app with a bundle identifier, so this cannot run
# under `swift test`. Requires XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/../TestHost"
xcodegen generate --quiet
exec xcodebuild test \
  -project PaywallTestHost.xcodeproj \
  -scheme PaywallTestHost \
  -destination 'platform=macOS' \
  -quiet "$@"
