#!/bin/bash
# Installs vox for Claude Code on macOS, Linux or WSL: scripts and sounds under ~/.claude, the hooks in
# ~/.claude/settings.json, the dictation helper, and the mod from this folder as a local marketplace. Safe to rerun.
# Needs python3. On Linux fetches espeak-ng and a player when missing. macOS builds the Swift helper (Xcode command line
# tools); Linux and WSL get dictation with --dictation (Python, ~650 MB of models). Optional: herdr, a TypeSafe key.
set -e
here=$(cd "$(dirname "$0")" && pwd)
c=~/.claude
case $(uname -s) in Darwin) os=mac ;; *) grep -qi microsoft /proc/version 2>/dev/null && os=wsl || os=linux ;; esac
# run from /vox setup there is no terminal for a password: sudo then only works when it needs none
root() { [ "$(id -u)" = 0 ] && { "$@"; return; }; if [ -t 0 ]; then sudo "$@"; else sudo -n "$@" 2>/dev/null || { echo "Needs root, run: sudo $*"; exit 1; }; fi; }
get() {  # get <command> <package>: installs the package when the command is missing
  command -v "$1" >/dev/null && return
  if [ "$os" = mac ]; then brew install "$2"
  elif command -v apt-get >/dev/null; then root apt-get update -qq && root apt-get install -y "$2"
  elif command -v dnf >/dev/null; then root dnf install -y "$2"
  elif command -v pacman >/dev/null; then root pacman -S --noconfirm "$2"
  elif command -v brew >/dev/null; then brew install "$2"
  else echo "Install $2, then run this again."; exit 1; fi
}
command -v python3 >/dev/null || { echo "vox needs python3 (macOS: xcode-select --install; Linux: your package manager)."; exit 1; }
if [ "$os" = linux ]; then
  command -v piper >/dev/null || get espeak-ng espeak-ng
  command -v pw-play >/dev/null || command -v paplay >/dev/null || command -v aplay >/dev/null || get paplay "$(command -v pacman >/dev/null && echo libpulse || echo pulseaudio-utils)"
fi
[ "$os" = mac ] && { command -v swift >/dev/null || { xcode-select --install; echo "Install the command line tools, then run this again."; exit 1; }; }

mkdir -p $c/hooks $c/sounds/pack $c/output-styles $c/skills/vox-voice
# earlier installs: speak.sh, speak.json and the helper folders voice/ and voice-lite/
[ -f $c/speak.json ] && [ ! -f $c/vox.json ] && mv $c/speak.json $c/vox.json
rm -f $c/hooks/speak.sh
for old in voice voice-lite; do [ -d $c/hooks/$old ] && [ ! -d $c/hooks/vox-helper ] && mv $c/hooks/$old $c/hooks/vox-helper; done
rm -rf $c/hooks/voice $c/hooks/voice-lite
cp "$here/bin/vox" "$here/vox.default.json" $c/hooks/
cp -n "$here"/sounds/pack/*.wav $c/sounds/pack/ 2>/dev/null || true
cp "$here/sounds/make.sh" $c/sounds/make.sh
cp "$here/output-styles/vox-voice.md" $c/output-styles/
cp "$here/skills/vox-voice/SKILL.md" $c/skills/vox-voice/
chmod +x $c/hooks/vox $c/sounds/make.sh

# hooks: drop any earlier vox entries, then add the current ones
s=$c/settings.json; [ -f "$s" ] || echo '{}' > "$s"
python3 - "$s" "$HOME/.claude/hooks/vox" <<'EOF'
import json, os, re, sys
path, vox = sys.argv[1:3]
with open(path) as f:
    settings = json.load(f)
hooks = settings.setdefault("hooks", {})
old = re.compile(r"speak\.sh|hooks/vox ")
for event, groups in hooks.items():
    hooks[event] = [g for g in groups if not old.search(" ".join(h.get("command", "") for h in g.get("hooks", [])))]
def add(event, command, matcher=None):
    group = {"hooks": [{"type": "command", "command": f"{vox} {command}", "async": True}]}
    if matcher:
        group = {"matcher": matcher, **group}
    hooks.setdefault(event, []).append(group)
add("UserPromptSubmit", "send")
add("PreToolUse", "tick")
add("PostToolUse", "after", "Bash")
add("PostToolUseFailure", "fail")
add("Notification", "notify")
add("Stop", "stop")
add("StopFailure", "stop")
add("MessageDisplay", "display")
if not settings.get("outputStyle"):
    settings["outputStyle"] = "vox-voice"
with open(path + ".tmp", "w") as f:
    json.dump(settings, f, indent=2)
os.replace(path + ".tmp", path)
EOF

# the dictation helper, from helper/macos (Swift) or helper/linux (Python), installed as hooks/vox-helper
if [ "$os" = mac ]; then
  mkdir -p $c/hooks/vox-helper && cp -R "$here"/helper/macos/{Package.swift,Package.resolved,Info.plist,build.sh,run.sh,Sources} $c/hooks/vox-helper/
  # each release ships the built helper for its version; compiling it (minutes, Xcode tools) is the fallback
  version=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$here/.claude-plugin/plugin.json")
  if command -v gh >/dev/null && gh release download "v$version" --repo cwdx/vox --pattern vox-helper --output $c/hooks/vox-helper/vox-helper --clobber 2>/dev/null; then
    chmod +x $c/hooks/vox-helper/vox-helper
  else
    $c/hooks/vox-helper/build.sh
  fi
elif [ "$1" = --dictation ]; then
  command -v apt-get >/dev/null && root apt-get install -y libportaudio2 python3-venv
  mkdir -p $c/hooks/vox-helper && cp "$here"/helper/linux/{helper.py,run.sh,setup.sh} $c/hooks/vox-helper/
  $c/hooks/vox-helper/setup.sh
fi
if command -v claude >/dev/null; then
  claude plugin marketplace add "$here" >/dev/null 2>&1 || true
  claude plugin install vox@vox >/dev/null 2>&1 || claude plugin update vox@vox >/dev/null 2>&1 || true
fi
echo "vox installed. Restart Claude Code. Live dictation needs herdr$([ "$os" = mac ] || echo ' and ./install.sh --dictation')."
