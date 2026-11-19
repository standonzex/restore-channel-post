#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -x "dist/Restore Channel Post.app/Contents/MacOS/RestoreChannelPost" ]; then
    ./build.sh
fi
open "dist/Restore Channel Post.app"
