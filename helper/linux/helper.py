#!/usr/bin/env python3
"""Linux/WSL dictation for vox: mic -> silero VAD -> Parakeet (sherpa-onnx) -> herdr pane. Usage: helper.py <pane> | --file x.wav"""
import json, os, queue, re, shutil, subprocess, sys, threading, time, wave
from pathlib import Path

import numpy as np

HOME = Path.home()
SOUNDS = HOME / ".claude/sounds"
FIFO, STATE, LOG = SOUNDS / ".voice.fifo", SOUNDS / ".voice.state", SOUNDS / ".voice.log"
PLAYING = SOUNDS / ".voice.playing"
CACHE = HOME / ".cache/vox"
MODEL = CACHE / "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
RATE = 16000
CONF = HOME / ".claude/vox.json"
CONNECTORS = {"and", "but", "so", "or", "because", "then", "um", "uh", "like", "the", "a", "to", "of", "with"}

S = dict(pane="", text="", sent="", paused=False, speaking=False, spoken={}, status="loading", quiet_since=None)
levels = [0.0] * 200
lock = threading.Lock()
playlist, player = [], None
play_gen = 0


def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%F %T')} {msg}\n")


def fix_words(text):
    """The user's dictionary (vox.json "replace"): whole words only, ignoring case; a hyphen separates words, while
    letters, digits, _ and an inner . or / keep a word whole, so code, paths and addresses never change."""
    try:
        table = {k.lower(): v for k, v in json.loads(CONF.read_text()).get("replace", {}).items() if k}
    except (OSError, ValueError):
        return text
    if not table:
        return text
    words = "|".join(map(re.escape, sorted(table, key=len, reverse=True)))
    pattern = rf"(?<![\w./])(?:{words})(?!\w|[./]\w)"
    return re.sub(pattern, lambda m: table[m.group(0).lower()], text, flags=re.I)


def after_keyword(text):
    """With "autoListen" off, only words that start with a keyword ("Vox, ...") are sent, without it; None means none was said."""
    try:
        conf = json.loads(CONF.read_text())
    except (OSError, ValueError):
        conf = {}
    if conf.get("autoListen") is not False:
        return text
    words = "|".join(map(re.escape, conf.get("keywords") or ["vox", "claude", "fox"]))
    m = re.match(rf"\W*(?:hey\W+)?(?:{words})\b[\s\W]*", text, flags=re.I)
    return m and text[m.end():][:1].upper() + text[m.end():][1:]


def norm(t):
    return re.sub(r"[^\w' ]", "", t.lower()).strip()


def send_after(text):
    t = text.strip().lower()
    last = t.split()[-1].strip(".,!?") if t.split() else ""
    if last in CONNECTORS or not t.endswith((".", "?", "!")):
        return 1.8
    return 0.8


def herdr(*args):
    return subprocess.run(["herdr", "pane", *args], capture_output=True, text=True)


def focused_claude_pane():
    try:
        panes = json.loads(herdr("list").stdout)["result"]["panes"]
        return next((p["pane_id"] for p in panes if p.get("focused") and p.get("agent") == "claude"), None)
    except Exception:
        return None


def publish():
    wait = 0
    if S["text"] and S["quiet_since"]:
        wait = max(0, send_after(S["text"]) - (time.time() - S["quiet_since"]))
    state = dict(
        levels=levels, out=[0] * 200, judged=[], text=S["text"], sent=S["sent"], verdict={},
        wait=wait, speaking=S["speaking"], paused=S["paused"], pane=S["pane"],
        me={"enrolled": False, "on": False}, jev={"configured": False, "on": False},
        asr={"model": "parakeet-tdt-0.6b-v2", "status": S["status"]}, spoken=S["spoken"],
    )
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state))
    tmp.replace(STATE)


def player_cmd(path):
    for exe, args in (("pw-play", []), ("paplay", []), ("aplay", ["-q"])):
        if shutil.which(exe):
            return [exe, *args, path]
    if shutil.which("powershell.exe") and shutil.which("wslpath"):
        win = subprocess.run(["wslpath", "-w", path], capture_output=True, text=True).stdout.strip()
        return ["powershell.exe", "-c", f"(New-Object Media.SoundPlayer '{win}').PlaySync()"]
    return None


def wav_seconds(path):
    try:
        with wave.open(path) as w:
            return w.getnframes() / w.getframerate()
    except Exception:
        return 0


def play_loop():
    global player
    while True:
        with lock:
            item = playlist[0] if playlist else None
            gen = play_gen
        if not item:
            S["speaking"], S["spoken"] = False, {}
            PLAYING.unlink(missing_ok=True)
            time.sleep(0.05)
            continue
        cmd = player_cmd(item["file"])
        S["speaking"] = True
        PLAYING.touch()
        S["spoken"] = {"text": item["text"], "seconds": item["seconds"], "elapsed": 0}
        start = time.time()
        if cmd:
            player = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            while player.poll() is None:
                S["spoken"]["elapsed"] = time.time() - start
                time.sleep(0.05)
        else:
            log("no audio player found")
        Path(item["file"]).unlink(missing_ok=True)
        Path(item["file"] + ".txt").unlink(missing_ok=True)
        with lock:
            if gen == play_gen and playlist:
                playlist.pop(0)


def stop_speech():
    global play_gen
    with lock:
        play_gen += 1
        playlist.clear()
    if player and player.poll() is None:
        player.kill()


def fifo_loop():
    if not FIFO.exists():
        os.mkfifo(FIFO, 0o600)
    while True:
        with open(FIFO) as f:
            lines = f.read().splitlines()
        for line in lines:
            cmd, _, arg = line.partition(" ")
            if cmd in ("play", "queue") and arg:
                if cmd == "play":
                    stop_speech()
                txt = Path(arg + ".txt")
                item = dict(file=arg, text=txt.read_text().strip() if txt.exists() else "", seconds=wav_seconds(arg))
                with lock:
                    playlist.append(item)
            elif cmd == "stop":
                stop_speech()
            elif cmd == "pane" and arg:
                S["pane"] = arg.strip()
            elif cmd == "enroll":
                log("enroll is not supported on Linux")


def speak_toggle(arg):
    subprocess.Popen(["bash", str(HOME / ".claude/hooks/vox"), arg])


def run_command(text):
    said = norm(text)
    if said in ("scratch that", "cancel", "never mind", "nevermind", "delete that"):
        return True
    if said in ("stop", "stop talking", "quiet", "shush"):
        stop_speech()
        return True
    if said in ("interrupt", "escape", "stop working"):
        stop_speech()
        herdr("send-keys", S["pane"], "esc")
        return True
    if said in ("pause", "pause listening", "stop listening", "hold on", "pause dictation"):
        S["paused"] = True
        log("paused")
        return True
    if said in ("mute", "mute voice"):
        speak_toggle("off")
        return True
    if said in ("unmute", "unmute voice"):
        speak_toggle("on")
        return True
    return False


def deliver(text):
    if S["paused"]:
        if any(w in norm(text) for w in ("resume", "unpause", "start listening", "listen again", "im back")):
            S["paused"] = False
            log("resumed")
        return
    text = after_keyword(text)
    if text is None:
        return
    send = norm(text).endswith("send it")
    if run_command(text):
        log(f"command: {text}")
        return
    if send:
        text = re.sub(r"[\s.,!?]*send it[\s.,!?]*$", "", text, flags=re.I)
    if not text:
        return
    text = fix_words(text)
    S["pane"] = focused_claude_pane() or S["pane"]
    if not S["pane"]:
        log(f"no pane, dropped: {text}")
        return
    S["text"], S["quiet_since"] = text, time.time()
    herdr("send-text", S["pane"], text)
    herdr("send-keys", S["pane"], "enter")
    S["sent"], S["text"], S["quiet_since"] = text, "", None
    log(f"sent: {text}")


def recognizer():
    import sherpa_onnx
    return sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(MODEL / "encoder.int8.onnx"), decoder=str(MODEL / "decoder.int8.onnx"),
        joiner=str(MODEL / "joiner.int8.onnx"), tokens=str(MODEL / "tokens.txt"),
        model_type="nemo_transducer", num_threads=4)


def transcribe(rec, samples):
    st = rec.create_stream()
    st.accept_waveform(RATE, samples)
    rec.decode_stream(st)
    return st.result.text.strip()


def read_wav(path):
    with wave.open(path) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1, "need 16-bit mono wav"
        data = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
        rate = w.getframerate()
    if rate != RATE:
        data = np.interp(np.arange(0, len(data), rate / RATE), np.arange(len(data)), data).astype(np.float32)
    return data


def listen(rec):
    import sherpa_onnx
    import sounddevice as sd

    cfg = sherpa_onnx.VadModelConfig()
    cfg.silero_vad.model = str(CACHE / "silero_vad.onnx")
    cfg.silero_vad.min_silence_duration = 0.4
    cfg.sample_rate = RATE
    vad = sherpa_onnx.VoiceActivityDetector(cfg, buffer_size_in_seconds=60)
    q = queue.Queue()

    def on_audio(data, frames, t, status):
        q.put(data[:, 0].copy())

    chunks, last_voice, window, fresh = [], 0.0, 512, False
    buf = np.zeros(0, np.float32)
    with sd.InputStream(samplerate=RATE, channels=1, dtype="float32", blocksize=window, callback=on_audio):
        S["status"] = "ready"
        log(f"listening, pane={S['pane']}")
        while True:
            try:
                buf = np.concatenate([buf, q.get(timeout=0.1)])
            except queue.Empty:
                pass
            now = time.time()
            while len(buf) >= window:
                frame, buf = buf[:window], buf[window:]
                levels.append(min(1.0, float(np.sqrt(np.mean(frame ** 2)))))
                del levels[0]
                if S["speaking"]:
                    vad.reset()
                    chunks.clear()
                    continue
                vad.accept_waveform(frame)
                if vad.is_speech_detected():
                    last_voice = now
            while not vad.empty():
                chunks.append(vad.front.samples)
                vad.pop()
                fresh = True
            # speech that resumes before the send adds to the message: its audio is kept and re-read whole
            if fresh and now - last_voice >= 0.8:
                fresh = False
                text = transcribe(rec, np.concatenate(chunks))
                if text:
                    S["text"], S["quiet_since"] = text, now
            elif S["text"] and now - last_voice >= send_after(S["text"]):
                deliver(S["text"])
                chunks.clear()
                S["text"], S["quiet_since"] = "", None


def main():
    args = sys.argv[1:]
    if args[:1] == ["--fix"]:
        print(fix_words(args[1]))
        return
    if args[:1] == ["--keyword"]:
        woken = after_keyword(args[1])
        print("(asleep)" if woken is None else woken)
        return
    rec = recognizer()
    if args[:1] == ["--file"]:
        print(transcribe(rec, read_wav(args[1])))
        return
    S["pane"] = args[0] if args else ""
    SOUNDS.mkdir(parents=True, exist_ok=True)
    threading.Thread(target=fifo_loop, daemon=True).start()
    threading.Thread(target=play_loop, daemon=True).start()
    threading.Thread(target=lambda: [(publish(), time.sleep(0.15)) for _ in iter(int, 1)], daemon=True).start()
    try:
        listen(rec)
    except Exception as e:  # sounddevice loads inside listen(); PortAudio errors mean no usable microphone
        log(f"no microphone: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
