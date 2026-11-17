# vox

Talk to Claude Code and hear it talk back. Claude reads its replies, steps and questions aloud as they stream, plays
quiet sounds for each event, and loops a soft beat while it works. Say something and it types into the session, stops
Claude's voice when you start talking, and sends when you finish. A band above the prompt and a full pane show an
equalizer, the words in block letters, and every switch.

## Install

```
/plugin marketplace add cwdx/vox
/plugin install vox@vox
/vox setup
```

Restart Claude Code. The mod checks the machine at every start and names anything missing; `/vox doctor` lists it.
`./install.sh` from a clone does the same as `/vox setup`.

| | macOS | Linux | WSL |
| --- | --- | --- | --- |
| Speech | `say` | piper or espeak-ng | Windows voices |
| Sounds | afplay | pw-play, paplay or aplay | Windows player |
| Dictation | Swift helper, echo cancelled, talk over Claude | `/vox setup dictation`, Python helper | as Linux, through WSLg |

Needs Python 3 (standard library only). macOS builds the helper with the Xcode command line tools. Dictation types into
[herdr](https://herdr.dev) panes, so it needs herdr; speech and sounds work without it.

## Use

`/vox` lists the switches and flips them (`/vox steps`, `/vox think`, …); `/vox full` (or clicking the fox) expands the line above the prompt into the full view;
`/vox asr <parakeet|ultra|whisper|apple>` picks the macOS final pass. Settings: put what you change in `~/.claude/vox.json`; the rest come from `vox.default.json`.
A project's `.claude/vox.json`, then `.claude/vox.local.json` (kept out of git), override both for speech and sounds in that project; dictation settings stay in yours.
With several sessions open, only the herdr pane in focus speaks; the others chime.

- **Final pass.** Each message is re-read by Parakeet v2 before it sends: on the Neural Engine via FluidAudio on
  macOS (2.6% word errors, 0.06 s a message on an M2), with sherpa-onnx on the CPU elsewhere.
- **Only me.** `echo enroll > ~/.claude/sounds/.voice.fifo` registers your voice from your recent messages; with the
  pane's "only me" switch on, other voices are not sent. macOS only.
- **Auto listen.** On by default: everything you say is typed. `/vox auto` (or the pane's "auto" switch) turns it off,
  so only what follows "Vox", "Claude" or "Fox" is typed, like "Vox, run the tests"; `keywords` in `vox.json` sets others.
- **Jev.** Optional end-of-turn judging by TypeSafe: set `TYPESAFE_API_KEY`, or put a command that prints it in
  `vox.json` as `keyCommand`. Without it, punctuation and a pause decide.

## What leaves the machine

Nothing, unless you set a TypeSafe key. Speech recognition, the voice check and the sounds all run on the device, and
each message's audio is a temporary file; with `~/.claude/sounds/takes` present it is also kept there, for "only me".
Setup downloads the speech models once: Parakeet through FluidAudio on macOS, sherpa-onnx and Silero VAD on Linux.
With a key set, the text of a paused message goes to TypeSafe to judge whether you have finished. Audio is never sent.

## Develop

`tests/vox.sh`, `tests/doctor.sh`, `tests/dictionary.sh` and `tests/keyword.sh` run anywhere; `claude plugin test .` runs the mod's tests.
ARCHITECTURE.md maps the code.
A release carries the built macOS helper, so setup downloads it instead of compiling: after `swift build -c release`
in `helper/macos`, `gh release create v<version> helper/macos/.build/release/vox-helper`. Tuning values
(voice bars, guest time, send waits) are settings in `vox.default.json`, never code.

## Credits

[FluidAudio](https://github.com/FluidInference/FluidAudio) and NVIDIA's Parakeet for recognition on macOS,
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) and Silero VAD on Linux, [herdr](https://herdr.dev) for the panes,
and TypeSafe's Jev for the optional end-of-turn call. The sounds are synthesised by `sounds/make.sh`.

## Licence

MIT, © Chris Wijnia. Keep the copyright line when you reuse it.
