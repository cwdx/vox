import { describe, expect, test } from 'claude-code/testing'

import type { VoxState } from '../types'
import { banner, fit, glyph } from '../hooks/font'
import { mood } from '../hooks/mascot'
import { pColor, pWord } from '../hooks/meter'

const base: VoxState = { enabled: true, narrate: true, think: true, stream: true, listening: false, speaking: false, thinking: false, sounds: {} }
const live = { levels: [], out: [], text: '', sent: '', verdict: {}, wait: 0, speaking: false }

describe('mood', () => {
  test('one state shows at a time', async () => {
    expect(mood({ ...base, enabled: false }).label).toBe('off')
    expect(mood(base).label).toBe('ready')
    expect(mood({ ...base, listening: true }).label).toBe('listening')
    expect(mood({ ...base, thinking: true }).label).toBe('working')
    expect(mood(base, { ...live, text: 'hi' }).label).toBe('hearing you')
    expect(mood(base, { ...live, speaking: true }).label).toBe('talking')
  })

  test('another voice shows briefly, then listening returns', async () => {
    const me = (at: number) => ({ enrolled: true, on: true, last: { p: 0.2, ok: false, at } })
    expect(mood({ ...base, listening: true }, { ...live, me: me(Date.now() / 1000) }).label).toBe('not you')
    expect(mood({ ...base, listening: true }, { ...live, me: me(Date.now() / 1000 - 10) }).label).toBe('listening')
  })
})

describe('font', () => {
  test('a glyph keeps whole letters inside the width', async () => {
    expect(glyph('HELLO', 100)[0]!.length).toBe(19)
    const narrow = glyph('HELLO', 10)
    expect(narrow).toHaveLength(5)
    expect(narrow[0]!.length).toBeLessThanOrEqual(10)
  })

  test('fit cuts every row to the width', async () => {
    const rows = fit(['HI', 'THERE'].map(word => glyph(word, 40)), 12)!
    expect(rows).toHaveLength(5)
    for (const row of rows) expect(row.length).toBeLessThanOrEqual(12)
    expect(fit([], 12)).toBeUndefined()
  })

  test('a banner draws once until the words change', async () => {
    expect(banner('test', 'hello there', 40)).toBeDefined()
    expect(banner('test', 'hello there', 40)).toBeUndefined()
    expect(banner('test', 'hello there you', 40)).toBeDefined()
  })
})

describe('verdict', () => {
  test('thresholds', async () => {
    expect(pWord(0.9)).toBe('done')
    expect(pWord(0.1)).toBe('more coming')
    expect(pColor(0.5)).toBe('yellow')
    expect(pColor(undefined)).toBe('gray')
  })
})
