import { atom, read } from 'claude-code'
import type { Args, EngineInterface, Next } from 'claude-code'

import { dots, invite, isIdle, mood } from './mascot'
import { BARS, barColor, heights, pColor, pOf, verdictOf } from './meter'
import { drawPane } from './pane'
import { toggleExpanded } from './shell'
import { drawDot, flip } from './switches'

const needsRef = atom({ plugin: 'vox', key: 'needs' } as const, [] as string[])
const stateRef = atom({ plugin: 'vox', key: 'state' } as const, null)
const liveRef = atom({ plugin: 'vox', key: 'live' } as const, null)
const frameRef = atom({ plugin: 'vox', key: 'frame' } as const, 0)
const expandedRef = atom({ plugin: 'vox', key: 'expanded' } as const, false)

type Input = Extract<Args<'ui.render'>, { component: 'AbovePrompt' }>

const clip = (text: string, size: number) => (text.length > size ? `…${text.slice(-size)}` : text)

// One line holds it all: mascot, ear and voice switches, the mic as an equalizer, the words so far, Jev's call, and '⤢' for the rest.
export async function drawBand($: EngineInterface, e: Input, next: Next<'ui.render', Input>) {
  const missing = await read($, needsRef)
  if (missing.length && !e.props.hasSurvey) {
    const { Text } = $.ui.resolve(e)
    return <Text color="yellow" wrap="truncate-end">{`vox needs setup (${missing.join(', ')}): /vox setup`}</Text>
  }
  const state = await read($, stateRef)
  if (e.props.hasSurvey || !state) return next(e)
  const live = await read($, liveRef)
  await read($, frameRef)
  if (await read($, expandedRef)) return drawPane($, e)
  const { Box, Button, Text } = $.ui.resolve(e)
  const look = mood(state, live)
  return (
    <Box justifyContent="space-between">
      <Box flexShrink={0}>
        <Button key="fox" plain onPress={() => void toggleExpanded($)}>
          <Text color={look.color}>{`${look.face} ${look.label}`}</Text>
        </Button>
        <Text>{' '.repeat(13 - look.label.length)}</Text>
        {/* name then dot, as in the full view */}
        <Button key="ear" plain onPress={() => void flip($, 'ear')}>
          <Text color="gray">mic </Text>
          {drawDot(Text, state.listening)}
        </Button>
        <Text>{'  '}</Text>
        <Button key="voice" plain onPress={() => void flip($, 'voice')}>
          <Text color="gray">voice </Text>
          {drawDot(Text, state.enabled)}
        </Button>
        <Text>{'  '}</Text>
        {state.listening && live && heights((live.speaking ? live.out ?? live.levels : live.levels).slice(-10)).map((height, i) => (
          <Text key={`bar${i}`} color={barColor(height, live.speaking)}>{BARS[height]}</Text>
        ))}
      </Box>
      <Box flexGrow={1} flexShrink={1} marginX={1}>
        <Text color={live?.text ? 'white' : 'gray'} wrap="truncate-end">
          {live?.text ? `“${clip(live.text, 60)}”` : state.listening && isIdle() ? `${invite().toLowerCase()}${dots()}` : ''}
        </Text>
      </Box>
      <Box flexShrink={0}>
        {state.listening && live?.text && <Text color={pColor(pOf(live))}>{verdictOf(live)} </Text>}
        <Button key="open" plain label="⤢" onPress={() => void toggleExpanded($)} />
      </Box>
    </Box>
  )
}

// The footer's mode labels, like "auto mode on": how the mic listens, so it shows even with the band scrolled away.
export async function addMode($: EngineInterface, e: Extract<Args<'ui.render'>, { component: 'SessionMode' }>, next: Next<'ui.render', Extract<Args<'ui.render'>, { component: 'SessionMode' }>>) {
  const state = await read($, stateRef)
  if (!state?.listening) return next(e)
  const mode = state.autoListen === false ? `say "${state.keywords?.[0] ?? 'vox'}"` : 'auto listen'
  return next({ ...e, props: { ...e.props, modes: [...e.props.modes, mode] } })
}
