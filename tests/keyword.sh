#!/bin/bash
# With "auto listen" off, only words after a keyword are dictated. Runs each helper built on this machine: tests/keyword.sh
cd "$(dirname "$0")/.." || exit 1
HOME=$(mktemp -d)
export HOME
mkdir -p "$HOME/.claude"
echo '{"autoListen": false}' > "$HOME/.claude/vox.json"
cases=(
  "Claude, fix the bug.|Fix the bug."
  "hey Claude what's up|What's up"
  "  CLAUDE: run tests|Run tests"
  "claude|"
  "Fix the claude bug|(asleep)"
  "Claudette is here|(asleep)"
  "Fox, check the desk|Check the desk"
  "vox mute|Mute"
  "Foxes are fast|(asleep)"
)
fails=0
check() {
  for c in "${cases[@]}"; do
    got=$("$@" "${c%%|*}")
    [ "$got" = "${c#*|}" ] || { echo "FAIL $1: '${c%%|*}' -> '$got', want '${c#*|}'"; fails=$((fails + 1)); }
  done
}
[ -x helper/macos/.build/release/vox-helper ] && check helper/macos/.build/release/vox-helper --keyword
py=${VOX_PYTHON:-python3}; "$py" -c "import numpy" 2>/dev/null && check "$py" helper/linux/helper.py --keyword
echo '{}' > "$HOME/.claude/vox.json"
if [ -x helper/macos/.build/release/vox-helper ] && [ "$(helper/macos/.build/release/vox-helper --keyword "fix it")" != "fix it" ]; then echo "FAIL: auto listen passes everything"; fails=$((fails + 1)); fi
[ $fails = 0 ] && echo "keyword: all ${#cases[@]} cases pass" || exit 1
