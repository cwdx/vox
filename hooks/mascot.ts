import type { VoiceLive, VoxState } from '../types'
import { fit, glyph } from './font'

// when either side last spoke; after a quiet spell both views show an invitation to talk
let lastActive = Date.now()
const IDLE_MS = 15_000
const INVITES = ['JUST TALK', 'SAY HI', "I'M ALL EARS", 'GO AHEAD', 'TALK TO ME']
export const isIdle = () => Date.now() - lastActive > IDLE_MS
// the invitation changes every ten seconds, so a quiet pane still feels alive
export const invite = () => INVITES[Math.floor(Date.now() / 10_000) % INVITES.length]!
// typed out a letter at a time, then a cursor that blinks until the next one
const typed = () => {
  const text = invite()
  const shown = Math.min(text.length, Math.floor((Date.now() % 10_000) / 110))
  const cursor = shown < text.length || Math.floor(Date.now() / 500) % 2 ? '_' : ''
  return text.slice(0, shown) + cursor
}
// The invitation in block letters when the whole of it fits the column (a phone's narrow pane cuts letters
// apart), else as plain text on the middle row; always five rows, so the pane keeps its height.
export function drawInvite(width: number) {
  const size = invite().split(' ').map(word => glyph(word, width)).reduce((sum, word) => sum + (word[0]?.length ?? 0) + 2, 0)
  if (size <= width) return fit(typed().split(' ').filter(Boolean).map(word => glyph(word, width)), width) ?? ['', '', '', '', '']
  return ['', '', `✨ ${typed().toLowerCase()}`, '', '']
}

// While Claude works, a little pixel creature walks across the pane. Each turn picks its own creature, colour,
// speed and direction, and it stops now and then to look around, so no two turns look the same.
// Sprites face right, five rows by two frames; '#' is a filled pixel.
const CREATURES: { rows: [string[], string[]]; pace: number; tint?: string; front?: string[] }[] = [
  { pace: 1, rows: [['.......#.#', '#......###', '.########.', '.########.', '.#.#..#.#.'], ['.......#.#', '#......###', '.########.', '.########.', '..#.#..#.#']] }, // cat
  { pace: 1, rows: [['........##.', '#.......###', '#########..', '.#######...', '.#.#..#.#..'], ['........##.', '#.......###', '#########..', '.#######...', '..#.#..#.#.']] }, // dog
  { pace: 2, rows: [['..###..', '.#.#.#.', '.#####.', '#.###.#', '.#...#.'], ['..###..', '.#.#.#.', '.#####.', '#.###.#', '..#.#..']] }, // robot
  { pace: 4, rows: [['...####...', '..#....#..', '..#.##.#.#', '..#....#.#', '##########'], ['...####...', '..#....#..', '..#.##.##.', '..#....#.#', '##########']] }, // snail
  { pace: 1, rows: [['#.....#', '.#...#.', '..###..', '...#...', '.......'], ['.......', '.......', '##.#.##', '..###..', '...#...']] }, // bird
  { pace: 2, rows: [['#.......#', '.#.....#.', '..#####..', '.#######.', '#.#...#.#'], ['#.......#', '.#.....#.', '..#####..', '.#######.', '.#.#.#.#.']] }, // crab
  { pace: 1, tint: '#d9772b', rows: [['.........#.#.', '##.......####', '###########..', '..#######....', '..#.#..#.#...'], ['.........#.#.', '##.......####', '###########..', '..#######....', '...#.#..#.#..']], front: ['.##.......##.', '.###########.', '..##.###.##..', '...#######...', '.....###.....'] }, // fox, always fox-orange; it faces you when it stops
]
const TINTS = ['#7c6fae', '#5fa8a0', '#c08457', '#8fa65a', '#b46f9a', '#6f8fc8']

let workSeed = 0
let wasThinking = false
let lastWorked = 0

// Called from the poll: Claude at work counts as activity too, since the invitation is only for a quiet, idle desk.
export function trackActivity(live: VoiceLive | null, thinking: boolean) {
  if (live && (live.text || live.speaking)) lastActive = Date.now()
  if (thinking) lastActive = Date.now()
  // a new creature only for a new turn: the thinking flag blinks between steps, and each blink would pick another
  if (thinking && !wasThinking && Date.now() - lastWorked > 15_000) workSeed = Date.now()
  if (thinking) lastWorked = Date.now()
  wasThinking = thinking
}

// a small seeded random number: the same turn always draws the same way
const rand = (n: number) => {
  const x = Math.sin(workSeed * 12.9898 + n * 78.233) * 43758.5453
  return x - Math.floor(x)
}

export function drawWalk(width: number) {
  // the fox is vox's own, so it walks about a third of the turns; the others share the rest
  const creature = rand(1) < 1 / 3 ? CREATURES.at(-1)! : CREATURES[Math.floor(rand(5) * (CREATURES.length - 1))]!
  const tint = creature.tint ?? TINTS[Math.floor(rand(2) * TINTS.length)]!
  const leftward = rand(3) < 0.5
  const step = 70 + Math.floor(rand(4) * 70) * creature.pace
  const ticks = Math.floor((Date.now() - workSeed) / step)
  // every so often it stops for a moment: a pause of a few ticks in each stretch of forty
  const stretch = Math.floor(ticks / 40)
  const pauseOf = (k: number) => (rand(10 + k) < 0.5 ? 6 : 0)
  const pause = pauseOf(stretch)
  // each earlier stretch adds its own steps; summing with this stretch's pause made the creature jump
  let moved = Math.min(ticks % 40, 40 - pause)
  for (let k = 0; k < stretch; k++) moved += 40 - pauseOf(k)
  // it paces back and forth inside the column, turning at each end, so it is never cut off at an edge
  // two cells short of the edge: a row that touches the column's last cell can still wrap in some terminals
  const room = Math.max(1, width - 2 - creature.rows[0][0]!.length)
  const lap = Math.floor((moved + (leftward ? room : 0)) / room)
  const goingLeft = lap % 2 === 1
  const x = goingLeft ? room - ((moved + (leftward ? room : 0)) % room) : (moved + (leftward ? room : 0)) % room
  const still = ticks % 40 >= 40 - pause
  const pose = still && creature.front ? creature.front : creature.rows[still ? 0 : moved % 2]!.map(row => (goingLeft ? [...row].reverse().join('') : row))
  // every row filled to the full width, so the terminal never keeps a stale pixel from the last frame
  const rows = pose.map(row => (' '.repeat(x) + row.replaceAll('#', '█').replaceAll('.', ' ')).padEnd(width - 1).slice(0, width - 1))
  return { rows, tint }
}

// The mascot, a fox's face whose ears (^ ^) stay put while its eyes and mouth tell the one state everything shows.
const blink = (a: string, b: string, ms = 500) => (Math.floor(Date.now() / ms) % 2 ? a : b)
export function mood(state: VoxState, live?: VoiceLive | null) {
  if (!state.enabled && !state.listening) return { face: '^-ᴗ-^', label: 'off', color: 'gray' }
  if (live?.speaking) return { face: blink('^•o•^', '^•ᴗ•^', 180), label: 'talking', color: 'magentaBright' }
  // another voice was heard and not typed: a few seconds of a sideways look, then back to listening
  const check = live?.me?.last
  if (check?.ok === false && Date.now() / 1000 - (check.at ?? 0) < 4) return { face: '^¬_¬^', label: 'not you', color: 'gray' }
  if (live?.text) return { face: '^°ᴗ°^', label: 'hearing you', color: 'cyanBright' }
  if (live?.paused) return { face: '^-_-^', label: 'paused', color: 'yellow' }
  if (state.thinking) return { face: blink('^•_•^', '^¬_¬^', 700), label: 'working', color: 'yellow' }
  if (state.listening && state.autoListen === false) return { face: '^-ᴗ-^', label: `say ${state.keywords?.[0] ?? 'vox'}`.slice(0, 13), color: 'cyan' }
  if (state.listening) return { face: blink('^•ᴗ•^', '^-ᴗ-^', 3000), label: 'listening', color: 'cyan' }
  return { face: '^•ᴗ•^', label: 'ready', color: 'white' }
}

export const dots = () => '·'.repeat(1 + (Math.floor(Date.now() / 400) % 3)).padEnd(3)
