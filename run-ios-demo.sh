#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ "$#" -eq 0 ]; then set -- booted; fi
python3 tools/run_ios_demo.py "$@"
