import Foundation

let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
let fifo = "\(home)/.claude/sounds/.voice.fifo"
let playing = "\(home)/.claude/sounds/.voice.playing"

func conf() -> [String: Any] {
  (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(home)/.claude/vox.json")))) as? [String: Any] ?? [:]
}

// Every tuning value is a setting, so tuning never needs a rebuild; the defaults match vox.default.json.
func setting(_ key: String, _ fallback: Double) -> Double { conf()[key] as? Double ?? fallback }

// With "autoListen" off, only words that start with a keyword ("Vox, ...") are typed, without it; nil means none was said.
func afterKeyword(_ text: String) -> String? {
  guard conf()["autoListen"] as? Bool == false else { return text }
  let words = ((conf()["keywords"] as? [String]) ?? ["vox", "claude", "fox"]).map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
  guard let re = try? NSRegularExpression(pattern: "^\\W*(?:hey\\W+)?(?:\(words))\\b[\\s\\p{P}]*", options: .caseInsensitive),
        let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range, in: text) else { return nil }
  let rest = text[r.upperBound...]
  return rest.prefix(1).uppercased() + rest.dropFirst()
}

func onlyMe() -> Bool { conf()["onlyMe"] as? Bool ?? false }
func meThreshold() -> Float { Float(setting("meThreshold", 0.5)) }
