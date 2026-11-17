import { atom, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

const needsRef = atom({ plugin: 'vox', key: 'needs' } as const, [] as string[])
const expandedRef = atom({ plugin: 'vox', key: 'expanded' } as const, false)

// the vox script with its arguments as argv: nothing the user types is parsed by a shell
export function sh($: EngineInterface, ...args: string[]) {
  return $.process.run(['/bin/bash', '-c', '"$HOME/.claude/hooks/vox" "$@"', 'vox', ...args], { timeoutMs: 10_000 })
}

// the full view replaces the one-line band above the prompt, so it always sits there, never in a side pane
export function toggleExpanded($: EngineInterface) {
  return update($, expandedRef, open => !open)
}

export async function checkSetup($: EngineInterface) {
  const { stdout } = await $.process.run([`${$.plugin.root}/bin/vox-doctor`])
  const missing = stdout.split('\n').filter(line => line && !line.includes('(optional)')).map(line => line.split('\t')[0]!)
  await update($, needsRef, () => [...new Set(missing)])
  return stdout.trim()
}

// install.sh can outlast a command's budget (the helper builds for minutes), so it streams in the background
export async function setup($: EngineInterface, flags: string[]) {
  let last = ''
  const run = $.process.spawn({ argv: ['/bin/bash', `${$.plugin.root}/install.sh`, ...flags] })
  let piece = await run.next()
  for (; !piece.done; piece = await run.next()) {
    last = piece.value.text.trim().split('\n').at(-1) || last
    $.ui.status(`vox setup: ${last.slice(0, 80)}`)
  }
  const code = piece.value.code
  $.ui.status(undefined)
  const left = await checkSetup($)
  $.ui.toast(code === 0 ? (left ? `vox set up, except: ${left.replace(/\t/g, ' ')}` : 'vox is set up. Restart Claude Code.') : `vox setup stopped: ${last}`, { timeoutMs: 15_000 })
}
