# -*- coding: utf-8 -*-
"""
timing.py -- generic narration builder for simple_reel.

Turns a narration spec (JSON) into three artifacts using Microsoft edge-tts
(free, no API key) + ffmpeg. Content-agnostic: works for a single narrator or a
multi-voice "podcast" -- it only depends on the voices map and the lines given.

    <out>.mp3           spoken audio (all lines stitched, small gap between)
    <out>.timing.json   {"mp3","gap","total","segments":[{i,speaker,text,start,end}]}
    <out>.srt           captions (one entry per line)

Usage:
    python timing.py narration.json out_basename

narration.json:
{
  "voices": { "Narrator": "en-US-AndrewMultilingualNeural" },
  "rate": "-2%",        # optional; applied to every line unless a line overrides
  "gap": 0.40,          # optional; seconds of silence between lines
  "lines": [
    { "speaker": "Narrator", "text": "First sentence." },
    { "speaker": "Narrator", "text": "Second one." }
  ]
}

For a multi-host podcast, list several voices and tag each line with its speaker:
  "voices": { "Marcus": "en-US-AndrewMultilingualNeural",
              "Diana":  "en-US-AvaMultilingualNeural",
              "Theo":   "en-GB-RyanNeural",
              "Grace":  "en-US-EmmaMultilingualNeural" }
"""
import asyncio, json, os, sys, subprocess
import edge_tts


def ffprobe_dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nw=1:nk=1", path],
                         capture_output=True, text=True).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return 0.0


def srt_time(t):
    h = int(t // 3600); m = int((t % 3600) // 60); s = int(t % 60)
    ms = int(round((t - int(t)) * 1000))
    if ms == 1000:
        s += 1; ms = 0
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms)


async def synth(sem, idx, text, voice, rate, tmp):
    path = os.path.join(tmp, "l%05d.mp3" % idx)
    async with sem:
        await edge_tts.Communicate(text, voice, rate=rate).save(path)
    return path


async def build(spec, out_base):
    voices = spec["voices"]
    g_rate = spec.get("rate", "+0%")
    gap = float(spec.get("gap", 0.4))
    lines = spec["lines"]

    tmp = out_base + "_tmp"
    os.makedirs(tmp, exist_ok=True)
    for f in os.listdir(tmp):
        try:
            os.remove(os.path.join(tmp, f))
        except OSError:
            pass

    sem = asyncio.Semaphore(6)
    tasks = []
    for i, ln in enumerate(lines):
        sp = ln.get("speaker", "Narrator")
        voice = voices.get(sp) or next(iter(voices.values()))
        rate = ln.get("rate", g_rate)
        tasks.append(asyncio.create_task(synth(sem, i, ln["text"], voice, rate, tmp)))
    paths = await asyncio.gather(*tasks)

    sil = os.path.join(tmp, "_sil.mp3")
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
                    "-t", str(gap), "-c:a", "libmp3lame", "-b:a", "96k", sil],
                   check=True, capture_output=True)

    timing = []
    cursor = 0.0
    listf = os.path.join(tmp, "_list.txt")
    with open(listf, "w", encoding="utf-8") as lf:
        for i, (ln, p) in enumerate(zip(lines, paths)):
            d = ffprobe_dur(p)
            timing.append({"i": i, "speaker": ln.get("speaker", "Narrator"),
                           "text": ln["text"], "start": round(cursor, 3),
                           "end": round(cursor + d, 3)})
            lf.write("file '%s'\n" % p.replace("\\", "/"))
            lf.write("file '%s'\n" % sil.replace("\\", "/"))
            cursor = cursor + d + gap

    out_mp3 = out_base + ".mp3"
    subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", listf,
                    "-c:a", "libmp3lame", "-b:a", "112k", out_mp3],
                   check=True, capture_output=True)
    total = ffprobe_dur(out_mp3)

    with open(out_base + ".timing.json", "w", encoding="utf-8") as f:
        json.dump({"mp3": os.path.basename(out_mp3), "gap": gap,
                   "total": round(total, 3), "segments": timing},
                  f, indent=1, ensure_ascii=False)

    multi = len(voices) > 1
    with open(out_base + ".srt", "w", encoding="utf-8") as f:
        for n, seg in enumerate(timing, 1):
            label = (seg["speaker"] + ": ") if multi else ""
            f.write("%d\n%s --> %s\n%s%s\n\n" % (n, srt_time(seg["start"]),
                    srt_time(seg["end"]), label, seg["text"]))

    print("WROTE %s  |  %dm%02ds  |  %d lines" %
          (os.path.basename(out_mp3), int(total // 60), int(total % 60), len(lines)))
    print("WROTE %s.timing.json and %s.srt" %
          (os.path.basename(out_base), os.path.basename(out_base)))


def main():
    if len(sys.argv) < 3:
        print("usage: python timing.py narration.json out_basename")
        return
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        spec = json.load(f)
    asyncio.run(build(spec, sys.argv[2]))


if __name__ == "__main__":
    main()
