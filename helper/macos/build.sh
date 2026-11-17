#!/bin/bash
# Builds the helper (a Swift package; the first build fetches and compiles FluidAudio, which takes a while).
# `build.sh <pane>` also restarts it, typing into that herdr pane.
set -eo pipefail
cd "$(dirname "$0")"
swift build -c release 2>&1 | tail -1
cp .build/release/vox-helper ./vox-helper
[ -n "$1" ] || exit 0
pkill -f "hooks/vox-helper/" || true
sleep 0.5
nohup ./run.sh "$1" >> ~/.claude/sounds/.voice.log 2>&1 &
