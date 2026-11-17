#!/bin/bash
# The dictionary must change whole words only. Runs each helper built on this machine: tests/dictionary.sh
cd "$(dirname "$0")/.." || exit 1
HOME=$(mktemp -d)
export HOME
mkdir -p "$HOME/.claude"
echo '{"replace": {"acmi": "Acme", "cloud code": "Claude Code", "teh": "the"}}' > "$HOME/.claude/vox.json"
cases=(
  "acmi is up|Acme is up"
  "Ask ACMI.|Ask Acme."
  "acmi-based tools|Acme-based tools"
  "acmi's plan|Acme's plan"
  "open cloud code now|open Claude Code now"
  "piacmi and acmil stay|piacmi and acmil stay"
  "my_acmi stays|my_acmi stays"
  "www.acmi.com stays|www.acmi.com stays"
  "see /acmi/docs|see /acmi/docs"
  "acmi2 stays|acmi2 stays"
  "tehran stays, teh fixes|tehran stays, the fixes"
)
fails=0
check() {
  for c in "${cases[@]}"; do
    got=$("$@" "${c%%|*}")
    [ "$got" = "${c#*|}" ] || { echo "FAIL $1: '${c%%|*}' -> '$got', want '${c#*|}'"; fails=$((fails + 1)); }
  done
}
[ -x helper/macos/.build/release/vox-helper ] && check helper/macos/.build/release/vox-helper --fix
py=${VOX_PYTHON:-python3}; "$py" -c "import numpy" 2>/dev/null && check "$py" helper/linux/helper.py --fix
[ $fails = 0 ] && echo "dictionary: all ${#cases[@]} cases pass" || exit 1
