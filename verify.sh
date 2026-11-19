#!/bin/sh
set -eu
cd "$(dirname "$0")"
python3 -m unittest discover -s tests -v
TEST_DIR="$(mktemp -d -t channel-recovery-tests)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc ios/Sources/ChannelPostRecoveryPolicy.swift tests/PolicyTests.swift -o "$TEST_DIR/policy"
"$TEST_DIR/policy"
swift run --package-path module RecoveryKitChecks
swift build --package-path module -c release --product ChannelRecoveryKit
MODULE_BUILD_PATH="$(swift build --package-path module -c release --show-bin-path)"
swiftc -parse-as-library -I "$MODULE_BUILD_PATH/Modules" -L "$MODULE_BUILD_PATH" -lChannelRecoveryKit tests/ClientSmokeTests.swift -o "$TEST_DIR/client"
python3 tools/run_client_test.py "$TEST_DIR/client"
swiftc -parse-as-library -I "$MODULE_BUILD_PATH/Modules" -L "$MODULE_BUILD_PATH" -lChannelRecoveryKit \
    -warnings-as-errors app/Sources/RecoveryModel.swift app/Sources/DemoHost.swift tests/ModelFlowTests.swift -o "$TEST_DIR/model"
"$TEST_DIR/model"
swiftc -frontend -parse ios/Sources/*.swift
if [ -n "${RECOVERY_TELEGRAM_CHECKOUT:-}" ]; then
    python3 tools/verify_native_patch.py "$RECOVERY_TELEGRAM_CHECKOUT"
fi
./build.sh
codesign --verify --deep --strict 'dist/Restore Channel Post.app'
echo 'Verification complete: reference app built; iOS patch syntax checked only.'
