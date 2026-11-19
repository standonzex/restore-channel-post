#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcrun --find simctl >/dev/null 2>&1; then
    echo 'Full Xcode and the iOS Simulator component are required. See IOS-SETUP.md.' >&2
    exit 2
fi
RECOVERY_IOS_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
RECOVERY_IOS_ARCH="$(uname -m)"
RECOVERY_IOS_TARGET="$RECOVERY_IOS_ARCH-apple-ios16.0-simulator"
RECOVERY_IOS_BUILD=dist/ios-simulator
RECOVERY_IOS_APP="$RECOVERY_IOS_BUILD/RestoreChannelPost.app"
mkdir -p "$RECOVERY_IOS_BUILD/module" "$RECOVERY_IOS_APP"
xcrun --sdk iphonesimulator swiftc -parse-as-library -emit-library -static -emit-module \
    -module-name ChannelRecoveryKit -target "$RECOVERY_IOS_TARGET" -sdk "$RECOVERY_IOS_SDK" \
    -warnings-as-errors module/Sources/ChannelRecoveryKit/*.swift \
    -emit-module-path "$RECOVERY_IOS_BUILD/module/ChannelRecoveryKit.swiftmodule" \
    -o "$RECOVERY_IOS_BUILD/module/libChannelRecoveryKit.a"
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$RECOVERY_IOS_TARGET" -sdk "$RECOVERY_IOS_SDK" \
    -I "$RECOVERY_IOS_BUILD/module" -L "$RECOVERY_IOS_BUILD/module" -lChannelRecoveryKit \
    -framework SwiftUI -framework AVKit -framework UIKit -warnings-as-errors \
    app/Sources/RecoveryModel.swift ios-demo/*.swift \
    -o "$RECOVERY_IOS_APP/RestoreChannelPost"
cat > "$RECOVERY_IOS_APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RestoreChannelPost</string>
<key>CFBundleIdentifier</key><string>local.again.channelrecovery.iosreference</string>
<key>CFBundleName</key><string>Restore Channel Post</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>18</string>
<key>CFBundleShortVersionString</key><string>1.8</string>
<key>MinimumOSVersion</key><string>16.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST
python3 tools/sign_reference_app.py "$RECOVERY_IOS_APP"
echo "Built simulator demo: $RECOVERY_IOS_APP"
