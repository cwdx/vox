import Foundation

// Seconds of quiet before sending: short after a finished sentence, longer mid-thought.
func sendAfter(_ text: String) -> Double {
  let t = text.trimmingCharacters(in: .whitespaces).lowercased()
  let last = t.split(separator: " ").last.map(String.init) ?? ""
  if ["and", "but", "so", "or", "because", "then", "um", "uh", "like", "the", "a", "to", "of", "with"].contains(last.trimmingCharacters(in: .punctuationCharacters)) { return 1.8 }
  if t.hasSuffix("?") { return 0.5 }
  if t.hasSuffix(".") || t.hasSuffix("!") { return 0.6 }
  return 1.8  // no punctuation yet: likely mid-thought, so give the next words time
}

// Jev (TypeSafe) judges whether a paused transcript is a finished thought; about 0.33 s a call.
let typesafeKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] ?? ""
var finished: [String: Double] = [:]
var asking = ""
var hummed = false
// Jev's reading of a short utterance as a vox command, when it is sure
var intents: [String: String] = [:]

// Jev runs when a key is configured and vox.json's "jev" is not false; off, punctuation decides when to send.
func jevOn() -> Bool {
  let c = conf()
  return c["jev"] as? Bool ?? true
}

func judge(_ text: String) {
  guard !typesafeKey.isEmpty, jevOn(), asking != text, finished[text] == nil else { return }
  asking = text
  var req = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: 1.5)
  req.httpMethod = "POST"
  req.setValue("Bearer \(typesafeKey)", forHTTPHeaderField: "Authorization")
  req.setValue("application/json", forHTTPHeaderField: "Content-Type")
  req.httpBody = try? JSONSerialization.data(withJSONObject: [
    "model": "jev-latest",
    "state": ["transcript": text],
    // the same call asks, for short utterances, whether the words are a command to vox itself
    "questions": (text.split(separator: " ").count <= 7 ? ["command": [
      "type": "choice",
      "instructions": "Someone talks to a coding assistant by voice, through speech recognition that sometimes mishears words. Is this whole utterance a command to the voice system itself, and which one?",
      "criteria": ["none": "A normal message for the assistant, a request or question about work", "clear": "Discard what was just dictated", "hush": "Stop the assistant talking right now", "interrupt": "Stop the assistant working", "pause": "Stop dictating for now, stop taking what they say until they come back", "mute": "Turn the spoken replies off", "unmute": "Turn the spoken replies back on"],
    ]] : [String: Any]()).merging(["done": [
      "type": "noul",
      "instructions": "Someone is dictating a message to a coding assistant out loud and has just paused. People pause mid-thought, so only say yes when the message is clearly complete and sending it now would not cut them off.",
      "criteria": ["true": "A complete request, question or answer that makes sense on its own and needs nothing after it", "false": "Cut off mid-sentence, a lone word or fragment that only starts a thought, ends on a filler or connecting word, or likely continues"],
    ]]) { $1 },
  ])
  let started = Date()
  URLSession.shared.dataTask(with: req) { data, _, _ in
    let p = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
    let done = ((p?["answers"] as? [String: Any])?["done"] as? [String: Any])?["noul"] as? Double
    let command = (p?["answers"] as? [String: Any])?["command"] as? [String: Any]
    let choice = command?["choice"] as? String
    let sure = ((command?["probabilities"] as? [String: Any])?[choice ?? ""] as? Double) ?? 0
    DispatchQueue.main.async {
      if let choice, choice != "none", sure >= 0.6 { intents[text] = choice; log(String(format: "intent %@ %.2f: %@", choice, sure, text)) }; if let done { finished[text] = done; verdict = ["p": done, "text": text]; judged = Array((judged + [["p": done, "text": text, "ms": Int(Date().timeIntervalSince(started) * 1000)]]).suffix(12)); log(String(format: "jev %.2f: %@", done, text)) }; asking = "" }
  }.resume()
}

// Seconds of quiet before sending: Jev's verdict when it has one, the punctuation heuristic until then.
func wait(_ text: String) -> Double {
  // a long message is a finished thought more often, a few words usually start one: the wait scales with length
  let words = text.split(separator: " ").count
  let scale = words <= 3 ? setting("shortWaitScale", 1.4) : words >= 20 ? setting("longWaitScale", 0.7) : 1.0
  let most = setting("maxWait", 3)
  guard let p = finished[text] else { return min(most, sendAfter(text) * scale) }
  // a confident yes sends soon; short messages need more certainty, since a lone word often starts a thought
  let sure = words <= 2 ? 0.9 : 0.75
  // never longer than maxWait: past that a pause is the end, whatever Jev thinks
  return min(most, (p >= sure ? 0.5 : p <= 0.3 ? 3.0 : 1.6) * scale)
}
