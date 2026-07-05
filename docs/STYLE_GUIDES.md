# simple_reel — Style Guides & Authoring Contracts

*The rules Claude-in-session follows when authoring storyboard prompts and
shot assets. The exe enforces none of this — it renders what it is given;
these conventions are what make the output age-appropriate, consistent, and
renderable. Companion to RUNBOOK.md (workflow) and CAPABILITIES.md (why).*

---

## 1. Grade-band visual styles (K-12)

Pick ONE band per reel (the storyboard-level `"profile"` + prompt fragments);
per-shot overrides are allowed but rare.

### Band K-2 — storybook
- `"profile": "anime"` or `"default"` with fragments below
- still_prompt fragment: `children's picture-book illustration, flat colors,
  thick friendly outlines, simple rounded shapes, bright primary colors,
  cheerful, uncluttered background`
- negative additions: `scary, dark, horror, gore, weapons, realistic,
  photograph, complex background`

### Band 3-5 — 3D-cartoon
- still_prompt fragment: `3D animated family film style, warm soft lighting,
  rounded friendly characters, vibrant colors, gentle depth of field`
- negative additions: `scary, horror, gore, weapons, photorealistic, gritty`

### Band 6-8 — graphic novel
- still_prompt fragment: `graphic-novel illustration, clean ink linework,
  rich flat shading, dynamic composition, muted palette with accent color`
- negative additions: `gore, explicit violence, horror, photograph`

### Band 9-12 / adult — cinematic (current default)
- still_prompt fragment: `photorealistic, cinematic lighting, film still`
- standard negative: `blurry, low quality, distorted, extra limbs, deformed
  hands, text, watermark, cartoon, oversaturated`

**Standing rules (all bands):** no on-frame text from diffusion (use SVG shots
for text); if Christ appears, face in light / unseen; visualize the *content*
being narrated, not the narrator.

## 2. Profiles (checkpoint selection)

`templates/profiles.json` maps profile name → SDXL-family checkpoint file.
Storyboard-level `"profile"` sets the reel default; per-shot `"profile"`
overrides. Unknown/absent profile = `default`.

| Profile | Checkpoint | Use |
|---------|-----------|-----|
| `default` / `photo` | sd_xl_base_1.0.safetensors | cinematic, bands 6-12 |
| `anime` | animagine-xl-4.0.safetensors | anime; bands K-8 stylized |

Anime prompting note (Animagine is tag-trained): lead with quality/style tags,
e.g. `masterpiece, high score, great score, absurdres` + danbooru-style tags,
then the scene description. Keep the standard negative plus
`lowres, bad anatomy, bad hands, error, missing fingers, jpeg artifacts, signature`.

## 3. SVG shots (crisp on-frame text, diagrams, maps, timelines)

Add `"svg": "<file>.svg"` to any `ken_burns` / `still` / `video` shot. The
exe rasterizes it (resvg) into the shot's still slot instead of running
diffusion; motion then applies as usual (ken_burns over a diagram works well).

**Authoring contract:**
- File lives in the reel's `output_dir` (the `svg` value is resolved
  against it; absolute paths also allowed).
- Root element: `<svg viewBox="0 0 1280 704" ...>` — match the reel aspect.
  The exe renders at the reel's pixel size.
- Set an explicit opaque background rect (transparent renders black in x264).
- System fonts only (`font-family="Segoe UI"` / `Georgia` / `Consolas` are
  safe); no external images, no CSS imports, no scripts.
- Text must be sized for video: body ≥ 28px at 1280-width; titles 48-72px.
- Deterministic: same file = same frame; no randomness.

## 4. Manim shots (explainer animation: math, geometry, text reveals)

`"kind": "manim", "script": "<file>.py"` — the exe runs
`python -m manim render -a` on the script with the reel's resolution and fps
and takes the produced clip as `<id>.mp4`.

**Authoring contract:**
- Script lives in `output_dir` (resolved against it; absolute OK).
- **Exactly ONE `Scene` subclass per script** (the exe renders with `-a`).
- Total animation time (sum of `self.play(run_time=...)` + `self.wait(...)`)
  **must equal the shot's `duration`**.
- Use `Text`/`MarkupText` (Pango), NOT `Tex`/`MathTex`, unless LaTeX is
  installed on the machine (it is not, by default).
- Set `self.camera.background_color` explicitly (default is black).
- No file I/O, no network, no randomness in the scene.
- The exe supplies `-r WIDTH,HEIGHT --fps FPS` from the storyboard — do not
  hardcode resolution in the script.

## 5. Blender shots (3D camera moves, environments, 2.5D parallax)

`"kind": "blender", "script": "<file>.py"` — the exe runs
`blender -b --factory-startup -P <script> -- <frames_dir> <width> <height> <fps> <duration_s>`
then encodes `frames_dir/f_####.png` to `<id>.mp4`.

**Authoring contract (the script MUST):**
- Read its five args from `sys.argv` after the `--` separator.
- Build the scene procedurally with `bpy` (primitives, lights, camera path);
  free CC0 assets may be linked only from local disk paths that exist.
- Configure: `scene.render.resolution_x/y`, `scene.render.fps`,
  `frame_start=1`, `frame_end=fps*duration`, PNG output to
  `<frames_dir>/f_` (`scene.render.filepath`), then `bpy.ops.render.render(animation=True)`.
- Engine: `BLENDER_EEVEE_NEXT` for stylized/fast (default choice);
  `CYCLES` + `scene.cycles.samples <= 64` + OptiX only when photoreal matters
  (expect minutes per shot).
- Deterministic: fixed seeds on any noise/particles.
- Keep shots ≤ ~10 s; long 3D shots belong to ken_burns over a Cycles still.

## 6. Character sheets (consistent characters across shots) — LIVE in v0.3

The production step:
1. Claude authors `characters.json`:
   ```json
   { "output_dir": "D:/reels/<reel>", "profile": "anime",
     "characters": [
       { "name": "yosef", "seed": 501,
         "spec": "1boy, a young Hebrew shepherd with short curly dark hair, ... (full verbatim description)" } ] }
   ```
2. `simple_reel characters characters.json` renders one sheet per character
   (832×1216 full body, front view, plain background, fixed seed) into
   `output_dir/characters/<name>.png`.
3. Every shot featuring the character does BOTH:
   - repeats the SAME spec text **verbatim** inside `still_prompt` (never
     paraphrase a character between shots), and
   - adds `"ref_image": "characters/<name>.png"` — IP-Adapter (plus SDXL)
     anchors the identity to the sheet.

Tuning (proven 2026-07-04): the template runs weight_type **"prompt is more
important"**, so the scene comes from the text and the look from the sheet.
`"ref_weight"` per shot: 0.4–0.5 scene-dominant, **0.55 default**, 0.7+
identity-locked but the sheet's plain background starts washing out the scene.
Same seed + same spec regenerates an identical sheet; keep sheets under the
reel's `characters/` so reels stay self-contained.

## 7. Determinism & review rules (all shot types)

- Every shot has an explicit `seed`; re-renders must reproduce.
- One sentence per prompt field; compact JSON (the storyboard is the record).
- Age-appropriateness is decided at authoring time (band fragments +
  negatives) — there is no downstream filter.
- Anything with on-frame words = SVG or Manim shot, never diffusion.
