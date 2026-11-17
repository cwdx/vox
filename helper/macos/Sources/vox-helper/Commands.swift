import AVFoundation

// Spoken commands: Jev reads short utterances for intent, in the user's own words; these exact phrases work
// without a Jev key. A whole utterance that is a command acts instead of being sent.
// "scratch that" clears the box; "stop" hushes Claude; "interrupt" presses Escape; "mute" and "unmute" flip speech;
// "slash vox full" types /vox full; "... send it" sends at once.
func runCommand(_ text: String) -> Bool {
  let said = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
  let speak = "\(home)/.claude/hooks/vox"
  func clear() { show("") }
  func run(_ args: [String]) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [speak] + args; try? p.run() }
  let intent = intents[text] ?? ""
  switch intent {
  case "clear": clear(); return true
  case "hush": clear(); stopSpeech(); return true
  case "interrupt": clear(); stopSpeech(); herdr(["send-keys", pane, "esc"]); return true
  case "pause": clear(); paused = true; log("paused"); return true
  case "mute": clear(); run(["off"]); return true
  case "unmute": clear(); run(["on"]); return true
  default: break
  }
  switch said {
  case "scratch that", "cancel", "never mind", "nevermind", "delete that": clear(); return true
  case "stop", "stop talking", "quiet", "shush": clear(); stopSpeech(); return true
  case "interrupt", "escape", "stop working": clear(); stopSpeech(); herdr(["send-keys", pane, "esc"]); return true
  case "pause", "pause listening", "stop listening", "hold on", "pause dictation": clear(); paused = true; log("paused"); return true
  case "mute", "mute voice": clear(); run(["off"]); return true
  case "unmute", "unmute voice": clear(); run(["on"]); return true
  default: break
  }
  if said.hasPrefix("slash ") {
    show("/" + said.dropFirst(6))
    return false
  }
  return false
}

func commands() {
  if !FileManager.default.fileExists(atPath: fifo) { mkfifo(fifo, 0o600) }
  while true {
    guard let h = FileHandle(forReadingAtPath: fifo) else { sleep(1); continue }
    let lines = String(decoding: h.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
    for line in lines {
      let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
      DispatchQueue.main.async {
        switch parts.first {
        case "play" where parts.count == 2, "queue" where parts.count == 2:
          guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: parts[1])) else { return }
          if parts[0] == "play" { stopSpeech() }
          let gen = playGen
          let path = parts[1]
          if speech.isEmpty { spokenStart = Date() }
          let said = (try? String(contentsOfFile: parts[1] + ".txt", encoding: .utf8)) ?? ""
          speech.append((said, Double(file.length) / file.processingFormat.sampleRate))
          queued += 1
          FileManager.default.createFile(atPath: playing, contents: nil)
          player.scheduleFile(file, at: nil) {
            DispatchQueue.main.async {
              try? FileManager.default.removeItem(atPath: path)
              try? FileManager.default.removeItem(atPath: path + ".txt")
              guard gen == playGen else { return }
              if !speech.isEmpty { speech.removeFirst(); spokenStart = Date() }
              queued -= 1
              if queued == 0 { try? FileManager.default.removeItem(atPath: playing) }
            }
          }
          player.play()
        case "enroll": enroll()
        case "stop": stopSpeech()
        case "pane" where parts.count == 2: pane = parts[1]
        default: break
        }
      }
    }
    h.closeFile()
  }
}
