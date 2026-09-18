#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root/apps/ios"

action="${1:-}"
if [ "$#" -gt 0 ]; then shift; fi

# `--release` builds the optimized configuration; other arguments go to xcodebuild.
configuration=Debug
passthrough=()
for arg in "$@"; do
  if [ "$arg" = "--release" ]; then
    configuration=Release
  else
    passthrough+=("$arg")
  fi
done
set -- "${passthrough[@]+"${passthrough[@]}"}"

xcode() {
  xcodebuild \
    -project DreamApp.xcodeproj \
    -scheme DreamApp \
    -configuration "$configuration" \
    "$@"
}

case "$action" in
  build)
    xcode -destination 'generic/platform=iOS Simulator' build "$@"
    ;;

  test)
    xcode -sdk iphonesimulator test "$@"
    ;;

  run)
    # iPhone 18 Pro / iOS 27.0. Override with IOS_SIMULATOR_ID for another device.
    simulator="${IOS_SIMULATOR_ID:-61CBAB38-EA8A-4898-9F1E-5C50142D1662}"
    destination="platform=iOS Simulator,id=$simulator"
    derived_data="$HOME/Library/Developer/Xcode/DerivedData/DreamApp-Run-$configuration"

    xcrun simctl bootstatus "$simulator" -b
    open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app \
      "devices:///device/open?id=$simulator"
    xcode -destination "$destination" \
      -derivedDataPath "$derived_data" build

    app="$derived_data/Build/Products/$configuration-iphonesimulator/DreamApp.app"
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
    xcrun simctl install "$simulator" "$app"
    xcrun simctl launch --terminate-running-process "$simulator" "$bundle_id"
    ;;

  run-device)
    device="${IOS_DEVICE_NAME:-iPhone Pro (Vlad)}"
    derived_data="$HOME/Library/Developer/Xcode/DerivedData/DreamApp-Device-$configuration"

    xcode -destination "platform=iOS,name=$device" \
      -derivedDataPath "$derived_data" \
      -allowProvisioningUpdates build

    app="$derived_data/Build/Products/$configuration-iphoneos/DreamApp.app"
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
    xcrun devicectl device install app --device "$device" "$app"

    # A locked phone refuses launches; the app is installed, so just say so.
    launch_log=$(mktemp)
    if ! xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle_id" >"$launch_log" 2>&1; then
      if grep -q "could not be, unlocked" "$launch_log"; then
        echo "Installed. Phone is locked, so open DreamApp Dev manually." >&2
      else
        cat "$launch_log" >&2
        rm -f "$launch_log"
        exit 1
      fi
    fi
    rm -f "$launch_log"
    ;;

  *)
    echo "Usage: bash tools/run-ios.sh build|test|run|run-device [--release]" >&2
    exit 2
    ;;
esac
