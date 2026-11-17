// Voice bridge for Claude Code in herdr. One audio engine with macOS voice processing, so the microphone
// hears the user and not Claude's own voice. It plays Claude's speech, streams the user's words into a herdr pane
// as they talk (Apple's on-device recognizer), presses Enter after a pause, and stops Claude's voice the
// moment they say a word.
//   vox-helper <pane>     run; commands arrive on ~/.claude/sounds/.voice.fifo: "play <file>" | "stop" | "pane <id>"
import AVFoundation
import FluidAudio
import Speech

var queued = 0
var playGen = 0

var pane = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
var request: SFSpeechAudioBufferRecognitionRequest?
var task: SFSpeechRecognitionTask?
var typed = ""
var generation = 0
var lastWords = Date.distantPast
// Live state for the vox mod: mic levels for its equalizer, the words so far, Jev's last verdict.
let stateFile = "\(home)/.claude/sounds/.voice.state"
var levels = [Float](repeating: 0, count: 200)
var outLevels = [Float](repeating: 0, count: 200)
var judged: [[String: Any]] = []  // every Jev call for the message being spoken, for the vox pane
var lastSent = ""
var verdict: [String: Any] = [:]
func publish() {
  let quiet = Date().timeIntervalSince(lastWords)
  let state: [String: Any] = [
    "levels": levels, "out": outLevels, "judged": judged, "text": typed, "sent": lastSent, "verdict": verdict,
    "wait": typed.isEmpty ? 0 : max(0, wait(typed) - quiet),
    "speaking": FileManager.default.fileExists(atPath: playing),
    "paused": paused,
    "pane": pane,
    "me": ["enrolled": voiceprint != nil, "on": onlyMe(), "last": lastCheck],
    "jev": ["configured": !typesafeKey.isEmpty, "on": jevOn()],
    "asr": ["model": wantedModel(), "status": asrStatus],
    "spoken": speech.first.map { ["text": $0.text, "seconds": $0.seconds, "elapsed": Date().timeIntervalSince(spokenStart)] } ?? [:],
  ]
  if let data = try? JSONSerialization.data(withJSONObject: state) { try? data.write(to: URL(fileURLWithPath: stateFile), options: .atomic) }
}

func log(_ s: String) { FileHandle.standardError.write("\(Date()) \(s)\n".data(using: .utf8)!) }

// The sentences queued to speak, in order, with their length; the first is the one playing since `spokenStart`.
var speech: [(text: String, seconds: Double)] = []
var spokenStart = Date()

func stopSpeech() {
  playGen += 1; queued = 0
  speech = []
  player.stop()
  try? FileManager.default.removeItem(atPath: playing)
}

func listen() {
  generation += 1
  let mine = generation
  task?.cancel()
  forgetVoice()
  let r = SFSpeechAudioBufferRecognitionRequest()
  r.shouldReportPartialResults = true
  r.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
  r.addsPunctuation = true
  // words the recognizer otherwise mishears (toggle came out as total)
  r.contextualStrings = ["toggle", "panel", "pane", "vox", "Jev", "herdr", "Claude", "unmute", "scratch that", "send it"] + ((conf()["replace"] as? [String: String]) ?? [:]).values
  request = r
  task = recognizer.recognitionTask(with: r) { result, error in
    // a cancelled or finished task still calls back; only the current one may type or restart
    DispatchQueue.main.async {
      guard mine == generation else { return }
      guard let result else { if error != nil { log("restart: \(error!.localizedDescription)"); listen() }; return }
      let heard = result.bestTranscription.formattedString
      if paused {
        let said = heard.lowercased()
        if ["resume", "unpause", "start listening", "listen again", "i'm back"].contains(where: said.contains) {
          paused = false; log("resumed"); listen()
        }
        return
      }
      if !heard.isEmpty { lastHeard = Date() }
      guard let text = afterKeyword(heard) else { asleep = !heard.isEmpty; return }
      asleep = false
      if !text.isEmpty, mayType(text) {
        if FileManager.default.fileExists(atPath: playing) { stopSpeech() }
        lastWords = Date()
        hummed = false
        show(text)
      }
    }
  }
}

// "pause" stops dictation until the user says "resume"; the mic stays open only to hear that word
var paused = false
// words heard without a keyword: dropped once the speaker pauses, so the next utterance starts clean
var asleep = false

// After a pause, send what was said and start a fresh utterance.
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
  publish()
  if heardIsMe == false || asleep, Date().timeIntervalSince(lastHeard) > 1.2 { asleep = false; forgetVoice(); request?.endAudio(); listen() }
  // the send wait counts from when the words ended, not from the check, so a short phrase is not held twice
  if let words = checkShortPhrase() { lastWords = lastHeard; show(words) }
  guard !typed.isEmpty else { return }
  let quiet = Date().timeIntervalSince(lastWords)
  if quiet > 0.3 { judge(typed) }
  // a soft "mm-hm" once per pause when Jev hears a thought still going, like a listener nodding
  if quiet > 1.0, !hummed, let p = finished[typed], p <= 0.3,
     let hum = try? AVAudioFile(forReading: URL(fileURLWithPath: "\(home)/.claude/sounds/pack/mm.wav")) {
    hummed = true
    player.scheduleFile(hum, at: nil)
    player.play()
  }
  // "... send it" at the end sends now, without the words
  let sendNow = typed.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)).hasSuffix("send it")
  if sendNow, quiet > 0.3 {
    if let range = typed.range(of: "send it", options: [.caseInsensitive, .backwards]) { show(String(typed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) }
  } else {
    guard quiet > wait(typed) else { return }
  }
  guard !typed.isEmpty else { request?.endAudio(); listen(); return }
  closeTake()
  if heardIsMe != true, let me = likeness(), me < meThreshold() {
    noteCheck(me, ok: false)
    log("ignored, not the owner: \(typed)")
    show(""); typed = ""; finished = [:]; request?.endAudio(); listen()
    return
  }
  if runCommand(typed) {
    log("command: \(typed)")
    typed = ""; finished = [:]; intents = [:]; request?.endAudio(); listen()
    return
  }
  // the box holds more than was dictated (the user typed too): their words are theirs to send, so nothing is pressed
  if let box = composer()?.trimmingCharacters(in: .whitespaces), !box.isEmpty, box != typed.trimmingCharacters(in: .whitespaces) {
    log("not sent, the box has typed text: \(box)")
    typed = ""; finished = [:]; request?.endAudio(); listen()
    return
  }
  var better = afterKeyword(finalText(typed)) ?? typed
  if let range = better.range(of: "send it", options: [.caseInsensitive, .backwards]), sendNow {
    better = String(better[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
  }
  if better != typed { show(better) }
  herdr(["send-keys", pane, "enter"])
  lastSent = typed
  if FileManager.default.fileExists(atPath: takes) {
    let name = "\(takes)/\(Int(Date().timeIntervalSince1970))"
    try? FileManager.default.copyItem(at: current, to: URL(fileURLWithPath: name + ".wav"))
    try? typed.write(toFile: name + ".txt", atomically: true, encoding: .utf8)
  }
  try? FileManager.default.removeItem(at: current)
  log("sent: \(typed)")
  typed = ""
  finished = [:]
  request?.endAudio()
  listen()
}

// `vox-helper --keyword <text>` prints what a keyword leaves of the text, to test the setting.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--keyword" {
  print(afterKeyword(CommandLine.arguments[2]) ?? "(asleep)")
  exit(0)
}
// `vox-helper --fix <text>` prints the text after the user's dictionary, to test entries.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--fix" {
  print(fixWords(CommandLine.arguments[2]))
  exit(0)
}

// `vox-helper --likeness <wav>...` prints each file's likeness to the saved voiceprint, to calibrate the threshold.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--likeness" {
  let e = blockingly { try await CampPlusEmbedder.load() }!
  for f in CommandLine.arguments.dropFirst(2) {
    let started = Date()
    let score = blockingly { CampPlusEmbedder.cosine(try await e.embed(audioURL: URL(fileURLWithPath: f)), voiceprint ?? []) } ?? .nan
    print(String(format: "%.3f  %4.0fms  %@", score, Date().timeIntervalSince(started) * 1000, (f as NSString).lastPathComponent))
  }
  exit(0)
}

SFSpeechRecognizer.requestAuthorization { status in
  guard status == .authorized else { log("speech recognition not allowed: \(status.rawValue)"); exit(1) }
  DispatchQueue.main.async {
    _ = engine.mainMixerNode // the engine fails to start (-10875) if voice processing comes before the mixer exists
    let input = engine.inputNode
    do { try input.setVoiceProcessingEnabled(true) } catch { log("voice processing: \(error)"); exit(1) }
    if #available(macOS 14, *) {
      input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
    }
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: nil)
    let format = input.outputFormat(forBus: 0)
    let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
    // voice processing hands over several channels; the recognizer wants the first one
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
      guard let one = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buf.frameLength), let src = buf.floatChannelData else { return }
      one.frameLength = buf.frameLength
      one.floatChannelData![0].update(from: src[0], count: Int(buf.frameLength))
      request?.append(one)
      DispatchQueue.main.async { keep(one) }
      var sum: Float = 0
      for i in 0..<Int(one.frameLength) { let v = one.floatChannelData![0][i]; sum += v * v }
      let rms = (sum / Float(max(1, one.frameLength))).squareRoot()
      DispatchQueue.main.async { levels.removeFirst(); levels.append(rms) }
    }
    // Claude's own voice, for the mod's second equalizer
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buf, _ in
      guard let data = buf.floatChannelData else { return }
      var sum: Float = 0
      for i in 0..<Int(buf.frameLength) { sum += data[0][i] * data[0][i] }
      let rms = (sum / Float(max(1, buf.frameLength))).squareRoot()
      DispatchQueue.main.async { outLevels.removeFirst(); outLevels.append(rms) }
    }
    engine.prepare()
    do { try engine.start() } catch { log("engine: \(error)"); exit(1) }
    listen()
    prepareModel()
    Task.detached {
      do {
        let e = try await CampPlusEmbedder.load()
        DispatchQueue.main.async { embedder = e; log("voiceprint: model ready") }
      } catch {
        DispatchQueue.main.async { log("voiceprint: model failed: \(error)") }
      }
    }
    Thread { commands() }.start()
    log("ready, typing into \(pane)")
  }
}
RunLoop.main.run()
