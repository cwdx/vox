#!/bin/bash
# shellcheck disable=SC2016,SC2034  # expect evals single-quoted checks
# The hook script against stand-in players, voices and herdr: settings, sounds, speech and focus. tests/vox.sh
cd "$(dirname "$0")/.." || exit
HOME=$(mktemp -d)
export HOME
export PATH="$HOME/bin:$PATH" HERDR_PANE_ID=w1:p1 CLAUDE_CODE_ENTRYPOINT=cli
mkdir -p "$HOME/bin" "$HOME/.claude/hooks" "$HOME/.claude/sounds/pack"
cp bin/vox vox.default.json "$HOME/.claude/hooks/"
cp sounds/pack/tick-soft.wav sounds/pack/send-pop.wav "$HOME/.claude/sounds/pack/"
cd "$HOME" || exit
LOG=$HOME/calls
for tool in afplay say pw-play paplay aplay espeak-ng; do printf '#!/bin/sh\necho "%s $*" >> %s\n' "$tool" "$LOG" > "$HOME/bin/$tool"; done
focus() { printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"panes\":[{\"pane_id\":\"$1\",\"focused\":true,\"agent\":\"claude\"}]}}'" > "$HOME/bin/herdr"; chmod +x "$HOME/bin/herdr"; }
chmod +x "$HOME"/bin/*
vox() { "$HOME/.claude/hooks/vox" "$@"; }
fails=0
expect() { if eval "$2"; then :; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
jget() { python3 -c 'import json,sys
d = json.load(sys.stdin)
for k in filter(None, sys.argv[1].split(".")): d = d[k]
print(json.dumps(d, separators=(",", ":")) if isinstance(d, (dict, list)) else d)' "$1"; }
calls() { sleep 0.3; cat "$LOG" 2>/dev/null; : > "$LOG"; }

vox set rate 180 >/dev/null
expect "set writes only the change" '[ "$(jget . < ~/.claude/vox.json)" = "{\"rate\":180}" ]'
expect "defaults fill the rest" '[ "$(vox status | jget mode)" = full ]'
vox use tick tick-soft >/dev/null
expect "use picks a sound" '[ "$(jget sounds.tick < ~/.claude/vox.json)" = tick-soft ]'
calls >/dev/null
mkdir -p "$HOME/repo/.claude" "$HOME/repo/src"
echo '{"rate":220}' > "$HOME/repo/.claude/vox.json"
expect "a project's vox.json wins from inside it" '[ "$(cd ~/repo/src && vox status | jget rate)" = 220 ]'
expect "and through CLAUDE_PROJECT_DIR" '[ "$(CLAUDE_PROJECT_DIR=~/repo vox status | jget rate)" = 220 ]'
echo '{"rate":240}' > "$HOME/repo/.claude/vox.local.json"
expect "its vox.local.json wins over that" '[ "$(cd ~/repo && vox status | jget rate)" = 240 ]'
expect "outside it the user's stays" '[ "$(cd ~ && vox status | jget rate)" = 180 ]'

focus w1:p1
echo '{"session_id":"s","tool_name":"Read","tool_input":{"file_path":"/a/notes.md"}}' | vox tick
out=$(calls)
expect "a step plays its sound" 'grep -q "tick-soft.wav" <<< "$out"'
expect "a step is read aloud" 'grep -q "Reading notes.md" <<< "$out"'

echo '{"session_id":"s","message_id":"m","delta":"Done. The rest","final":false}' | vox display
expect "a streamed sentence is spoken whole" 'grep -q "Done." <<< "$(calls)"'

focus w9:p1
echo '{"session_id":"s","message_id":"n","delta":"Hidden. ","final":true}' | vox display
expect "an unfocused session stays quiet" '! grep -q Hidden <<< "$(calls)"'
echo '{"session_id":"s","tool_name":"Read","tool_input":{"file_path":"/a/b.md"}}' | vox tick
out=$(calls)
expect "an unfocused session still plays sounds" 'grep -q "tick-soft.wav" <<< "$out"'
expect "an unfocused session reads no steps" '! grep -q Reading <<< "$out"'

expect "state is one line of JSON" '[ "$(vox state s | jget listening)$(vox state s | jget thinking)" = FalseFalse ]'
echo '{"session_id":"s"}' | vox send
expect "a prompt starts the thinking loop" '[ "$(vox state s | jget thinking)" = True ]'
echo '{"session_id":"s"}' | vox notify
expect "a notification stops it" '[ "$(vox state s | jget thinking)" = False ]'
calls >/dev/null
vox off >/dev/null
echo '{"session_id":"s","tool_name":"Read","tool_input":{}}' | vox tick
expect "off is silent" '[ -z "$(calls)" ]'

[ $fails = 0 ] && echo "vox: all checks pass" || exit 1
