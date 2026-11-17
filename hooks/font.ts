// A 3×5 pixel font, one cell a pixel: thin strokes, four cells a letter.
const FONT: Record<string, string[]> = {
  "A": ['010', '101', '111', '101', '101'],
  "B": ['110', '101', '110', '101', '110'],
  "C": ['011', '100', '100', '100', '011'],
  "D": ['110', '101', '101', '101', '110'],
  "E": ['111', '100', '110', '100', '111'],
  "F": ['111', '100', '110', '100', '100'],
  "G": ['011', '100', '101', '101', '011'],
  "H": ['101', '101', '111', '101', '101'],
  "I": ['111', '010', '010', '010', '111'],
  "J": ['001', '001', '001', '101', '010'],
  "K": ['101', '101', '110', '101', '101'],
  "L": ['100', '100', '100', '100', '111'],
  "M": ['10001', '11011', '10101', '10001', '10001'],
  "N": ['1001', '1101', '1011', '1001', '1001'],
  "O": ['010', '101', '101', '101', '010'],
  "P": ['110', '101', '110', '100', '100'],
  "Q": ['010', '101', '101', '110', '011'],
  "R": ['110', '101', '110', '101', '101'],
  "S": ['011', '100', '010', '001', '110'],
  "T": ['111', '010', '010', '010', '010'],
  "U": ['101', '101', '101', '101', '111'],
  "V": ['101', '101', '101', '101', '010'],
  "W": ['10001', '10001', '10101', '11011', '10001'],
  "X": ['101', '101', '010', '101', '101'],
  "Y": ['101', '101', '010', '010', '010'],
  "Z": ['111', '001', '010', '100', '111'],
  "0": ['111', '101', '101', '101', '111'],
  "1": ['010', '110', '010', '010', '111'],
  "2": ['110', '001', '010', '100', '111'],
  "3": ['110', '001', '010', '001', '110'],
  "4": ['101', '101', '111', '001', '001'],
  "5": ['111', '100', '110', '001', '110'],
  "6": ['011', '100', '111', '101', '111'],
  "7": ['111', '001', '010', '010', '010'],
  "8": ['111', '101', '111', '101', '111'],
  "9": ['111', '101', '111', '001', '110'],
  ".": ['0', '0', '0', '0', '1'],
  ",": ['0', '0', '0', '1', '1'],
  "!": ['1', '1', '1', '0', '1'],
  "?": ['110', '001', '010', '000', '010'],
  "'": ['1', '1', '0', '0', '0'],
  "-": ['000', '000', '111', '000', '000'],
  ":": ['0', '1', '0', '1', '0'],
  "$": ['011', '110', '010', '011', '110'],
  "%": ['101', '001', '010', '100', '101'],
  "/": ['001', '001', '010', '100', '100'],
  "_": ['000', '000', '000', '000', '111'],
}

function letter(char: string) {
  const bits = FONT[char.toUpperCase()] ?? ['000', '000', '000', '000', '000']
  return bits.map(row => [...row].map(bit => (bit === '1' ? '█' : ' ')).join(''))
}

// A word's glyph, letters one cell apart; too wide for the line, it keeps its last letters whole.
export function glyph(word: string, width: number) {
  const kept: string[][] = []
  let used = 0
  for (const g of [...word].map(letter).reverse()) {
    const size = (g[0]?.length ?? 0) + 1
    if (kept.length && used + size > width) break
    kept.unshift(g)
    used += size
  }
  return Array.from({ length: 5 }, (_, row) => kept.map(g => g.at(row) ?? '').join(' '))
}

const wordWidth = (word: string[]) => Math.max(0, ...word.map(line => line.length))

// Lays a page of word glyphs side by side, two cells apart.
export function fit(words: string[][], width: number) {
  if (!words.length) return undefined
  const height = Math.max(0, ...words.map(word => word.length))
  return Array.from({ length: height }, (_, row) =>
    words.map(word => (word[row] ?? '').padEnd(wordWidth(word))).join('  ').slice(0, width),
  )
}

// The last words as solid block letters (a 3×5 pixel font, each pixel a █): readable at a glance.
const lastBanner = new Map<string, string>()
// Where each speaker's current page starts in their word list: words stay put until the page is full.
const pageStart = new Map<string, { text: string; start: number }>()

// The page of glyphs as JSON, or undefined when it is the one already drawn.
export function banner(who: string, text: string, width: number) {
  const words = text.split(/\s+/).filter(Boolean)
  const page = pageStart.get(who)
  // a new message, or one that shrank, starts on a fresh page
  let start = page && text.startsWith(page.text.split(/\s+/).slice(0, page.start).join(' ')) && page.start < words.length ? page.start : 0
  let shown = words.slice(start).map(word => glyph(word, width))
  if (shown.reduce((sum, word) => sum + wordWidth(word) + 2, 0) > width + 2) {
    start = words.length - 1
    shown = shown.slice(-1)
  }
  pageStart.set(who, { text, start })
  const key = `${width}:${start}:${words.slice(start).join(' ')}`
  if (lastBanner.get(who) === key) return undefined
  lastBanner.set(who, key)
  return JSON.stringify(shown)
}
