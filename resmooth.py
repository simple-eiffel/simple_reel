# -*- coding: utf-8 -*-
"""Regenerate the ken_burns motion clips of a reel from its existing stills, using a
4x-supersampled zoompan (smooth, no stair-step jerk). No GPU needed -- pure ffmpeg over
the *_still.png already on disk. Then re-run:  simple_reel assemble <storyboard.json> <mp3>

Usage: python resmooth.py <storyboard.json>
"""
import json, sys, os, subprocess

def kb_filter(motion, n, w, h, fps):
    sw, sh = w * 4, h * 4
    if motion == "push_out":
        z = "if(eq(on,0),1.2,max(1.2-0.2*on/%d,1.0))" % n; x = "iw/2-iw/zoom/2"; y = "ih/2-ih/zoom/2"
    elif motion == "pan_left":
        z = "1.15"; x = "(iw-iw/zoom)*(1-on/%d)" % n; y = "ih/2-ih/zoom/2"
    elif motion == "pan_right":
        z = "1.15"; x = "(iw-iw/zoom)*(on/%d)" % n; y = "ih/2-ih/zoom/2"
    elif motion == "pan_up":
        z = "1.15"; x = "iw/2-iw/zoom/2"; y = "(ih-ih/zoom)*(1-on/%d)" % n
    elif motion == "pan_down":
        z = "1.15"; x = "iw/2-iw/zoom/2"; y = "(ih-ih/zoom)*(on/%d)" % n
    else:
        z = "min(1.0+0.2*on/%d,1.2)" % n; x = "iw/2-iw/zoom/2"; y = "ih/2-ih/zoom/2"
    return ("scale=%d:%d:flags=lanczos,zoompan=z='%s':x='%s':y='%s':d=%d:s=%dx%d:fps=%d"
            % (sw, sh, z, x, y, n, w, h, fps))

def main():
    sb = json.load(open(sys.argv[1], encoding="utf-8"))
    d = sb["output_dir"].rstrip("/")
    w, h, fps = sb["width"], sb["height"], sb["fps"]
    done = 0
    for s in sb["shots"]:
        if s.get("kind", "ken_burns") != "ken_burns":
            continue
        still = d + "/" + s["id"] + "_still.png"
        out = d + "/" + s["id"] + ".mp4"
        if not os.path.exists(still):
            print("  missing:", still); continue
        n = int(s["duration"]) * fps
        vf = kb_filter(s.get("motion", "push_in"), n, w, h, fps)
        subprocess.run(["ffmpeg", "-y", "-loop", "1", "-i", still, "-vf", vf,
                        "-frames:v", str(n), "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-crf", "18", out], check=True, capture_output=True)
        done += 1
        if done % 15 == 0:
            print("  re-smoothed", done)
    print("re-smoothed %d ken_burns clips in %s" % (done, d))

if __name__ == "__main__":
    main()
