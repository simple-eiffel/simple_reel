"""Cut a reel's narration mp3 into per-shot wav slices for `kind: talking` shots.

Wan S2V drives lip-sync from an audio file, so every talking shot needs the exact
stretch of narration spoken during it. The storyboard already tiles the timeline
in whole seconds, so the slice boundaries fall straight out of the shot order.

    python slice_audio.py <storyboard.json> <narration.mp3>

Writes <output_dir>/audio/<id>.wav for each talking shot and stamps the matching
"audio" field into the storyboard in place. Re-runnable: existing slices are
overwritten, and non-talking shots are left alone.

Needs ffmpeg on PATH (same dependency as timing.py and the assembler).
"""

import json
import os
import subprocess
import sys

TALKING = {"talking", "s2v"}


def main():
    if len(sys.argv) < 3:
        print("usage: python slice_audio.py <storyboard.json> <narration.mp3>")
        return 1

    sb_path, mp3 = sys.argv[1], sys.argv[2]
    if not os.path.isfile(mp3):
        print(f"narration not found: {mp3}")
        return 1

    with open(sb_path, "r", encoding="utf-8") as f:
        sb = json.load(f)

    out_dir = sb["output_dir"]
    audio_dir = os.path.join(out_dir, "audio")
    os.makedirs(audio_dir, exist_ok=True)

    # Shot durations are whole seconds and tile the reel without gaps, so a
    # running sum gives each shot's start. Same arithmetic the assembler uses.
    start = 0
    cut = 0
    for shot in sb["shots"]:
        dur = int(shot.get("duration", 5))
        if shot.get("kind", "").lower() in TALKING:
            wav = os.path.join(audio_dir, f"{shot['id']}.wav")
            # 16 kHz mono: wav2vec2's native rate, so ComfyUI does no resampling.
            cmd = [
                "ffmpeg", "-y", "-loglevel", "error",
                "-ss", str(start), "-t", str(dur), "-i", mp3,
                "-ac", "1", "-ar", "16000", wav,
            ]
            subprocess.run(cmd, check=True)
            shot["audio"] = f"audio/{shot['id']}.wav"
            cut += 1
            print(f"{shot['id']}  {start:>5}s +{dur}s -> audio/{shot['id']}.wav")
        start += dur

    if cut == 0:
        print("no talking shots in this storyboard; nothing to cut.")
        return 0

    with open(sb_path, "w", encoding="utf-8") as f:
        json.dump(sb, f, indent=2, ensure_ascii=False)
    print(f"\n{cut} slice(s) written; storyboard updated with audio paths.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
