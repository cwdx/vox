import { atom, read } from 'claude-code'
import type { EngineInterface } from 'claude-code'

import type { VoxState } from '../types'
import { sh } from './shell'
import { readState } from './state'

const stateRef = atom({ plugin: 'vox', key: 'state' } as const, null)

// switch name → vox.json key ("ear" is the listening helper)
export const SWITCHES = { voice: 'enabled', steps: 'narrate', think: 'think', fx: 'fx', stream: 'stream', ear: 'listening', auto: 'autoListen' } as const
export type Switch = keyof typeof SWITCHES

export const isOn = (state: VoxState, name: Switch) => state[SWITCHES[name]] !== false

// the final-pass recognizers, in the order a press cycles through them
export const MODELS = ['parakeet', 'ultra', 'whisper', 'apple'] as const

export async function flip($: EngineInterface, name: Switch) {
  const state = (await read($, stateRef)) ?? (await readState($))
  if (!state) return `${name}: vox has no state yet`
  const next = !isOn(state, name)
  await (name === 'ear' ? sh($, 'listen', next ? 'on' : 'off') : sh($, 'set', SWITCHES[name], String(next)))
  const after = await readState($)
  return after && isOn(after, name) === next ? `${name} ${next ? 'on' : 'off'}` : `${name} did not change`
}

// the dot both views use for a switch, so they read alike
export const drawDot = (Text: ReturnType<EngineInterface['ui']['resolve']>['Text'], on: boolean) => (
  <Text color={on ? 'green' : 'gray'}>{on ? '●' : '○'}</Text>
)
