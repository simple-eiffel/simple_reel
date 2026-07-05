# -*- coding: utf-8 -*-
"""Scaffold storyboard.json from a timing.json (drift-free durations) + a prompts.json.
Usage: python make_storyboard.py <timing.json> <out storyboard.json> <reel> <output_dir> <prompts.json>
prompts.json = [ {"still": "...", "motion": "push_in"}, ... ]  one entry per narration line.
One scene per line; scene boundaries land on integer-second marks of the audio, so scene
durations tile the timeline exactly (no audio/video drift)."""
import json, sys

NEG = "blurry, low quality, distorted, extra limbs, deformed hands, warped face, text, watermark, cartoon, oversaturated"

def main():
    timing_path, out_path, reel, outdir, prompts_path = sys.argv[1:6]
    d = json.load(open(timing_path, encoding="utf-8"))
    prompts = json.load(open(prompts_path, encoding="utf-8"))
    segs = d["segments"]; total = float(d["total"]); n = len(segs)
    fb = ["push_in", "pan_right", "push_out", "pan_left", "push_in", "pan_up", "pan_down"]
    shots = []
    for i in range(n):
        start_b = round(segs[i]["start"])
        end_b = round(segs[i + 1]["start"]) if i + 1 < n else round(total)
        dur = max(1, end_b - start_b)
        if i < len(prompts):
            still = prompts[i].get("still", "a cinematic frame")
            motion = prompts[i].get("motion", "push_in")
        else:
            still, motion = ("a lone figure in a shaft of light in a vast dim space, cinematic", fb[i % len(fb)])
        shots.append({
            "id": "s%03d" % (i + 1), "section": "line %d" % (i + 1),
            "kind": "ken_burns", "motion": motion, "duration": dur, "seed": 101 + i,
            "narration": segs[i]["text"], "still_prompt": still, "motion_prompt": "", "negative": NEG,
        })
    sb = {"reel": reel, "output_dir": outdir, "fps": 24, "width": 1280, "height": 704, "shots": shots}
    json.dump(sb, open(out_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("scenes: %d | prompts: %d | sum(dur): %d s | audio total: %d s"
          % (len(shots), len(prompts), sum(s["duration"] for s in shots), round(total)))

if __name__ == "__main__":
    main()
