import AVFoundation
import FluidAudio

// Only the owner's voice: CAM++ turns a message into a 192-number voiceprint; the owner's is the average of their kept
// messages (~/.claude/sounds/takes). With vox.json "onlyMe" on, a message whose print is far from it is dropped.
let voiceprintFile = "\(home)/.claude/sounds/voiceprint.json"
var embedder: CampPlusEmbedder?
var voiceprint: [Float]? = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: voiceprintFile)))) as? [Double])?.map(Float.init)

func blockingly<T>(_ work: @escaping () async throws -> T) -> T? {
  var out: T?
  let done = DispatchSemaphore(value: 0)
  Task.detached { out = try? await work(); done.signal() }
  done.wait()
  return out
}

// Averages the prints of the kept messages into the owner's voiceprint and saves it.
func enroll() {
  Task.detached {
    do {
      let e: CampPlusEmbedder
      if let loaded = embedder { e = loaded } else { e = try await CampPlusEmbedder.load() }
      let files = ((try? FileManager.default.contentsOfDirectory(atPath: takes)) ?? []).filter { $0.hasSuffix(".wav") }.sorted().suffix(20)
      var sum = [Float](repeating: 0, count: 192)
      var used = 0
      for f in files {
        guard let v = try? await e.embed(audioURL: URL(fileURLWithPath: "\(takes)/\(f)")) else { continue }
        // once a voiceprint exists, only messages that already sound like the owner refine it, never a guest's
        if let old = voiceprint, CampPlusEmbedder.cosine(v, old) < meThreshold() { continue }
        for (i, x) in v.enumerated() { sum[i] += x }
        used += 1
      }
      guard used > 0 else { DispatchQueue.main.async { log("voiceprint: no messages to learn from") }; return }
      let norm = sum.map { $0 * $0 }.reduce(0, +).squareRoot()
      let print = sum.map { $0 / max(norm, 1e-6) }
      try JSONSerialization.data(withJSONObject: print).write(to: URL(fileURLWithPath: voiceprintFile))
      DispatchQueue.main.async { embedder = e; voiceprint = print; log("voiceprint: enrolled from \(used) messages") }
    } catch {
      DispatchQueue.main.async { log("voiceprint: enrolment failed: \(error)") }
    }
  }
}

// The last 3 s of the mic at 16 kHz, so the owner check runs before a word is typed, not only at the send.
// The message's speech at 16 kHz, quiet stretches left out, at most 3 s: the check judges a voice, not the room.
var voiceSamples: [Float] = []
var heardIsMe: Bool?
var firstWordsAt: Date?
// Words held back while the check decides, typed at once when it passes.
var pendingText = ""
// When any words were last heard, the owner's or not, so a rejected voice is forgotten once it stops.
var lastHeard = Date.distantPast
// The last voice check, for the mod: how alike, whether it passed, and when.
var lastCheck: [String: Any] = [:]
// After another voice is heard, two minutes in which every check uses the strict bar: someone else is in the room.
var guestUntil = Date.distantPast

func hear(_ buffer: AVAudioPCMBuffer) {
  guard voiceprint != nil, heardIsMe == nil, let samples = buffer.floatChannelData?[0] else { return }
  let n = Int(buffer.frameLength)
  let rms = (stride(from: 0, to: n, by: 1).reduce(Float(0)) { $0 + samples[$1] * samples[$1] } / Float(max(1, n))).squareRoot()
  guard rms > 0.01 else { return }
  let step = max(1, Int(buffer.format.sampleRate / 16_000))
  voiceSamples += stride(from: 0, to: n, by: step).map { samples[$0] }
  if voiceSamples.count > 48_000 { voiceSamples.removeFirst(voiceSamples.count - 48_000) }
}

// Whether live words may be typed: always, unless only-me is on and the voice is not the owner's. It decides once
// 1.6 s of speech is in; a clip that short scores lower than a whole message, so it passes meLoose (0.15) below the send's bar.
func mayType(_ text: String) -> Bool {
  guard onlyMe(), voiceprint != nil, embedder != nil else { return true }
  if let known = heardIsMe { return known }
  firstWordsAt = firstWordsAt ?? Date()
  pendingText = text
  return voiceSamples.count >= 25_600 && checkVoice()
}

// A short phrase ("thank you") ends before 1.6 s of speech: it is judged on what there is once the speaker stops.
func checkShortPhrase() -> String? {
  guard heardIsMe == nil, firstWordsAt != nil, Date().timeIntervalSince(lastHeard) > 0.5, voiceSamples.count >= 6_400 else { return nil }
  return checkVoice() ? pendingText : nil
}

func checkVoice() -> Bool {
  guard let print = voiceprint, let e = embedder else { return true }
  let voice = Array(voiceSamples.suffix(25_600))
  guard let me = blockingly({ CampPlusEmbedder.cosine(try await e.embed(audio: voice), print) }) else { return true }
  // under a second of speech scores lower still: other voices measured 0.1 to 0.2 there, the owner 0.27 and up
  heardIsMe = me >= meThreshold() - Float(Date() < guestUntil ? 0 : voice.count < 25_600 ? setting("meLooseShort", 0.25) : setting("meLoose", 0.15))
  noteCheck(me, ok: heardIsMe!)
  return heardIsMe!
}

func noteCheck(_ me: Float, ok: Bool) {
  lastCheck = ["p": me, "ok": ok, "at": Date().timeIntervalSince1970]
  if !ok { guestUntil = Date().addingTimeInterval(setting("guestSeconds", 120)) }
  log(String(format: ok ? "the owner (%.2f)" : "not the owner (%.2f)", me))
}

func forgetVoice() { heardIsMe = nil; firstWordsAt = nil; voiceSamples = []; pendingText = "" }

// How close the whole message is to the owner's voiceprint, 1 the same voice; nil when not checked. The send uses it
// only when the live check never decided, since a short phrase's take is mostly silence.
func likeness() -> Float? {
  guard onlyMe(), let print = voiceprint, let e = embedder else { return nil }
  let url = current
  return blockingly { CampPlusEmbedder.cosine(try await e.embed(audioURL: url), print) }
}
