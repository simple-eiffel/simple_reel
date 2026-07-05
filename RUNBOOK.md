# simple_reel — Runbook (author instructions for any source MD)

*The canonical, content-agnostic instructions. When Larry points Claude at a markdown
file, Claude follows this to produce a captioned video whose visuals are timed to a
narration. Works for any length. Generic — nothing here is NOUS-specific.*

---

## The tool at a glance

The exe lives at **`D:\prod\simple_reel\bin\simple_reel.exe`** and `bin\` is on the
user PATH, so from any prompt:

```
simple_reel --help      full usage text (start here when you forget)
simple_reel status      checklist: ffmpeg, curl, templates, ComfyUI, edge-tts, resvg, manim, blender
simple_reel up          start whatever is down (ComfyUI, own console) and wait until ready
```

A render **auto-starts ComfyUI** if it isn't running (waits up to 3 minutes), so
`up` is optional — it just lets you front-load the wait. The install root defaults to
`D:\prod\simple_reel` (override with the `SIMPLE_REEL_HOME` env var); templates and
temp files resolve against it, so the exe works from any current directory.

### Who runs what

| Tool | Run by | Job |
|------|--------|-----|
| `bin\simple_reel.exe` | Larry (or Claude) | render scenes, assemble the film, character sheets, preflight/startup |
| `timing.py` | Larry/Claude, system python | narration.json → mp3 + timing.json + srt (needs `pip install edge-tts`, ffmpeg) |
| `make_storyboard.py` | optional | scaffold a drift-free storyboard.json from timing.json + prompts.json |
| `resmooth.py` | optional | regenerate ken_burns clips from existing stills (no GPU), then re-run assemble |
| `D:\AI\upscale_video_4k.py` | called **by the exe** | 4K pass on Wan video clips (via ComfyUI's embedded python) |
| `tools\resvg.exe` | called **by the exe** | rasterize `svg:` shot stills (crisp on-frame text) |
| Manim (`python -m manim`) | called **by the exe** | render `kind: manim` scene scripts |
| `D:\AI\blender\blender.exe` | called **by the exe** | render `kind: blender` bpy scripts headless |

The exe does **not** call the three python helpers above — they are separate steps.
It invokes the 4K upscaler (per video shot), resvg, Manim and Blender itself.

### Shot kinds and sources (v0.3, contracts in `docs/STYLE_GUIDES.md`)

- `kind`: `ken_burns` | `video` (Wan i2v) | `still` | `manim` (scene .py) | `blender` (bpy .py)
- **Still source**: diffusion `still_prompt` (checkpoint chosen by `profile` —
  reel-level or per-shot; map in `templates/profiles.json`: `default`/`photo` = SDXL,
  `anime` = Animagine XL 4.0) **or** `svg: <file>` rasterized by resvg.
- **Grade-band styles (K-12)**: prompt fragments + negatives per band in
  `docs/STYLE_GUIDES.md` §1 — that plus `profile` is how age-appropriate reels happen.
- **Character consistency**: author `characters.json` (name + verbatim spec + seed) →
  `simple_reel characters characters.json` renders reference sheets into
  `<output_dir>/characters/<name>.png` → shots repeat the spec text verbatim AND add
  `"ref_image": "characters/<name>.png"` (IP-Adapter anchors the identity). For a
  recurring character seen from several angles or in several moods, build a **multi-view
  / expression / pose sheet** — see [Character sheets](#character-sheets--multi-angle-expression-pose) below.
- Diffusion stills render **grouped by checkpoint** (each model loads once); pure
  SVG/manim/blender reels don't need ComfyUI at all.

### Character sheets — multi-angle, expression, pose

A **character sheet** (a.k.a. *model sheet* / *turnaround*) is the animator's device for
keeping one character on-model across many shots. The classic sheet has four parts;
simple_reel realizes each as one or more clean reference PNGs under `characters/`.

| Sheet part | What it is (traditional) | How to author it here |
|---|---|---|
| **Turnaround** | The same figure from 3–5 angles — front, ¾, side/profile, back — aligned on shared eye / shoulder / waist / knee / foot guidelines so proportions never drift between views. | One `characters[]` entry **per angle**: identical `seed` + identical identity spec, differing only in the view tag (`front view` · `three-quarter view facing left` · `side profile` · `back view`). |
| **Expression sheet** | The emotional range — neutral, joy, sadness, anger, surprise, fear, wonder — each true to the character's personality. | One entry **per expression** you'll actually use: same seed + spec, tag swapped (`gentle smile` · `wide-eyed wonder` · `downcast, near tears`). |
| **Pose sheet** | Standing / action poses that read the character's body language. Convention: one bent limb + one straight (contrapposto) so other shots have more to go on. | One entry **per recurring pose**: same seed + spec (`standing A-pose` · `kneeling` · `reaching upward` · `mid-stride walking`). |
| **Detail callouts** | Clothing, props, palette, distinctive marks noted on the sheet so they stay fixed. | Bake the invariants **into the identity spec** — the block every entry and every shot repeats verbatim (hair, eyes, face, outfit, palette). |

**Authoring recipe**

1. Write **one identity spec** — the verbatim block of invariant traits (age, build, hair,
   eyes, face, outfit, palette). This exact text is repeated in *every* `characters[]`
   entry **and** in *every shot's* `still_prompt`. Never paraphrase it between shots.
2. Emit **several entries** that share that identity spec and the **same seed**, each
   ending in a different **view / expression / pose** tag. Name them `<char>_<variant>`
   (`boy_front`, `boy_3q`, `boy_profile`, `boy_smile`, `boy_kneel`).
3. `simple_reel characters characters.json` renders one clean PNG per entry into
   `<output_dir>/characters/` (832×1216, plain background, fixed seed).
4. Each shot picks the **variant whose angle + mood match the moment** and wires it in with
   `"ref_image": "characters/<char>_<variant>.png"` + `"ref_weight"` (0.4–0.5
   scene-dominant, **0.55 default**, 0.7+ identity-locked), repeating the identity spec
   verbatim in `still_prompt`.

**Why single-subject variants, not one gridded sheet.** The reference is fed to
IP-Adapter, which anchors identity best from a **clean, single-subject** image. A
multi-panel turnaround grid (several small faces on one canvas) is excellent *human*
documentation but a poor IP-Adapter anchor — it tries to reproduce the grid. So keep the
**library** of angles/expressions/poses as *separate* clean renders, one file each, and let
each shot reach for the right one. If you also want a human-eyeball turnaround to verify
consistency, render it as an extra *documentation* entry (`boy_turnaround`, spec +
`character model sheet, front, side and back views, plain background`) — but don't point
shots at it.

**Match the reference to the shot.** Front-facing dialogue → `_front`; a figure seen
walking from the side → `_profile`; a tender beat → `_smile`; a grief beat → the downcast
expression. A mismatched reference (a smiling anchor on a weeping shot) fights the scene and
washes out the emotion. Same seed + same identity spec regenerates any variant identically,
so the whole library is reproducible and the reel stays self-contained.

## Invocation

Larry says:

> **Follow the simple_reel Runbook.**
> Source MD: `<path to some .md>`
> Mode: **1 (narrate as-is)**  *or*  **2 (podcast)**
> Reel name: `<short_slug>`   *(optional; default = the MD's basename)*

Claude then performs the steps below and hands Larry the two EXE commands to run.

## The two modes (this is the only thing that differs)

- **Mode 1 — narrate the MD as-is.** One narrator reads the chapter's own prose. Faithful, fast. Use for essays/chapters meant to be *read aloud*.
- **Mode 2 — podcast from the MD.** Claude writes a multi-host dialogue *about* the chapter (like a discussion show), then narrates that. Livelier, longer, adds commentary. Use for explainer/companion content.

Everything after the narration is **identical** for both modes.

---

## Step 1 — Claude authors `narration.json`

Read the source MD. Produce a `narration.json` (schema below) into the reel's output folder.

**Mode 1 (as-is):**
- Strip markdown: drop headings, block-quote markers, footnote markers `[^n]`, links, and any front-matter. Keep the prose.
- Expand things that must be *spoken*: numerals, abbreviations, `&`, symbols. Spell out foreign/technical terms phonetically only if needed.
- Split into `lines` of ~1–3 sentences each (natural breath groups). One voice: `"Narrator"`.

**Mode 2 (podcast):**
- Write an original dialogue that teaches the chapter — 2–4 named hosts (e.g. a host, an expert, a skeptic, a plain-spoken everyperson). Cover the chapter's real content and sources; don't invent facts beyond the MD.
- Each `line` is `{ "speaker": <host>, "text": <what they say> }`. Map each host to a voice in `voices`.

**`narration.json` schema (consumed by `timing.py`):**
```json
{
  "voices": { "Narrator": "en-US-AndrewMultilingualNeural" },
  "rate": "-2%",
  "gap": 0.4,
  "lines": [
    { "speaker": "Narrator", "text": "One breath group of prose." },
    { "speaker": "Narrator", "text": "The next." }
  ]
}
```
Good default voices (edge-tts, free): narrator `en-US-AndrewMultilingualNeural`; podcast cast
`en-US-AndrewMultilingualNeural` / `en-US-AvaMultilingualNeural` / `en-GB-RyanNeural` / `en-US-EmmaMultilingualNeural`.

## Step 2 — Build the audio + timing (Larry or Claude runs)

```
python D:\prod\simple_reel\timing.py "<output_dir>\narration.json" "<output_dir>\<reel>"
```
Produces, in `<output_dir>`: `<reel>.mp3` (the narration), `<reel>.timing.json`
(per-line `start`/`end` + `total`), and `<reel>.srt` (captions). Needs `edge-tts`
(`pip install edge-tts`) and ffmpeg — `simple_reel status` verifies both. **Do this
first** — its `total` and per-line timings drive the storyboard.

## Step 3 — Claude authors `storyboard.json` (timed to `timing.json`)

Read `<reel>.timing.json`. Turn its segments into visual scenes:

- **Each scene covers one or more consecutive narration lines**; `scene.duration` = sum of those lines' `(end - start)`. The scene durations must total `timing.total` (± 1 s; give the remainder to the last scene).
- **Use whole-second (integer) durations.** The render engine and `resmooth.py` compute frame counts as `int(duration) * fps` — i.e. they **floor** each duration. Fractional durations (e.g. `9.858`) silently lose up to ~1 s **per scene**, which accumulates (54 scenes ≈ 30 s short) and leaves the assembled video ending before the narration. Tile integers drift-free instead: round each line's `start` to the nearest second, set `duration[i] = round(start[i+1]) − round(start[i])`, and give the last scene `round(total) − round(start[last])`. Sum then equals `round(timing.total)` exactly.
- **Keep scenes ~8–20 s.** If a single line runs longer, split it into 2–3 scenes of roughly equal duration, each with its own still, so the picture keeps moving.
- **Visualize the content being spoken**, not the speakers. Set `still_prompt` to one concise, photorealistic, cinematic sentence for that moment. No on-frame text. If Christ appears, keep his face **in light / unseen**.
- **Mostly `ken_burns`** (still + ffmpeg pan/zoom, cheap). Reserve **`video`** (Wan i2v, ≤ 5 s) for ~5–10 % of scenes where real motion matters. Vary `motion`.
- Put the `narration` (the spoken words for that scene) in each shot for the record.
- Set `output_dir` to **`D:/reels/<reel>`** (the D: drive has space and avoids OneDrive; Eiffel resume works there). All artifacts — narration, storyboard, stills, clips, final film — live in that one folder.

*Mechanical alternative:* one scene per narration line, durations tiled drift-free from
the timing file — `python make_storyboard.py <timing.json> <out.json> <reel> <output_dir> <prompts.json>`
where `prompts.json` = `[ {"still": "...", "motion": "push_in"}, ... ]`, one entry per line.

**`storyboard.json` schema (consumed by `simple_reel.exe`):**
```json
{
  "reel": "<reel>",
  "output_dir": "D:/reels/<reel>",
  "fps": 24, "width": 1280, "height": 704,
  "shots": [
    { "id": "s001", "section": "label", "kind": "ken_burns", "motion": "push_in",
      "duration": 14, "seed": 101,
      "narration": "the words spoken during this scene",
      "still_prompt": "one cinematic sentence, no on-frame text",
      "motion_prompt": "movement sentence (only used when kind = video)",
      "negative": "blurry, low quality, distorted, extra limbs, deformed hands, text, watermark, cartoon, oversaturated" }
  ]
}
```
- `id`: `s001`, `s002`, … zero-padded, in order (filenames derive from it; the id **is** the record — the assembler stitches by walking these in order).
- `kind`: `ken_burns` | `video` | `still`.  `motion`: `push_in|push_out|pan_left|pan_right|pan_up|pan_down`.

## Step 4 — Render + assemble (Larry runs)

```
simple_reel "<output_dir>\storyboard.json"                              REM render all scenes
simple_reel assemble "<output_dir>\storyboard.json" "<output_dir>\<reel>.mp3"   REM stitch + mux narration
```

No need to start ComfyUI by hand — the render launches it (own console window) when it
is down and waits until it answers. To pre-warm or troubleshoot: `simple_reel up` /
`simple_reel status`. Ctrl-C and re-run the render any time — `manifest.json` skips
finished scenes.

## Step 5 — Captions

Rename `<reel>.srt` to match the final film (`<reel>_narrated.srt`) or keep the same
basename; drop it beside the `.mp4`. Most players auto-load a same-named `.srt`. For
burned-in captions instead: `ffmpeg -i <reel>_narrated.mp4 -vf subtitles=<reel>.srt out.mp4`.

## Fix-ups

- **Jerky ken_burns pans** (older reels): `python D:\prod\simple_reel\resmooth.py "<output_dir>\storyboard.json"`
  regenerates every ken_burns clip from its existing still with the 4×-supersampled
  zoompan (no GPU), then re-run the `assemble` command.
- **Changed durations but the render skips ("resume: N done, 0 to render")**: `simple_reel`
  keys its resume off `manifest.json`, not the clip files — deleting the `.mp4` clips does
  **not** force a re-render, and re-running just reports "nothing to render." To re-cut
  ken_burns clips to new (integer) durations without a GPU pass, run
  `python D:\prod\simple_reel\resmooth.py "<output_dir>\storyboard.json"` (it rebuilds every
  ken_burns clip straight from the existing `*_still.png` at `int(duration)*fps` frames,
  ignoring the manifest), then re-run `assemble`. Verify with `ffprobe` that the final
  `_narrated.mp4` duration matches `timing.total`.
- **Rebuilding the exe** (after source changes): `cd D:\prod\simple_reel` then
  `D:\prod\ec.sh release -config simple_reel.ecf -target simple_reel_app`, and copy
  `EIFGENs\simple_reel_app\F_code\simple_reel_lean.exe` over `bin\simple_reel.exe`
  (`simple_reel_dbc.exe` is the contract-checking build, kept beside it in `bin\`).

## Outputs (all under `output_dir`)

```
narration.json  <reel>.mp3  <reel>.timing.json  <reel>.srt
<id>_still.png  <id>.mp4  <id>_3840w.mp4(video only)
<reel>.mp4 (silent)  <reel>_narrated.mp4 (with audio)  manifest.json  <reel>_concat.txt
```

---

*Pipeline: narration = edge-tts (`timing.py`); stills = SDXL, video = Wan 2.2 (ComfyUI);
Ken Burns + 4K + concat + mux = ffmpeg; orchestration = `simple_reel.exe` (Eiffel).
The only per-job creative work is Steps 1 and 3, which Claude does.*
