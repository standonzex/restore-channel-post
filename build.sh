#!/bin/sh
set -eu
cd "$(dirname "$0")"
APP="dist/Restore Channel Post.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/server" "$APP/Contents/Resources/media"
if [ ! -f app/Resources/media/demo-circle.mov ] || [ ! -f app/Resources/media/demo-photo.png ]; then
    GENERATOR="$(mktemp -t recovery-media-generator)"
    trap 'rm -f "$GENERATOR"' EXIT
    swiftc tools/GenerateMedia.swift -o "$GENERATOR"
    "$GENERATOR" app/Resources/media
fi
swift build --package-path module -c release --product ChannelRecoveryKit
MODULE_BUILD_PATH="$(swift build --package-path module -c release --show-bin-path)"
swiftc -parse-as-library -I "$MODULE_BUILD_PATH/Modules" -L "$MODULE_BUILD_PATH" -lChannelRecoveryKit -target "$(uname -m)-apple-macosx13.0" -O -warnings-as-errors -framework AVKit -framework AppKit app/Sources/*.swift -o "$APP/Contents/MacOS/RestoreChannelPost"
cp server/recovery.py server/http_api.py "$APP/Contents/Resources/server/"
cp app/Resources/media/demo-photo.png app/Resources/media/demo-circle.mov "$APP/Contents/Resources/media/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RestoreChannelPost</string>
<key>CFBundleIdentifier</key><string>local.again.restore-channel-post.reference</string>
<key>CFBundleName</key><string>Restore Channel Post</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.8</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
python3 tools/sign_reference_app.py "$APP"
echo "Built: $APP"
