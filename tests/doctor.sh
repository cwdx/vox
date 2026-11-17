#!/bin/bash
# The setup check names what an empty machine lacks, and nothing once it is installed. tests/doctor.sh
cd "$(dirname "$0")/.." || exit
HOME=$(mktemp -d)
export HOME
out=$(bin/vox-doctor)
for need in scripts sounds hooks settings; do
  grep -q "^$need" <<< "$out" || { echo "FAIL: an empty machine should lack $need"; exit 1; }
done
mkdir -p ~/.claude/hooks ~/.claude/sounds/pack
cp bin/vox vox.default.json ~/.claude/hooks/
echo '{"hooks":{"Stop":[{"hooks":[{"command":"'"$HOME"'/.claude/hooks/vox stop"}]}]}}' > ~/.claude/settings.json
out=$(bin/vox-doctor | grep -v '(optional)' | grep -v '^helper' | grep -v '^swift')
[ -z "$out" ] || { echo "FAIL: installed parts still listed: $out"; exit 1; }
echo "doctor: all checks pass"
