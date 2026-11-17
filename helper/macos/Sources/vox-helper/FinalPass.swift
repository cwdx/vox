import FluidAudio
import Foundation

// The final pass: Parakeet on the Neural Engine re-reads the whole message (vox.json "asr": parakeet, the default,
// v2 English; ultra; whisper through whisper-cli; or apple for none). Apple's live text stands when it is off,
// still loading, slower than 2.5 s or empty. Measured on an M2: v2 about 0.06 s a message, 2.6% word errors.

let finalModels: [String: AsrModelVersion] = ["parakeet": .v2, "ultra": .ultra]
var parakeet: (name: String, manager: AsrManager)?
var parakeetLoading = ""
var asrStatus = "off"

func wantedModel() -> String {
  let c = conf()
  return c["asr"] as? String ?? "parakeet"
}

// Loads the wanted Parakeet in the background; the first message after a switch uses Apple's text.
func prepareModel() {
  let name = wantedModel()
  guard let version = finalModels[name], parakeet?.name != name, parakeetLoading != name else {
    if finalModels[name] == nil { asrStatus = name == "whisper" ? (FileManager.default.fileExists(atPath: "\(home)/.cache/whisper-cpp/ggml-base.en.bin") ? "ready" : "missing") : "off" }
    return
  }
  parakeetLoading = name
  asrStatus = "loading"
  Task.detached {
    do {
      let models = try await AsrModels.downloadAndLoad(version: version)
      let manager = AsrManager()
      try await manager.loadModels(models)
      DispatchQueue.main.async { parakeet = (name, manager); parakeetLoading = ""; asrStatus = "ready"; log("final pass: \(name) ready") }
    } catch {
      DispatchQueue.main.async { parakeetLoading = ""; asrStatus = "error"; log("final pass: \(name) failed: \(error)") }
    }
  }
}

func finalText(_ live: String) -> String {
  let name = wantedModel()
  let model = "\(home)/.cache/whisper-cpp/ggml-base.en.bin"
  var text: String?
  let started = Date()
  if name == "whisper", FileManager.default.fileExists(atPath: model) {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["whisper-cli", "-m", model, "-f", current.path, "-nt", "-np"]
    p.standardOutput = out; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
    text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(whereSeparator: \.isWhitespace).joined(separator: " ")
  } else if let loaded = parakeet, loaded.name == name {
    let done = DispatchSemaphore(value: 0)
    let url = current
    Task.detached {
      var state = TdtDecoderState.make(decoderLayers: await loaded.manager.decoderLayerCount)
      text = try? await loaded.manager.transcribe(url, decoderState: &state).text
      done.signal()
    }
    _ = done.wait(timeout: .now() + 2.5)
  } else {
    prepareModel()
  }
  guard let text, !text.isEmpty else { return live }
  log(String(format: "final %@ %.0fms: %@", name, Date().timeIntervalSince(started) * 1000, text))
  return text
}
