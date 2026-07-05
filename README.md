# simple_reel

**[GitHub](https://github.com/simple-eiffel/simple_reel)**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Eiffel](https://img.shields.io/badge/Eiffel-25.02-blue.svg)](https://www.eiffel.org/)
[![Design by Contract](https://img.shields.io/badge/DbC-enforced-orange.svg)]()

Chapter-to-video render orchestrator for Eiffel — turns a markdown source and a
narration timing file into a captioned film whose visuals are timed to the spoken
word. An Eiffel console app that drives ComfyUI (Wan 2.2 i2v + SDXL stills), ffmpeg,
edge-tts, resvg, Manim and Blender from a single storyboard.

Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

**Development** — CLI orchestrator (`simple_reel.exe`), render-engine-first pipeline.

## Examples — films made with simple_reel

**[NOUS — Finding the Mind of Christ](https://www.youtube.com/playlist?list=PLc044q4oRJJw)** — a full narrated series produced entirely through this pipeline: **18 films** (an intro + 17 chapters) across two movements. Each film was authored as a markdown chapter, narrated with edge-tts (Andrew voice, Mode 1), storyboarded shot-by-shot, and rendered as timed `ken_burns` stills (SDXL) with Wan 2.2 i2v motion where it counted — then stitched and muxed by `simple_reel.exe`.

▶ **Watch the playlist:** https://www.youtube.com/playlist?list=PLc044q4oRJJw

## Features

- **Storyboard-driven render**: one `storyboard.json` describes every shot; the engine renders and stitches them in order, resuming from `manifest.json`.
- **Shot kinds**: `ken_burns` (still + ffmpeg pan/zoom), `video` (Wan 2.2 i2v ≤ 5 s), `still`, `manim` (scene scripts), `blender` (headless bpy).
- **Diffusion stills**: SDXL / Animagine XL checkpoints selected per reel or per shot via `templates/profiles.json`; or `svg:` shots rasterized by resvg for crisp on-frame text.
- **Character consistency**: reference sheets (turnaround / expression / pose) anchored through IP-Adapter for on-model characters across shots.
- **Timed narration**: edge-tts narration + drift-free integer-second scene tiling keep the picture locked to the audio.
- **4K pass**: separate streamed ffmpeg upscale of Wan clips (never in-graph).
- **Auto-start**: launches ComfyUI when it is down and waits until ready.

## Quick Start

The workflow is documented in [`RUNBOOK.md`](RUNBOOK.md). In brief:

```bat
simple_reel --help      REM full usage
simple_reel status      REM preflight: ffmpeg, curl, templates, ComfyUI, edge-tts, resvg, manim, blender
simple_reel up          REM start whatever is down and wait until ready

REM author narration.json + storyboard.json, then:
python timing.py "<out>\narration.json" "<out>\<reel>"          REM mp3 + timing.json + srt
simple_reel "<out>\storyboard.json"                             REM render all scenes
simple_reel assemble "<out>\storyboard.json" "<out>\<reel>.mp3" REM stitch + mux narration
```

`SIMPLE_REEL_HOME` overrides the install root (default `D:\prod\simple_reel`);
templates and temp files resolve against it, so the exe works from any directory.

## Building

```bat
cd simple_reel
ec -config simple_reel.ecf -target simple_reel_app -c_compile
```

Copy `EIFGENs\simple_reel_app\F_code\simple_reel.exe` to `bin\` and put `bin\` on PATH.
`bin\` and generated media (`data\output`, `data\tmp`) are gitignored — build the exe
locally or grab it from a GitHub Release.

## Installation (as an ECF library)

1. Set the environment variable:
```bat
set SIMPLE_EIFFEL=D:\prod
```

2. Add to your ECF file:
```xml
<library name="simple_reel" location="$SIMPLE_EIFFEL/simple_reel/simple_reel.ecf"/>
```

Runtime tools: ffmpeg, edge-tts (`pip install edge-tts`), ComfyUI (Wan 2.2 + SDXL),
and optionally Manim and Blender. `simple_reel status` verifies what is present.

## Targets

- `simple_reel` — library target (default)
- `simple_reel_app` — the `simple_reel` console executable
- `simple_reel_tests` — test suite (`TEST_APP`)

## Dependencies

- simple_logger, simple_http, simple_json, simple_process, simple_file, simple_datetime
- ISE base

## License

MIT License

---

Part of the **Simple Eiffel** ecosystem — modern, contract-driven Eiffel libraries.
