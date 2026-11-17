# Architecture

How vox is put together, for whoever changes it next.

## Bird's eye view

vox gives Claude Code a voice and ears. Three parts that never import each other (the helper is installed as `~/.claude/hooks/vox-helper` from `helper/macos` or `helper/linux`) talk through files in
`~/.claude/sounds/` and one settings file:

```
 Claude Code ──hooks──▶ bin/vox ──"play/queue <file>"──▶ .voice.fifo ──▶ helper ──▶ speakers
      ▲                    │                                                │  ▲
      │                    └── sounds, speech (direct when no helper)       │  └── mic
      │                                                                     ▼
   the mod ◀──── reads .voice.state (150 ms) ◀──── writes ──────────────  helper ──types──▶ herdr pane
```

- **bin/vox** (installed as `~/.claude/hooks/vox`) turns hook events into sounds and speech.
- **The helper** owns the microphone and the speakers. It types what you say into the focused herdr pane and plays
  Claude's speech, so on macOS its echo cancelling lets you talk over Claude.
- **The mod** draws the band and pane and flips settings. It never touches audio itself.

## Codemap

| Path | Lines | What |
| --- | --- | --- |
| `hooks/` | ~750 | The mod. `register.tsx` wires `/vox` and the two drawings; `band.tsx` the line above the prompt, `pane.tsx` its expanded view in the same place; `state.ts` reads the helper and the script; `mascot.ts`, `font.ts`, `meter.ts` draw; `shell.ts` runs the script and setup; `switches.tsx` the switches |
| `bin/vox` | ~610 | Hook handler and CLI in Python (standard library only): `play`/`synth` per platform, the thinking loop, focus gating, `state` |
| `bin/vox-doctor` | ~80 | Lists what this machine lacks; empty output means ready |
| `install.sh` | ~65 | What `/vox setup` runs: tools, files, hooks, the helper |
| `helper/macos/Sources/vox-helper/` | ~560 | macOS helper (Swift package), a file per concern (`Typing`, `Recording`, `FinalPass`, `Voiceprint`, `Jev`, `Commands`, `Settings`, `main`): AVAudioEngine voice processing, Apple live text, Parakeet final pass (FluidAudio), voiceprint, Jev |
| `helper/linux/helper.py` | ~320 | Linux/WSL helper: silero VAD, Parakeet (sherpa-onnx), the same FIFO and state contract |
| `sounds/pack/` | 27 wav | Shipped earcons; `sounds/make.sh` re-renders them (needs sox) |
| `vox.default.json` | | Every setting's default |
| `skills/`, `output-styles/` | | How Claude works with vox, and replies written to be heard |
| `tests/` | | `vox.sh` (settings, sounds, speech, focus against stand-ins), `doctor.sh`, `dictionary.sh`, `keyword.sh`, `mod.test.tsx` |

## Contracts

- **Settings.** Defaults in `vox.default.json`, the user's changes in `~/.claude/vox.json`, then the nearest
  project's `.claude/vox.json` and `.claude/vox.local.json`. `vox` merges them in that order; switches write the user's file. The helpers
  serve every pane, so they read only the user's `vox.json` and carry the same defaults in code.
- **FIFO** `~/.claude/sounds/.voice.fifo`, one command per line: `play <file>`, `queue <file>` (with `<file>.txt`
  holding its words), `stop`, `pane <id>`, `enroll`. The helper deletes a file once played.
- **State** `~/.claude/sounds/.voice.state`: JSON several times a second (levels, text, sent, verdict, wait,
  speaking, spoken, pane, asr, me, jev). The mod only reads it.
- **Speaker** `~/.claude/sounds/.voice.speaker`: the pane whose speech is playing, so other panes don't show it.

## Invariants

- One voice for many sessions: only the focused Claude pane speaks, pulses and receives dictation; the others chime.
- Dictation follows focus, even mid-message.
- A drawing never writes state; the mod's poll does every write.
- The dictionary changes whole words only. Letters, digits, `_` and an inner `.` or `/` keep a word whole, so
  code, paths and addresses never change.
- With "only me" on, an unrecognised voice can neither send nor command; with "auto listen" off, neither can words that do
  not start with a keyword, and they never stop Claude's voice.
- Secrets are never written to disk by vox: a Jev key lives only in the helper's environment.
- Nothing needs root unless setup must install a package, and setup never waits on a password.
