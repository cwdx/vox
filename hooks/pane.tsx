import { atom, read } from 'claude-code'
import type { Args, EngineInterface } from 'claude-code'

import { fit } from './font'
import { drawInvite, drawWalk, isIdle, mood } from './mascot'
import { GRADIENT, eqBars, eqRow, meter, pColor, pOf } from './meter'
import { sh, toggleExpanded } from './shell'
import { EMPTY_LIVE, readState, view } from './state'
import { MODELS, drawDot, flip, isOn } from './switches'

const stateRef = atom({ plugin: 'vox', key: 'state' } as const, null)
const frameRef = atom({ plugin: 'vox', key: 'frame' } as const, 0)
const liveRef = atom({ plugin: 'vox', key: 'live' } as const, null)
const lastClaudeRef = atom({ plugin: 'vox', key: 'lastClaude' } as const, false)
const bigYouRef = atom({ plugin: 'vox', key: 'bigYou' } as const, '')
const bigClaudeRef = atom({ plugin: 'vox', key: 'bigClaude' } as const, '')

type Input = Extract<Args<'ui.render'>, { component: 'AbovePrompt' }>

const SIDE = 36

// one switch in the grid: its name, whether it is on, what pressing it does, and a short note
const toggle = (name: string, on: boolean, press: () => unknown) => ({ name, on, press })

export async function drawPane($: EngineInterface, e: Input) {
  const { Box, Button, Text } = $.ui.resolve(e)
  try {
    const state = await read($, stateRef)
    if (!state) return <Text>vox is starting…</Text>
    await read($, frameRef)
    // with the ear off the helper's last file is stale: show the switches over a quiet, empty pane
    const heard = await read($, liveRef)
    const live = state.listening && heard ? heard : EMPTY_LIVE
    const left = Math.max(20, (e.viewport?.columns ?? 80) - SIDE - 4)
    view.width = left
    const rows = 2
    const isClaude = live.speaking
    const showsClaude = live.speaking || (!live.text && (await read($, lastClaudeRef)))
    const words = JSON.parse((showsClaude ? await read($, bigClaudeRef) : await read($, bigYouRef)) || '[]') as string[][]
    const bars = eqBars(isClaude ? live.out ?? live.levels : live.levels, left)
    const p = pOf(live)
    const check = live.me?.last
    // the gap after a switch sits outside its button, so hovering lights the name and dot only
    const drawToggle = (t: ReturnType<typeof toggle>) => (
      <Box key={`p-${t.name}`}>
        <Button key={`t-${t.name}`} plain onPress={() => void t.press()}>
          <Text color="gray">{t.name.padEnd(8)}</Text>
          {drawDot(Text, t.on)}
        </Button>
        <Text>{'  '}</Text>
      </Box>
    )
    const calls = live.judged ?? []
    const look = mood(state, live)
    const drawLines = (lines: string[], key: string, props: { color: string; bold?: boolean }) =>
      lines.map((text, i) => <Text key={`${key}${i}`} {...props} wrap="truncate-end">{text || ' '}</Text>)
    const walk = state.thinking && !live.text && !live.speaking ? drawWalk(left) : undefined
    return (
      <Box paddingX={1}>
        <Box flexDirection="column" width={left} flexShrink={0}>
          {Array.from({ length: rows }, (_, row) => (
            <Text key={`row${row}`} color={GRADIENT[isClaude ? 'claude' : 'user'][rows - 1 - row]} wrap="truncate-end">
              {eqRow(bars, rows, row)}
            </Text>
          ))}
          <Text> </Text>
          {/* five rows are always held, so the pane keeps its height before anyone speaks */}
          {walk
            ? drawLines(walk.rows, 'work', { color: walk.tint })
            : state.listening && isIdle() && !live.text && !live.speaking
            ? drawLines(drawInvite(left), 'idle', { color: 'gray' })
            : drawLines(fit(words, left) ?? ['', '', '', '', ''], 'lk', { bold: true, color: showsClaude ? 'magentaBright' : 'cyanBright' })}
        </Box>
        <Box flexDirection="column" width={SIDE} marginLeft={2} flexShrink={0}>
          <Button key="fox" plain onPress={() => void toggleExpanded($)}>
            <Text color={look.color} bold>{`${look.face} ${look.label}`}</Text>
            <Text color="gray">{'  ⤡'}</Text>
          </Button>
          {/* three switches a row, each a fixed 11 cells (name, dot, gap); a switch with a reading shares its row */}
          {[
            [toggle('mic', state.listening && !live.paused, () => flip($, 'ear')), toggle('voice', state.enabled, () => flip($, 'voice')), toggle('live', isOn(state, 'stream'), () => flip($, 'stream'))],
            [toggle('steps', isOn(state, 'steps'), () => flip($, 'steps')), toggle('music', isOn(state, 'think'), () => flip($, 'think')), toggle('sounds', isOn(state, 'fx'), () => flip($, 'fx'))],
            [toggle('auto', isOn(state, 'auto'), () => flip($, 'auto'))],
          ].map((row, i) => <Box key={`sw${i}`}>{row.map(t => drawToggle(t))}</Box>)}
          {live.me?.enrolled && (
            <Box>
              {drawToggle(toggle('only me', live.me.on, () => sh($, 'set', 'onlyMe', String(!live.me!.on))))}
              {live.me.on && check?.p !== undefined && (
                <Text color={check.ok ? 'green' : 'gray'} wrap="truncate-end">{`${meter(check.p)} ${check.p.toFixed(2)} ${check.ok ? 'you' : 'not you'}`}</Text>
              )}
            </Box>
          )}
          {live.jev?.configured && (
            <Box>
              {drawToggle(toggle('jev', live.jev.on, () => sh($, 'set', 'jev', String(!live.jev!.on))))}
              {live.jev.on && p !== undefined && (
                <Text color={pColor(p)} wrap="truncate-end">{`${meter(p)} ${p.toFixed(2)}${calls.length ? ` · ${calls.length}×${Math.round(calls.reduce((sum, call) => sum + call.ms, 0) / calls.length)}ms` : ''}`}</Text>
              )}
            </Box>
          )}
          <Box>
            {drawToggle(toggle('skill', state.skillNudge !== false, () => sh($, 'set', 'skillNudge', String(state.skillNudge === false))))}
            <Button key="p-asr" plain onPress={() => void sh($, 'set', 'asr', MODELS[(MODELS.indexOf(state.asr ?? 'parakeet') + 1) % MODELS.length]!).then(() => readState($))}>
              <Text>{state.asr ?? 'parakeet'}</Text>
              <Text color="gray"> ▸</Text>
            </Button>
            <Text>{' '.repeat(Math.max(1, SIDE - 19 - (state.asr ?? 'parakeet').length))}</Text>
            <Button key="p-test" plain onPress={() => void sh($, 'demo')}>
              <Text color="gray">test </Text>
              <Text>▶</Text>
            </Button>
          </Box>
        </Box>
      </Box>
    )
  } catch (error) {
    return <Text color="red">vox could not draw: {String(error).slice(0, 160)}</Text>
  }
}
