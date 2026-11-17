import Foundation

func herdr(_ args: [String]) {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  p.arguments = ["herdr", "pane"] + args
  p.standardOutput = FileHandle.nullDevice
  try? p.run(); p.waitUntilExit()
}

// The Claude pane focused in herdr, so dictation follows the session the user switched to.
func focusedClaudePane() -> String? {
  let p = Process(), out = Pipe()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  p.arguments = ["herdr", "pane", "list"]
  p.standardOutput = out
  guard (try? p.run()) != nil else { return nil }
  let data = out.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let panes = (json["result"] as? [String: Any])?["panes"] as? [[String: Any]] else { return nil }
  return panes.first { $0["focused"] as? Bool == true && $0["agent"] as? String == "claude" }?["pane_id"] as? String
}

// The user's dictionary (vox.json "replace": {"teh": "the"}): whole words only, ignoring case. A hyphen separates
// words; letters, digits, _ and an inner . or / keep a word whole, so code, paths and addresses never change.
func fixWords(_ text: String) -> String {
  let map = Dictionary(((conf()["replace"] as? [String: String]) ?? [:]).filter { !$0.key.isEmpty }.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
  guard !map.isEmpty else { return text }
  let words = map.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
  guard let re = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_./])(?:\(words))(?![\\p{L}\\p{N}_]|[./][\\p{L}\\p{N}])", options: .caseInsensitive) else { return text }
  var out = text
  for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
    guard let r = Range(m.range, in: out), let to = map[out[r].lowercased()] else { continue }
    out.replaceSubrange(r, with: to)
  }
  return out
}

// Types the change from what is in the box to the new transcript: backspace the differing tail, type the rest.
// What the pane's prompt box holds, as the mod last saw it; nil when the mod is not watching that pane.
func composer() -> String? {
  guard let data = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/.claude/sounds/.voice.composer")),
        let box = try? JSONSerialization.jsonObject(with: data) as? [String: Any], box["pane"] as? String == pane else { return nil }
  return box["text"] as? String
}

var focusCandidate = ""
var focusSince = Date()

func show(_ raw: String) {
  let text = fixWords(raw)
  // the words follow focus: a switch to another Claude pane that holds for a second moves them there, while a
  // flicker between two clients' focus moves nothing, so words are never typed twice
  if let p = focusedClaudePane(), p != pane {
    if p != focusCandidate { focusCandidate = p; focusSince = Date() }
    if pane.isEmpty || typed.isEmpty || Date().timeIntervalSince(focusSince) >= 1 {
      if !typed.isEmpty, !pane.isEmpty { herdr(["send-keys", pane] + Array(repeating: "backspace", count: typed.count)) }
      pane = p; typed = ""; log("typing into \(pane)")
    }
  } else { focusCandidate = "" }
  guard text != typed else { return }
  // the user is typing in the box: dictation waits rather than mix into their words
  if typed.isEmpty, let box = composer(), !box.trimmingCharacters(in: .whitespaces).isEmpty { return }
  if typed.isEmpty { judged = [] }  // a new message: the pane keeps the last one's Jev calls until now
  guard !pane.isEmpty else { return }
  let common = zip(typed, text).prefix { $0 == $1 }.count
  let erase = typed.count - common
  if erase > 0 { herdr(["send-keys", pane] + Array(repeating: "backspace", count: erase)) }
  let add = String(text.dropFirst(common))
  if !add.isEmpty { herdr(["send-text", pane, add]) }
  typed = text
}
