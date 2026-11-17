import { atom, update } from 'claude-code'
import type { Register } from 'claude-code'

import { addMode, drawBand } from './band'
import { checkSetup, setup, sh, toggleExpanded } from './shell'
import { me, pollVoice, readState } from './state'
import { MODELS, SWITCHES, flip, isOn } from './switches'
import type { Switch } from './switches'

const homeRef = atom({ plugin: 'vox', key: 'home' } as const, '')

// A nudge beside the prompt, never shown to the user: when voice comes on, and every 25 prompts while it stays on,
// Claude is told to load the vox-voice skill, so it knows the setup it speaks through. `skillNudge: false` turns it off.
const NUDGE_EVERY = 25
const NUDGE = 'vox is on: the user hears replies read aloud and dictates by voice. If the vox-voice skill\'s instructions are not in your context (never loaded, or lost to compaction), load Skill(vox-voice) before replying; if they are, ignore this.'
let promptsSinceNudge = NUDGE_EVERY
let wasVoiceOn = false

// The shell scripts and the voice helper do the work; this mod shows their state and flips their switches.
export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'vox',
      description: 'Voice and sounds: /vox, /vox <voice|steps|think|fx|stream|ear>, /vox asr <parakeet|ultra|whisper|apple>, /vox <kind> <sound>, /vox full, /vox demo, /vox setup [dictation], /vox doctor',
    })
    const [dir = '', pane = ''] = (await $.process.run(['/bin/sh', '-c', 'printf "%s\n%s" "$HOME" "$HERDR_PANE_ID"'])).stdout.split('\n')
    await update($, homeRef, () => dir)
    me.pane = pane
    me.session = await $.session.id()
    void checkSetup($)
    $.ui.status(undefined)
    $.clock.every(1500, () => void readState($))
    $.clock.every(150, () => void pollVoice($))
    return next(e)
  })

  on('command.run', { command: 'vox' }, async ($, e) => {
    const [first = '', second] = e.args.trim().split(/\s+/)
    // `/vox think think-orb` picks a sound; `/vox think` alone flips the switch
    if (!second && Object.hasOwn(SWITCHES, first)) return { text: await flip($, first as Switch) }
    if (first === 'setup') {
      void setup($, second === 'dictation' ? ['--dictation'] : [])
      return { text: 'Setting up vox; progress shows in the status line.' }
    }
    if (first === 'doctor') return { text: (await checkSetup($)) || 'vox has everything it needs.' }
    if (first === 'full' || first === 'pane') {
      await toggleExpanded($)
      return { text: 'vox view toggled.' }
    }
    if (first === 'asr' && second) {
      if (!(MODELS as readonly string[]).includes(second)) return { text: `Models: ${MODELS.join(', ')}` }
      await sh($, 'set', 'asr', second)
      await readState($)
      return { text: `final pass: ${second}` }
    }
    if (first === 'demo') {
      void (second ? sh($, 'demo', second) : sh($, 'demo'))
      return { text: 'Playing the sounds.' }
    }
    if (first && second) {
      const { exitCode, stdout } = await sh($, 'use', first, second)
      return { text: exitCode === 0 ? `${first}: ${second}` : `No such sound. Sounds: ${stdout.trim().split('\n').join(', ')}` }
    }
    const state = await readState($)
    if (!state) return { text: 'vox has no state yet: is ~/.claude/hooks/vox there?' }
    const switches = (Object.keys(SWITCHES) as Switch[]).map(n => `${n} ${isOn(state, n) ? 'on' : 'off'}`).join(' · ')
    const sounds = Object.entries(state.sounds).map(([k, v]) => `${k} ${v.replace(`${k}-`, '')}`).join(' · ')
    return { text: `${switches}\n${sounds}` }
  })

  on('prompt.submit', async ($, e, next) => {
    const state = await readState($)
    const isVoiceOn = !!state?.enabled && state.skillNudge !== false
    if (isVoiceOn && !wasVoiceOn) promptsSinceNudge = NUDGE_EVERY
    wasVoiceOn = isVoiceOn
    if (!isVoiceOn || ++promptsSinceNudge < NUDGE_EVERY) return next(e)
    promptsSinceNudge = 0
    return next({ ...e, context: [...(e.context ?? []), NUDGE] })
  })

  on('ui.render', { component: 'AbovePrompt' }, drawBand)
  on('ui.render', { component: 'SessionMode' }, addMode)
}
