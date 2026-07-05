note
	description: "[
		CLI entry point. Run `simple_reel --help' for the full usage text.
			simple_reel <storyboard.json>                       render (auto-starts ComfyUI)
			simple_reel assemble <storyboard.json> [mp3]        stitch clips, mux narration
			simple_reel status | up | --help
	]"
	author: "Larry Rix"

class
	REEL_APP

inherit
	ARGUMENTS_32

create
	make

feature {NONE} -- Initialization

	make
			-- Dispatch on the command line.
		local
			l_first: STRING
		do
			if argument_count = 0 then
				print_help
			else
				l_first := argument (1).to_string_8
				if l_first.is_case_insensitive_equal ("--help") or
				   l_first.is_case_insensitive_equal ("-h") or
				   l_first.is_case_insensitive_equal ("help") then
					print_help
				elseif l_first.is_case_insensitive_equal ("status") then
					do_status
				elseif l_first.is_case_insensitive_equal ("up") then
					do_up
				elseif l_first.is_case_insensitive_equal ("assemble") then
					do_assemble
				elseif l_first.is_case_insensitive_equal ("characters") then
					do_characters
				else
					do_render (l_first)
				end
			end
		end

feature {NONE} -- Modes

	do_status
			-- Print the toolchain checklist without starting anything.
		local
			l_doc: REEL_DOCTOR
		do
			create l_doc.make (app_root)
			io.put_string ("simple_reel toolchain status:%N")
			l_doc.report
		end

	do_up
			-- Bring the environment up (start ComfyUI if down), then report.
		local
			l_doc: REEL_DOCTOR
		do
			create l_doc.make (app_root)
			if l_doc.ensure_comfy_up (Comfy_wait_seconds) then
				io.put_string ("ComfyUI is up.%N%N")
			else
				io.put_string ("ComfyUI did not come up -- check its console window.%N%N")
			end
			l_doc.report
		end

	do_assemble
			-- Stitch a reel's rendered clips into one film (optionally with narration).
		local
			l_sb: REEL_STORYBOARD
			l_asm: REEL_ASSEMBLER
			l_out: STRING
			l_audio: detachable STRING
		do
			if argument_count < 2 then
				io.put_string ("usage: simple_reel assemble <storyboard.json> [narration.mp3]%N")
			else
				create l_sb.make_from_file (argument (2).to_string_8)
				if not l_sb.is_valid then
					io.put_string ("cannot load storyboard: " + l_sb.last_error + "%N")
				else
					create l_asm.make (l_sb)
					if argument_count >= 3 then
						l_audio := argument (3).to_string_8
						l_out := l_sb.output_dir + "/" + l_sb.reel_name + "_narrated.mp4"
					else
						l_out := l_sb.output_dir + "/" + l_sb.reel_name + ".mp4"
					end
					io.put_string ("Assembling " + l_sb.reel_name + " in storyboard order...%N")
					if l_asm.assemble (l_out, l_audio) then
						io.put_string ("Wrote " + l_out + " (" + l_asm.clip_count.out + " clips stitched)%N")
					else
						io.put_string ("assemble failed: " + l_asm.last_error + "%N")
					end
				end
			end
		end

	do_characters
			-- Render the character reference sheets listed in a characters.json.
		local
			l_doc: REEL_DOCTOR
			l_pipe: detachable REEL_PIPELINE
			l_ok: BOOLEAN
		do
			if argument_count < 2 then
				io.put_string ("usage: simple_reel characters <characters.json>%N")
			else
				create l_doc.make (app_root)
				if l_doc.ensure_comfy_up (Comfy_wait_seconds) then
					l_pipe := new_pipeline (l_doc)
					if attached l_pipe as lp then
						l_ok := lp.render_characters (argument (2).to_string_8)
						if not l_ok then
							io.put_string ("characters run incomplete -- see messages above.%N")
						end
					end
				else
					io.put_string ("ComfyUI could not be started -- run `simple_reel status'.%N")
				end
			end
		end

	do_render (a_path: STRING)
			-- Load and render the storyboard at `a_path'. ComfyUI is brought up first
			-- only when a shot actually needs it (diffusion still or Wan video) --
			-- pure SVG/manim/blender reels render with the server down.
		local
			l_sb: REEL_STORYBOARD
			l_doc: REEL_DOCTOR
			l_pipe: detachable REEL_PIPELINE
			l_comfy_ok: BOOLEAN
		do
			create l_sb.make_from_file (a_path)
			if not l_sb.is_valid then
				io.put_string ("cannot load storyboard: " + l_sb.last_error + "%N")
			else
				create l_doc.make (app_root)
				if l_sb.needs_comfy then
					l_comfy_ok := l_doc.ensure_comfy_up (Comfy_wait_seconds)
				else
					l_comfy_ok := True
					io.put_string ("(no diffusion/video shots -- ComfyUI not required)%N")
				end
				if l_comfy_ok then
					l_pipe := new_pipeline (l_doc)
					if attached l_pipe as lp then
						lp.run (l_sb)
					end
				else
					io.put_string ("ComfyUI could not be started -- run `simple_reel status' to see what is missing.%N")
				end
			end
		end

	new_pipeline (a_doc: REEL_DOCTOR): detachable REEL_PIPELINE
			-- Pipeline wired with templates, profiles and tool paths; Void (with a
			-- message printed) when the core templates are missing.
		local
			l_still, l_video, l_ref: MODEL_PROFILE
		do
			create l_still.make_from_file ("sdxl_still", app_root + "\templates\sdxl_still.json")
			create l_video.make_from_file ("wan_i2v", app_root + "\templates\wan_i2v.json")
			if l_still.is_loaded and l_video.is_loaded then
				create Result.make (a_doc.client, l_still, l_video)
				Result.load_profiles (app_root + "\templates\profiles.json")
				Result.set_resvg_exe (app_root + "\tools\resvg.exe")
				create l_ref.make_from_file ("sdxl_still_ref", app_root + "\templates\sdxl_still_ref.json")
				if l_ref.is_loaded then
					Result.set_ref_still_profile (l_ref)
				end
			else
				io.put_string ("template(s) missing under " + app_root + "\templates%N")
			end
		end

feature {NONE} -- Help

	print_help
			-- Full usage text.
		do
			io.put_string ("simple_reel " + {SIMPLE_REEL}.version + " -- chapter-to-video render orchestrator over ComfyUI%N%N")
			io.put_string ("USAGE%N")
			io.put_string ("  simple_reel <storyboard.json>              render every scene; skips finished ones%N")
			io.put_string ("                                             (manifest.json); auto-starts ComfyUI if down%N")
			io.put_string ("  simple_reel assemble <storyboard.json> [narration.mp3]%N")
			io.put_string ("                                             stitch rendered clips in storyboard order;%N")
			io.put_string ("                                             mux the narration when given%N")
			io.put_string ("  simple_reel characters <characters.json>   render character reference sheets into%N")
			io.put_string ("                                             <output_dir>\characters\<name>.png -- shots%N")
			io.put_string ("                                             then anchor identity via their ref_image key%N")
			io.put_string ("  simple_reel status                         check the toolchain; starts nothing%N")
			io.put_string ("  simple_reel up                             start whatever is down (ComfyUI), wait ready%N")
			io.put_string ("  simple_reel --help                         this text%N%N")
			io.put_string ("TYPICAL WORKFLOW (details: D:\prod\simple_reel\RUNBOOK.md)%N")
			io.put_string ("  Claude (in a Claude Code session) authors the creative files; this exe does the rest.%N")
			io.put_string ("  1. narration.json   authored by Claude from your source MD (mode 1 as-is / mode 2 podcast)%N")
			io.put_string ("  2. python D:\prod\simple_reel\timing.py <dir>\narration.json <dir>\<reel>%N")
			io.put_string ("                      -> <reel>.mp3 + <reel>.timing.json + <reel>.srt%N")
			io.put_string ("  3. storyboard.json  authored by Claude, scene durations timed to <reel>.timing.json%N")
			io.put_string ("                      (or scaffolded: python make_storyboard.py <timing> <out> <reel> <dir> <prompts>)%N")
			io.put_string ("  4. simple_reel <dir>\storyboard.json%N")
			io.put_string ("  5. simple_reel assemble <dir>\storyboard.json <dir>\<reel>.mp3%N")
			io.put_string ("  6. captions: keep <reel>.srt beside the final mp4 (players auto-load it)%N%N")
			io.put_string ("SHOT KINDS AND SOURCES (docs\STYLE_GUIDES.md has the authoring contracts)%N")
			io.put_string ("  kind: ken_burns | video (Wan i2v) | still | manim (scene .py) | blender (bpy .py)%N")
			io.put_string ("  still source: diffusion prompt (checkpoint via profile/profiles.json) or svg: <file>%N")
			io.put_string ("  identity: ref_image: characters\<name>.png (IP-Adapter; sheets from `characters' mode)%N%N")
			io.put_string ("PYTHON HELPERS (run with the system python; NOT called by this exe)%N")
			io.put_string ("  timing.py           narration.json -> mp3 + timing.json + srt (pip install edge-tts; ffmpeg)%N")
			io.put_string ("  make_storyboard.py  scaffold a drift-free storyboard.json from timing.json + prompts.json%N")
			io.put_string ("  resmooth.py         regenerate ken_burns clips from existing stills (no GPU), then re-assemble%N%N")
			io.put_string ("NEEDS (no AI/API key -- Claude-in-session authors the JSON, the exe is pure render)%N")
			io.put_string ("  ComfyUI at http://127.0.0.1:8188 (render only; auto-started from D:\AI\ComfyUI_windows_portable)%N")
			io.put_string ("  ffmpeg and curl on PATH; templates\ under the install root%N")
			io.put_string ("  install root: D:\prod\simple_reel (override with SIMPLE_REEL_HOME)%N")
		end

feature {NONE} -- Environment

	app_root: STRING
			-- Install root: SIMPLE_REEL_HOME when set, else D:\prod\simple_reel.
			-- Templates and the client's temp dir resolve against this, so the exe
			-- works from any current directory (e.g. launched from bin\ on PATH).
		local
			l_env: EXECUTION_ENVIRONMENT
		once
			create l_env
			if attached l_env.item ("SIMPLE_REEL_HOME") as h and then not h.is_empty then
				Result := h.to_string_8
			else
				Result := "D:\prod\simple_reel"
			end
		ensure
			result_attached: Result /= Void and then not Result.is_empty
		end

	Comfy_wait_seconds: INTEGER = 180
			-- How long to wait for a freshly launched ComfyUI to answer.

end
