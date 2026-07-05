# simple_reel — Rendering Capabilities Report

> **STATUS 2026-07-04 (same day, v0.3.0): IMPLEMENTED — Tiers 0–3 plus
> character-sheet anchoring (IP-Adapter).** Grade-band style guide at
> `docs/STYLE_GUIDES.md`; profiles + Animagine XL 4.0; `svg:` stills (resvg);
> `kind: manim` (Manim CE 0.20.1); `kind: blender` (Blender 4.5.11 LTS);
> `characters` mode + `ref_image` (IP-Adapter plus SDXL). Unreal skipped by
> decision. This file remains the options survey; RUNBOOK.md is the operating doc.

*2026-07-04. What the pipeline can be extended to render, with what free tools,
under Eiffel control. Written against v0.2.0 (bin\simple_reel.exe, REEL_DOCTOR,
scribe removed). Hardware baseline: RTX 5070 Ti 16 GB; installed models:
SDXL base, FLUX.1-dev fp8, Wan 2.2 TI2V-5B.*

---

## 0. The architecture invariant (read first)

Every extension below plugs into one of exactly **two sockets that already exist**:

1. **ComfyUI graph templates** (`MODEL_PROFILE`). Any model ComfyUI can run is
   just a new `templates/*.json` with `%TOKEN%` placeholders plus a per-shot
   profile selector. Zero new transport code — `COMFY_CLIENT` already
   submits/polls/fetches.
2. **Headless CLI tools** (`SIMPLE_PROCESS`). Anything with a batch command
   line becomes a new shot `kind`, exactly like `ken_burns`/ffmpeg today.

And the division of labor is fixed: **Claude-in-session authors text files**
(prompts, JSON, SVG, Python scripts); **the exe renders deterministically**
(manifest resume, seeds, progress/ETA). The acid test for any candidate tool:
*can its entire creative input be a text file Claude writes?* If yes, it is a
first-class citizen. If it needs GUI authoring, it fights the pattern.

---

## 1. Age-appropriate / K-12 imagery — YES; mostly free already

Age-appropriateness in diffusion is a **prompt + checkpoint + negative-prompt**
matter; there is no rating switch. Three layers:

**(a) Claude-side style guide (zero code, works today).** A grade-band mapping
the storyboard author applies to every `still_prompt`:

| Band | Default look | Prompt fragment |
|------|--------------|-----------------|
| K-2 | flat storybook | "children's picture-book illustration, flat colors, thick friendly outlines, simple shapes, bright primaries" |
| 3-5 | 3D-cartoon | "3D animated film style, warm soft lighting, rounded characters, vibrant" |
| 6-8 | graphic novel | "graphic-novel illustration, clean ink lines, rich flat shading" |
| 9-12 | cinematic | current photoreal default |

Plus band-specific negatives appended to the existing negative prompt
("scary, horror, gore, weapons, suggestive" etc.).

**(b) Checkpoints (free, drop-in).** SDXL base does all four bands passably;
dedicated finetunes do them well. All are SDXL-family = **same template, one
new `%CHECKPOINT%` token**: Animagine XL 4.0 (anime, OpenRAIL++ — commercial
OK), DynaVision XL (3D-cartoon look), Juggernaut XL (photoreal). All free
(Civitai/HuggingFace).

**(c) Eiffel change (small, ~half a day).** Per-storyboard and per-shot
optional `"profile"` key in the JSON → picks the template/checkpoint;
`REEL_SHOT`/`REEL_STORYBOARD` parse it, `REEL_PIPELINE` groups Phase 1 by
profile so each checkpoint loads once.

**Verdict: cheapest win on the list.** The real gate is prompt discipline —
codify the band guide as `docs/STYLE_GUIDES.md` for storyboard authoring.

---

## 2. Animation / Anime — YES; free and already half-built

**Anime stills:** Animagine XL 4.0 (SDXL anime finetune; retains the
CreativeML OpenRAIL++-M license → commercial output OK) or Illustrious-XL.
Drop-in checkpoint via §1(c).

**Anime/animation motion, in order of effort:**

1. **Wan 2.2 i2v on an anime still — works TODAY, zero change.** Wan is
   style-agnostic; it animates whatever still you hand it. Apache-2.0.
2. **Ken Burns on anime stills — works today.**
3. **AniSora (Bilibili Index-AniSora)** — open-source anime-specialized i2v
   built on Wan; community reports 480-720p on 16 GB with GGUF quantization;
   ComfyUI workflows exist. = one new template + a model download.
4. **AnimateDiff** (SD1.5/SDXL motion modules, free) — classic looping anime
   motion at ~512p, upscale after. ComfyUI-native.
5. **ToonCrafter** — anime *in-betweening*: two keyframe stills → interpolated
   motion between them ("A morphs to B" shots). ~512p on 16 GB.
6. **RIFE / FILM frame interpolation** (free) — not a generator; smooths and
   retimes any clip. Worth adding as a post-pass regardless of anime.

All of these are ComfyUI graphs → `MODEL_PROFILE` templates. The Eiffel work
is the same per-shot profile selector as §1; the per-model work is extracting
a graph template (same method used for `wan_i2v.json`).

---

## 3. Blender 3D — YES, and it is the right 3D choice

- Free (GPL; outputs are yours). Fully headless:
  `blender -b -P scene.py -o //frames_##### -F PNG -a` — exactly the
  `SIMPLE_PROCESS` pattern the pipeline already uses for ffmpeg.
- **The key fit: bpy scenes are text files.** Claude writes a Python script
  that builds geometry, lights, camera path, and render settings
  procedurally — no .blend authoring needed for the shot types that matter:
  camera flythroughs (tabernacle/temple/ancient-city from primitives +
  free assets), terrain/starfield/water/smoke beds, 2.5D parallax
  (a rendered still + depth displacement — "Ken Burns on steroids").
- Engines: **EEVEE** (fast, stylized — fits K-12 bands) vs **Cycles**
  (path-traced, OptiX-accelerated on the 5070 Ti; slower, photoreal).
- Free assets: Poly Haven (CC0 HDRIs/models/textures), Sketchfab CC0 filter.
- Integration: new shot `kind: "blender"` with a per-shot `script` field →
  exe runs Blender headless, collects frames, ffmpeg-encodes `<id>.mp4`.
  Deterministic and resumable like everything else. Effort ≈ a day.
- Honest expectation: environment/camera/abstract shots = excellent.
  **Character animation = don't** — that is what Wan/AniSora shots are for.

---

## 4. Unreal Engine 5/6 — possible, NOT recommended

- Licensing is fine (free for linear rendered content; royalties only apply
  to shipped games) and headless rendering exists (Movie Render Queue via
  `UnrealEditor-Cmd.exe … -ExecutePythonScript`), so Eiffel *could* drive it.
- But it fails the acid test: levels/sequences/materials are **binary assets
  authored in the editor GUI**. Claude cannot hand you a UE scene as a
  reviewable text file. Add a 100+ GB install, shader-compile stalls, and
  per-project setup that dwarfs the rest of the pipeline.
- Everything UE would contribute here (photoreal 3D flythroughs) Blender +
  Cycles or a Wan `video` shot delivers at a fraction of the friction.
- **Park it.** Revisit only if you someday need MetaHuman-grade digital
  humans — and that is its own project.

---

## 5. SVG & friends — YES; the sleeper hit for K-12

Diffusion cannot do reliable on-frame text; SVG can — crisp labels, exact
layout, any reading level. And **SVG is XML: Claude authors it natively.**

- **Static SVG → still (Tier-2 core).** `resvg` (single free exe) or Inkscape
  CLI rasterizes Claude-authored SVG to PNG → feeds the *existing* ken_burns
  path. Maps, timelines, labeled diagrams, charts. New `kind: "svg"` or even
  just a pre-pass before the normal still slot.
- **Manim Community** (free/MIT, `pip install manim`, CLI) — the
  3Blue1Brown engine: math, geometry, text reveals, animated maps and
  timelines. Claude writes the scene .py with **exact durations** matched to
  `timing.json`; `manim render` emits the mp4 directly. The single best
  explainer-animation tool on this list. New `kind: "manim"`.
- **SVG frame sequences** — Claude (or a tiny generator script) emits one SVG
  per keyframe → resvg batch → ffmpeg. Zero heavyweight dependencies, fully
  deterministic.
- **Eiffel-native option you already own: `simple_cairo`** (+
  `cairo-windows-1.17.2` in D:\prod) — the exe itself can draw frames
  (growing charts, progress maps, timelines) straight to PNG with **no
  external process at all**. Also `simple_graphviz`/`simple_dot` → diagram
  SVGs. The most literally-Eiffel-controlled animation route available.
- Skips: **Motion Canvas** (MIT but node/TS setup for little gain over
  Manim), **Remotion** (company-license terms; individuals free — flagged,
  not needed), HTML/CSS via headless browser (`simple_playwright` exists but
  adds browser babysitting Manim/SVG makes unnecessary).

---

## 6. Licensing ledger (for published / monetized output)

- **SDXL base, Animagine XL 4.0** — CreativeML OpenRAIL++-M: commercial output OK.
- **Wan 2.2** — Apache-2.0: OK.
- **FLUX.1-dev (on disk)** — *Non-Commercial License* on the weights. BFL has
  clarified generated **outputs** may generally be used commercially, but the
  model itself can't back a commercial service; verify the current license
  text before relying on it for monetized publication — or use SDXL/Animagine
  (clean) or FLUX.1-schnell (Apache-2.0) instead.
- **Blender** (GPL — outputs unencumbered), **Manim** (MIT), **resvg**
  (MIT/Apache), **ffmpeg**: outputs unencumbered.
- **edge-tts** — free but rides Microsoft's unofficial Edge endpoint; fine
  for now, could break someday; noted.

---

## 7. Recommended roadmap

- **Tier 0 — now, zero code:** write `docs/STYLE_GUIDES.md` (grade-band
  prompt fragments + negatives). Anime/cartoon stills via prompts on SDXL;
  Wan animates them today.
- **Tier 1 — small (~half day):** per-shot/per-storyboard `profile` key +
  `%CHECKPOINT%` token; download Animagine XL 4.0 + one cartoon checkpoint;
  Phase-1 grouping by profile.
- **Tier 2 — (~a day):** `kind: "svg"` (resvg) and `kind: "manim"` — unlocks
  crisp on-frame text/diagrams for K-12. Optional RIFE post-pass.
- **Tier 3 — (~a day+):** `kind: "blender"` (bpy scripts); then evaluate
  AniSora / AnimateDiff / ToonCrafter templates for dedicated anime motion.
- **Not doing:** Unreal Engine, Remotion.

Each tier keeps the contract: Claude authors text, `storyboard.json` stays the
single interface, the exe stays the deterministic conductor.
