---
name: vox-voice
description: >-
  Use when the user asks to change, fix or extend the vox voice setup for Claude Code: replies read aloud,
  sound effects, the thinking loop, hands-free dictation, talking over Claude, auto-send timing, the vox mod
  or /vox, or says "nothing happens", "it keeps playing", "it doesn't hear me" or "too slow".
---

# vox-voice

**Goal.** Vox lets someone work with Claude Code without looking at the screen or typing, on macOS inside the
herdr terminal. So every change keeps two promises: whatever the user needs to know is also heard, and whatever
they need to do also works by voice or by a single key.

**How it works.** Claude's hooks call one script, `vox`, which plays a sound for each event, loops a quiet
sound while Claude works (a different one while a blocking shell command runs), and reads steps, multiple-choice
questions and the reply aloud as it streams. A Swift helper owns the microphone with macOS echo cancelling, so it
hears the user and not Claude: it types the user's words live into the herdr pane, stops Claude's voice at the
user's first word, and sends when Jev (TypeSafe) judges the thought finished. The vox mod draws one band above
the prompt: the fox mascot with the one state everything shares (off, listening, hearing you, paused, working,
talking), the mic and voice switches, an equalizer, the live words and Jev's verdict. Clicking the fox or ⤢ (or
`/vox full`) expands the band in place, above the prompt, into the full view, the only place for more: a tall equalizer, its own 3×5 pixel font for the last words of the user and
Claude's reply, Jev's calls with their latency and every switch. A pane must not write state
while it draws; the 150 ms poll does all writes.

| Part | Path | Owns |
| --- | --- | --- |
| Settings | `~/.claude/vox.json` over `hooks/vox.default.json` | what the user changed, over the defaults; change with `vox set` or `vox use` |
| Hook script | `~/.claude/hooks/vox` | sounds, loops, read-outs, `state` JSON; its header lists every command |
| Hook wiring | `~/.claude/settings.json`, the entries that call `hooks/vox` | which events reach the script |
| Dictation helper | `~/.claude/hooks/vox-helper/` (macOS: Swift, `build.sh <pane>` rebuilds and restarts; Linux: `helper.py`) | mic, dictation, auto-send, talk-over, speech playback |
| Final pass | inside the helper (FluidAudio, Neural Engine) | re-reads each message before it sends; `vox.json` `asr` picks parakeet (v2), ultra, whisper or apple |
| Only me | inside the helper (CAM++ voiceprint) | `vox.json` `onlyMe`/`meThreshold` (0.5); `echo enroll > ~/.claude/sounds/.voice.fifo` re-registers from the last 20 takes (each under 60 s); `vox-helper --likeness <wav>` scores a clip; a dropped message logs "ignored, not the owner" |
| Several sessions | `vox` `is_focused` | only the focused herdr pane speaks and pulses; the others just chime |
| Sounds | `~/.claude/sounds/make.sh` → `pack/*.wav` | the earcons and how they are levelled |
| Mod | the plugin `vox@vox` (`/vox setup` or `install.sh` installs the rest) | the band, its full view and `/vox` |
| Reply style | `~/.claude/output-styles/vox-voice.md` | how replies are written to be heard |
| Stop key | `~/.config/herdr/config.toml` | the herdr key that silences everything |

## Act on a spoken request

When the user asks by voice to open, close, expand or collapse the vox pane, run it yourself:
`herdr pane send-text "$HERDR_PANE_ID" "/vox full"` then `herdr pane send-keys "$HERDR_PANE_ID" Enter`; it toggles,
and runs once the current turn ends. Other `/vox` switches work the same way (`/vox mute` is `vox off`).

## Change something

1. Read `bin/vox` and the part that owns the behaviour; change only that part. A new switch lives in
   `vox.json`, is read with `get`, and gets a name in the mod's `SWITCHES`.
2. Rebuild what you touched: the helper with `build.sh <pane>`, the sounds with `make.sh` (hear them with
   `vox demo <kind>`), the mod with `claude plugin validate <repo>` and then
   `claude plugin update vox@vox`.
3. Verify on the real thing: the helper's log (`~/.claude/sounds/.voice.log`) records each Jev verdict and each
   send; `vox state` shows every switch; a screenshot shows the band.

Done when: the rebuilt part runs, its log, `vox state` or a screenshot shows the new behaviour, and the
user heard it.

## Why some code looks the way it does

- The voice engine refuses to start (`-10875`) when voice processing is enabled before the mixer node exists, so
  the helper touches `mainMixerNode` first. Voice processing hands over several channels; the recognizer gets one.
- A cancelled recognition task still calls back. Each callback checks its `generation`, or an old task restarts
  the new one and dictation goes deaf after the first message.
- An interrupted turn fires no hook, so the thinking loop watches the transcript for the interrupt and for silence.
  Keep both checks when changing `start_thinking`.
- `MessageDisplay` streams the reply in pieces. `vox display` speaks whole sentences in order under a lock,
  which is why Stop only plays the done sound.
- Echo cancelling covers only what the helper plays. Speech goes through the helper; sounds played with `afplay`
  reach the mic, which is why they stay short and quiet.
- Questions are read aloud even with step narration off, because the user answers them by number key without
  looking.
- The Jev key comes from the secret store into the helper's environment at start, and stays there. Check it by its
  length and an HTTP status, not by printing it.
- The final pass runs Parakeet through FluidAudio on the Neural Engine: four times faster than MLX for the same
  model. Its first load downloads Core ML weights; until it reports ready, Apple's live text is sent unchanged.

