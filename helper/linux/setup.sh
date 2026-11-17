#!/usr/bin/env bash
# venv + sherpa-onnx Parakeet TDT 0.6B v2 int8 + silero VAD into ~/.cache/vox
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cache="$HOME/.cache/vox"
name=sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8
base=https://github.com/k2-fsa/sherpa-onnx/releases/download
mkdir -p "$cache"
python3 -m venv "$here/.venv"
"$here/.venv/bin/pip" install -q --upgrade pip
"$here/.venv/bin/pip" install -q sherpa-onnx sounddevice numpy
if [ ! -f "$cache/$name/tokens.txt" ]; then
  curl -fsSL "$base/asr-models/$name.tar.bz2" | tar -xj -C "$cache"
fi
[ -f "$cache/silero_vad.onnx" ] || curl -fsSL -o "$cache/silero_vad.onnx" "$base/asr-models/silero_vad.onnx"
echo "ready. PortAudio is needed for the mic: sudo apt install libportaudio2 (and pulseaudio-utils for paplay)"
