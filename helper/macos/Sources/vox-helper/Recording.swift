import AVFoundation

// Each message's audio is recorded for the final pass; with ~/.claude/sounds/takes present it is also
// kept there with its text, for benchmarks.
let takes = "\(home)/.claude/sounds/takes"
// The tap opens a fresh file as soon as one closes, so each message records to its own name; `current` is the last closed.
func takeURL() -> URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vox-take-\(UUID().uuidString).wav") }
var recording = takeURL()
var current = takeURL()
var take: AVAudioFile?
func keep(_ buffer: AVAudioPCMBuffer) {
  if take == nil { take = try? AVAudioFile(forWriting: recording, settings: buffer.format.settings) }
  try? take?.write(from: buffer)
  hear(buffer)
}

// Closes the finished take so it can be read whole; `current` becomes it and the one before is deleted.
func closeTake() {
  try? FileManager.default.removeItem(at: current)
  current = recording
  recording = takeURL()
  take = nil
}
