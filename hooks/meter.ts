import type { VoiceLive } from '../types'

export const BARS = '▁▂▃▄▅▆▇█'

// two tones each: the user cyan with yellow peaks, Claude magenta with blue peaks
export const GRADIENT = {
  user: ['#06b6d4', '#fde047'],
  claude: ['#d946ef', '#60a5fa'],
}

// 0 to 1 for an RMS level: -60 dB is a silent room, -10 dB a raised voice
export const level = (rms: number) => Math.min(1, Math.max(0, (20 * Math.log10(Math.max(rms, 1e-6)) + 60) / 50))
export const heights = (levels: number[]) => levels.map(rms => Math.round(level(rms) * (BARS.length - 1)))

export const barColor = (height: number, isClaude: boolean) =>
  isClaude ? (height <= 4 ? 'magenta' : 'blue') : height <= 4 ? 'cyan' : 'yellow'

// One row of a tall equalizer, as runs of one colour: the top of each column in eighths, then solid below.
// After cava: bars two cells wide with a one-cell gap, monstercat smoothing so neighbours fall off in a
// slope, and a vertical gradient, the base tone at the bottom and the peak tone at the top.
export function eqBars(levels: number[], columns: number) {
  const count = Math.max(4, Math.floor((columns - 2) / 3))
  // one sample window more than shown: the oldest bar straddles the history's start and reads too tall
  const per = Math.max(1, Math.floor(levels.length / (count + 1)))
  const values = Array.from({ length: count }, (_, i) => {
    const slice = levels.slice(levels.length - (count - i) * per, levels.length - (count - i - 1) * per)
    return level(slice.reduce((a, b) => Math.max(a, b), 0))
  })
  // monstercat: each bar is at least a neighbour's height times 0.7 per step away
  for (let i = 1; i < count; i++) values[i] = Math.max(values[i]!, values[i - 1]! * 0.7)
  for (let i = count - 2; i >= 0; i--) values[i] = Math.max(values[i]!, values[i + 1]! * 0.7)
  return values
}

export function eqRow(values: number[], rows: number, row: number) {
  return values
    .map(value => {
      const filled = Math.round(value * rows * 8) - (rows - 1 - row) * 8
      const char = filled >= 8 ? '█' : filled <= 0 ? ' ' : BARS[filled - 1]!
      return char + char
    })
    .join(' ')
}

// a thin bar in eighths of a cell: five cells carry 40 steps, so it stays short and still reads finely
const EIGHTHS = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉']
export const meter = (p: number, size = 5) => {
  const steps = Math.round(Math.min(1, Math.max(0, p)) * size * 8)
  return ('█'.repeat(Math.floor(steps / 8)) + EIGHTHS[steps % 8]).padEnd(size, '·')
}

// Jev's verdict on the words now, or on the last message once it is sent
export const pOf = (live: VoiceLive) => (live.verdict.text === live.text || !live.text ? live.verdict.p : undefined)
// done is green, more coming is magenta, unsure is yellow; one place for the thresholds the helper also uses
export const pColor = (p: number | undefined) => (p === undefined || p < 0 ? 'gray' : p >= 0.7 ? 'green' : p <= 0.3 ? 'magenta' : 'yellow')
export const pWord = (p: number) => (p >= 0.7 ? 'done' : p <= 0.3 ? 'more coming' : 'unsure')

export function verdictOf(live: VoiceLive) {
  if (live.text) {
    const p = pOf(live)
    const judged = p === undefined ? 'listening' : `jev ${p.toFixed(2)} ${pWord(p)}`
    return `${judged} · sends in ${live.wait.toFixed(1)}s`
  }
  if (live.sent) return `sent${live.verdict.p === undefined ? '' : ` · jev ${live.verdict.p.toFixed(2)}`}`
  return ''
}
