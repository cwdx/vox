import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

import type { VoiceLive, VoxState } from '../types'
import { banner } from './font'
import { isIdle, trackActivity } from './mascot'
import { sh } from './shell'

const stateAtom = atom({ plugin: 'vox', key: 'state' } as const, null)
const liveAtom = atom({ plugin: 'vox', key: 'live' } as const, null)
// what this Mac still lacks for vox (bin/vox-doctor), optional parts left out; empty when ready
const needsAtom = atom({ plugin: 'vox', key: 'needs' } as const, [] as string[])
const homeAtom = atom({ plugin: 'vox', key: 'home' } as const, '')
const youBannerAtom = atom({ plugin: 'vox', key: 'bigYou' } as const, '')
const claudeBannerAtom = atom({ plugin: 'vox', key: 'bigClaude' } as const, '')
// who spoke last: the letters keep their last words until the other one starts
const lastClaudeAtom = atom({ plugin: 'vox', key: 'lastClaude' } as const, false)
// counts polls while idle, so the invitation animates; nothing else redraws a quiet pane
const frameAtom = atom({ plugin: 'vox', key: 'frame' } as const, 0)

// this session's ids, set at session.start
export const me = { session: '', pane: '' }
// the left column's width as last drawn; drawing may not write state, but a plain variable is the module's own
export const view = { width: 60 }

// what another pane's view of the voice leaves out: its words and verdicts
const NO_WORDS = { text: '', sent: '', verdict: {}, judged: [], wait: 0 }
export const EMPTY_LIVE: VoiceLive = { levels: [], out: [], speaking: false, ...NO_WORDS }

// One read at a time; a failed or half-written vox.json keeps the last good state.
let reading = false
export async function readState($: EngineInterface) {
  if (reading) return read($, stateAtom)
  reading = true
  try {
    const { stdout } = await sh($, 'state', me.session)
    const state = JSON.parse(stdout) as VoxState
    await update($, stateAtom, () => state)
    return state
  } catch {
    return read($, stateAtom)
  } finally {
    reading = false
  }
}

// the helper's file as last read: an unchanged file writes no state and redraws nothing
let lastLive = ''
let lastSentence: string[] = []

async function readLive($: EngineInterface, dir: string) {
  const text = await $.fs.read(`${dir}/.claude/sounds/.voice.state`).catch(() => '')
  // the voice is shared: speech another session queued plays here too, but its words are not this pane's to show
  const speaker = (await $.fs.read(`${dir}/.claude/sounds/.voice.speaker`).catch(() => '')).trim()
  const others = !!me.pane && !!speaker && speaker !== me.pane
  if (!text || text + others === lastLive) return
  lastLive = text + others
  try {
    const heard = JSON.parse(text) as VoiceLive
    // dictation types into the focused pane alone; the other sessions' panes keep only the shared meter
    const elsewhere = !!me.pane && !!heard.pane && heard.pane !== me.pane
    const shown = elsewhere ? { ...heard, ...NO_WORDS } : heard
    await update($, liveAtom, () => (others ? { ...shown, speaking: false, spoken: undefined, out: [] } : shown))
  } catch {}
}

async function readBanners($: EngineInterface, live: VoiceLive) {
  const you = banner('you', live.text || live.sent, view.width)
  if (you !== undefined) await update($, youBannerAtom, () => you)
  // what Claude's voice has reached: the words of the sentence playing, revealed in step with the audio
  const spoken = live.spoken ?? {}
  const sentence = (spoken.text ?? '').split(/\s+/).filter(Boolean)
  const reached = spoken.seconds ? Math.ceil(Math.min(1, (spoken.elapsed ?? 0) / spoken.seconds) * sentence.length) : 0
  // the helper drops a sentence as its audio ends, often before the last poll revealed its last words
  if (sentence.length) lastSentence = sentence
  const words = sentence.length ? sentence.slice(0, reached) : lastSentence
  const claude = words.length ? banner('claude', words.join(' '), view.width) : undefined
  if (claude !== undefined) await update($, claudeBannerAtom, () => claude)
  if (live.speaking) await update($, lastClaudeAtom, () => true)
  else if (live.text) await update($, lastClaudeAtom, () => false)
}

// What this pane's prompt box holds, for the helper: it never types into, or sends, words the user typed themselves.
let lastComposer = ''
async function shareComposer($: EngineInterface, dir: string) {
  if (!me.pane) return
  const { text } = await $.prompt.read()
  if (text === lastComposer) return
  lastComposer = text
  await $.fs.write(`${dir}/.claude/sounds/.voice.composer`, JSON.stringify({ pane: me.pane, text }))
}

export async function pollVoice($: EngineInterface) {
  const dir = await read($, homeAtom)
  if (!dir) return
  await shareComposer($, dir).catch(() => undefined)
  await readLive($, dir)
  const live = await read($, liveAtom)
  const thinking = !!(await read($, stateAtom))?.thinking
  trackActivity(live, thinking)
  if (isIdle() || thinking) await update($, frameAtom, n => n + 1)
  if (live) await readBanners($, live)
}
