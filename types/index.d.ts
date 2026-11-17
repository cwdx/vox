export type VoxState = {
  /** the final-pass recognizer: parakeet (v2, default), ultra, whisper, or apple (none) */
  asr?: 'parakeet' | 'ultra' | 'whisper' | 'apple'
  asrState?: { model?: string; status: string; error?: string }
  enabled: boolean
  narrate: boolean
  think: boolean
  fx?: boolean
  /** false stops the prompt nudge to load the vox-voice skill */
  skillNudge?: boolean
  stream: boolean
  /** false: only words after a keyword are dictated */
  autoListen?: boolean
  keywords?: string[]
  listening: boolean
  speaking: boolean
  thinking: boolean
  sounds: Record<string, string>
}

/** What the voice helper publishes several times a second. */
export type VoiceLive = {
  levels: number[]
  /** Claude's own voice, as the helper plays it */
  out: number[]
  text: string
  sent: string
  verdict: { p?: number; text?: string }
  wait: number
  /** the sentence Claude is saying now, its length and how far in, in seconds */
  spoken?: { text?: string; seconds?: number; elapsed?: number }
  /** every Jev call for the current or last message */
  judged?: { text: string; p: number; ms: number }[]
  speaking: boolean
  /** whether a Jev key is set, and whether Jev is switched on */
  jev?: { configured: boolean; on: boolean }
  /** with only-me on: the last voice check, how alike (0..1), whether it passed, and when (s) */
  me?: { enrolled: boolean; on: boolean; last?: { p?: number; ok?: boolean; at?: number } }
  pane?: string
  /** the user said "pause": dictation waits for "resume" */
  paused?: boolean
}

declare module 'claude-code' {
  interface PluginState {
    vox: { state: VoxState | null; live: VoiceLive | null; home: string; bigYou: string; bigClaude: string; lastClaude: boolean; frame: number; needs: string[]; expanded: boolean }
  }
}
