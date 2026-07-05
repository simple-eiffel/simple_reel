note
	description: "[
		The conductor. Walks a REEL_STORYBOARD scene by scene: produce the still
		(diffusion via ComfyUI -- checkpoint chosen per shot `profile' -- or a
		Claude-authored SVG rasterized by resvg), then bring it to life per `kind'
		(Wan i2v for key beats, ffmpeg Ken Burns pan/zoom for the rest, Manim or
		Blender scripts for explainer/3D shots, or leave it as a still). Emits each
		scene as it finishes, prints live progress (elapsed + ETA), and records a
		resume manifest so a re-run skips done shots.
	]"
	author: "Larry Rix"

class
	REEL_PIPELINE

create
	make

feature {NONE} -- Initialization

	make (a_client: COMFY_CLIENT; a_still, a_video: MODEL_PROFILE)
			-- Pipeline driving `a_client' with a still profile and an i2v profile.
		require
			still_loaded: a_still.is_loaded
			video_loaded: a_video.is_loaded
		do
			client := a_client
			still_profile := a_still
			video_profile := a_video
			comfy_input_dir := "D:/AI/ComfyUI_windows_portable/ComfyUI/input"
			python_exe := "D:/AI/ComfyUI_windows_portable/python_embeded/python.exe"
			upscaler_script := "D:/AI/upscale_video_4k.py"
			resvg_exe := "D:\prod\simple_reel\tools\resvg.exe"
			blender_exe := "D:\AI\blender\blender.exe"
			python_cmd := "python"
			still_steps := "20"
			video_steps := "20"
			create done_ids.make (32)
			done_ids.compare_objects
			create checkpoint_map.make (4)
			checkpoint_map.compare_objects
			create cur_default_profile.make_empty
		end

feature -- Access

	client: COMFY_CLIENT
	still_profile: MODEL_PROFILE
	video_profile: MODEL_PROFILE
	comfy_input_dir: STRING
	python_exe: STRING
	upscaler_script: STRING
	resvg_exe: STRING
	blender_exe: STRING
	python_cmd: STRING
	still_steps: STRING
	video_steps: STRING

	checkpoint_map: HASH_TABLE [STRING, STRING]
			-- profile name -> checkpoint filename (from templates/profiles.json).

	ref_still_profile: detachable MODEL_PROFILE
			-- IP-Adapter still template (identity-anchored stills); Void when the
			-- template or the IP-Adapter models are not installed.

feature -- Settings

	set_comfy_input_dir (a_dir: STRING)
		require not_empty: not a_dir.is_empty
		do comfy_input_dir := a_dir end

	set_video_steps (a_steps: STRING)
		require not_empty: not a_steps.is_empty
		do video_steps := a_steps end

	set_resvg_exe (a_path: STRING)
		require not_empty: not a_path.is_empty
		do resvg_exe := a_path end

	set_blender_exe (a_path: STRING)
		require not_empty: not a_path.is_empty
		do blender_exe := a_path end

	set_ref_still_profile (a_profile: MODEL_PROFILE)
		require loaded: a_profile.is_loaded
		do ref_still_profile := a_profile end

	load_profiles (a_path: STRING)
			-- Load the profile -> checkpoint map from the JSON object at `a_path'.
		require
			path_not_empty: not a_path.is_empty
		local
			l_file: SIMPLE_FILE
			l_json: SIMPLE_JSON
		do
			create l_file.make (native (a_path))
			if l_file.exists then
				create l_json
				if attached l_json.parse (l_file.content) as parsed and then
				   attached parsed.as_object as obj then
					across obj.keys as ic loop
						if attached obj.string_item (ic) as v then
							checkpoint_map.force (v.to_string_8, ic.to_string_8)
						end
					end
				end
			end
		end

feature -- Run

	run (a_sb: REEL_STORYBOARD)
			-- Render `a_sb' in two phases -- all visual sources (stills), then all
			-- motion -- so the GPU loads each checkpoint once and Wan once, instead
			-- of thrashing between models. SVG stills rasterize locally; manim and
			-- blender shots need no still and render entirely in Phase 2.
		require
			valid: a_sb.is_valid
		local
			l_out_dir, l_manifest: STRING
			l_run_start, l_phase_start, l_scene_start: INTEGER
			l_pending: ARRAYED_LIST [REEL_SHOT]
			l_names: HASH_TABLE [STRING, STRING]
			l_ckpts: ARRAYED_LIST [STRING]
			l_ck: STRING
			l_shot: REEL_SHOT
			k, c, l_p, l_stills, l_s, l_done: INTEGER
			l_name: detachable STRING
		do
			cur_width := a_sb.width
			cur_height := a_sb.height
			cur_fps := a_sb.fps
			cur_default_profile := a_sb.default_profile
			l_out_dir := a_sb.output_dir
			ensure_dir (l_out_dir)
			ensure_dir (comfy_input_dir)
			l_manifest := l_out_dir + "/manifest.json"
			load_manifest (l_manifest)
			l_run_start := now_secs

			say ("==== simple_reel :: " + a_sb.reel_name + " ====%N")
			say ("scenes : " + a_sb.count.out + "   size : " + cur_width.out + "x" + cur_height.out + " @ " + cur_fps.out + "fps%N")
			say ("output : " + l_out_dir + "%N")

			create l_pending.make (a_sb.count)
			from k := 1 until k > a_sb.count loop
				l_shot := a_sb.shots.i_th (k)
				if not done_ids.has (l_shot.id) then
					l_pending.extend (l_shot)
				end
				k := k + 1
			end
			l_p := l_pending.count
			say ("resume : " + done_ids.count.out + " done, " + l_p.out + " to render%N%N")

			if l_p > 0 then
				create l_names.make (l_p)
				l_stills := 0
				across l_pending as ic_shot loop
					if not ic_shot.is_scripted then
						l_stills := l_stills + 1
					end
				end

					-- Phase 1: every still. SVG shots rasterize locally (no GPU);
					-- diffusion shots run grouped by checkpoint so each model loads once.
				say ("---- Phase 1 : stills (" + l_stills.out + ") ----%N")
				l_phase_start := now_secs
				l_s := 0
				from k := 1 until k > l_pending.count loop
					l_shot := l_pending.i_th (k)
					if l_shot.has_svg then
						l_s := l_s + 1
						say ("[still " + l_s.out + "/" + l_stills.out + "] " + l_shot.id + " (" + l_shot.section + ") svg ... ")
						l_name := rasterize_svg (l_shot, l_out_dir)
						if attached l_name as nm then
							l_names.put (nm, l_shot.id)
						end
					end
					k := k + 1
				end
					-- distinct checkpoints, in first-appearance order
				create l_ckpts.make (2)
				l_ckpts.compare_objects
				from k := 1 until k > l_pending.count loop
					l_shot := l_pending.i_th (k)
					if l_shot.needs_diffusion_still then
						l_ck := checkpoint_for (l_shot)
						if not l_ckpts.has (l_ck) then
							l_ckpts.extend (l_ck)
						end
					end
					k := k + 1
				end
				from c := 1 until c > l_ckpts.count loop
					l_ck := l_ckpts.i_th (c)
					if l_ckpts.count > 1 then
						say ("-- checkpoint: " + l_ck + "%N")
					end
					from k := 1 until k > l_pending.count loop
						l_shot := l_pending.i_th (k)
						if l_shot.needs_diffusion_still and then checkpoint_for (l_shot).same_string (l_ck) then
							l_s := l_s + 1
							say ("[still " + l_s.out + "/" + l_stills.out + "] " + l_shot.id + " (" + l_shot.section + ") ... ")
							l_name := render_still (l_shot, seed_for (l_shot, k), l_out_dir)
							if attached l_name as nm then
								l_names.put (nm, l_shot.id)
							else
								say ("FAIL: " + client.last_error + "%N")
							end
						end
						k := k + 1
					end
					c := c + 1
				end
				say ("stills done in " + fmt (elapsed (l_phase_start)) + "%N%N")

					-- Phase 2: motion (Wan loads once for the video shots; ffmpeg,
					-- manim and blender need no ComfyUI model).
				say ("---- Phase 2 : motion (" + l_p.out + ") ----%N")
				l_phase_start := now_secs
				l_done := 0
				from k := 1 until k > l_pending.count loop
					l_shot := l_pending.i_th (k)
					if l_shot.is_scripted or else l_names.has (l_shot.id) then
						l_scene_start := now_secs
						say ("[" + k.out + "/" + l_p.out + "] " + l_shot.id + " (" + l_shot.section + ") :: " + l_shot.kind + "%N")
						if l_shot.is_manim then
							process_manim (l_shot, l_out_dir)
						elseif l_shot.is_blender then
							process_blender (l_shot, l_out_dir)
						elseif l_shot.is_video and then attached l_names.item (l_shot.id) as img then
							process_video (l_shot, img, seed_for (l_shot, k), l_out_dir)
						elseif l_shot.is_ken_burns then
							process_ken_burns (l_shot, l_out_dir)
						else
							say ("  still only%N")
						end
						mark_done (l_shot.id, l_manifest)
						l_done := l_done + 1
						report_progress (l_scene_start, l_phase_start, l_done, l_p)
					else
						say ("[" + k.out + "/" + l_p.out + "] " + l_shot.id + " -- still failed, skipping motion%N%N")
					end
					k := k + 1
				end
			else
				say ("nothing to render.%N")
			end
			say ("==== REEL COMPLETE in " + fmt (elapsed (l_run_start)) + " :: " + l_out_dir + " ====%N")
		end

feature -- Character sheets

	render_characters (a_path: STRING): BOOLEAN
			-- Render one reference sheet per character listed in the JSON at `a_path'
			-- into <output_dir>/characters/<name>.png -- full-body portrait, fixed
			-- seed, per-character (or file-level) checkpoint profile. These sheets
			-- anchor later shots via the `ref_image' field. True when all rendered.
		require
			path_not_empty: not a_path.is_empty
		local
			l_file: SIMPLE_FILE
			l_json: SIMPLE_JSON
			l_out_dir, l_default_profile, l_name, l_spec, l_neg, l_prof: STRING
			l_bind: HASH_TABLE [STRING, STRING]
			l_pid: detachable STRING
			l_files: ARRAYED_LIST [COMFY_OUTPUT_FILE]
			i, l_seed, l_ok, l_total, t0: INTEGER
		do
			create l_file.make (native (a_path))
			if not l_file.exists then
				say ("characters file not found: " + a_path + "%N")
			else
				create l_json
				if attached l_json.parse (l_file.content) as parsed and then
				   attached parsed.as_object as obj and then
				   attached obj.string_item (({STRING_32} "output_dir")) as od and then not od.is_empty and then
				   attached obj.array_item (({STRING_32} "characters")) as arr then
					l_out_dir := od.to_string_8
					l_default_profile := ""
					if attached obj.string_item (({STRING_32} "profile")) as pr then
						l_default_profile := pr.to_string_8
					end
					ensure_dir (l_out_dir + "/characters")
					l_total := arr.count
					from i := 1 until i > arr.count loop
						if attached arr.object_item (i) as co and then
						   attached co.string_item (({STRING_32} "name")) as nm and then
						   attached co.string_item (({STRING_32} "spec")) as sp then
							l_name := nm.to_string_8
							l_spec := sp.to_string_8
							l_seed := co.integer_32_item (({STRING_32} "seed"))
							if l_seed = 0 then
								l_seed := 500 + i
							end
							l_prof := l_default_profile
							if attached co.string_item (({STRING_32} "profile")) as cp and then not cp.is_empty then
								l_prof := cp.to_string_8
							end
							l_neg := "blurry, low quality, distorted, extra limbs, deformed hands, text, watermark, multiple people, cropped"
							if attached co.string_item (({STRING_32} "negative")) as ng and then not ng.is_empty then
								l_neg := ng.to_string_8
							end
							t0 := now_secs
							say ("[char " + i.out + "/" + l_total.out + "] " + l_name + " ... ")
							create l_bind.make (9)
							l_bind.put (l_spec + ", character reference sheet, full body, standing, front view, neutral expression, plain neutral background, even lighting", "POSITIVE")
							l_bind.put (l_neg, "NEGATIVE")
							l_bind.put ("832", "WIDTH")
							l_bind.put ("1216", "HEIGHT")
							l_bind.put (l_seed.out, "SEED")
							l_bind.put (still_steps, "STEPS")
							l_bind.put (checkpoint_for_profile (l_prof), "CHECKPOINT")
							l_bind.put ("reel_char_" + l_name, "PREFIX")
							l_pid := client.submit_prompt (still_profile.render (l_bind))
							if attached l_pid as lp and then client.wait_for (lp, 300) then
								l_files := client.output_files (lp)
								if not l_files.is_empty and then
								   client.fetch_file (l_files.first, l_out_dir + "/characters/" + l_name + ".png") then
									l_ok := l_ok + 1
									say ("OK " + fmt (elapsed (t0)) + " -> characters/" + l_name + ".png%N")
								else
									say ("FAIL fetch%N")
								end
							else
								say ("FAIL: " + client.last_error + "%N")
							end
						end
						i := i + 1
					end
					say (l_ok.out + "/" + l_total.out + " character sheets in " + l_out_dir + "/characters%N")
					Result := l_ok = l_total and l_total > 0
				else
					say ("invalid characters JSON (needs output_dir + characters[])%N")
				end
			end
		end

feature {NONE} -- Scene stages

	render_still (a_shot: REEL_SHOT; a_seed: INTEGER; a_out_dir: STRING): detachable STRING
			-- Render the still, copy it into ComfyUI input/ (for i2v) and into `a_out_dir'.
			-- When the shot names a `ref_image' (and the IP-Adapter template is loaded)
			-- the still is identity-anchored to that reference.
			-- Returns the still's input-relative filename, or Void on failure.
		local
			l_bind: HASH_TABLE [STRING, STRING]
			l_pid: detachable STRING
			l_files: ARRAYED_LIST [COMFY_OUTPUT_FILE]
			l_proc: SIMPLE_PROCESS
			l_ref_name: STRING
			t0: INTEGER
		do
			t0 := now_secs
			create l_bind.make (11)
			l_bind.put (a_shot.still_prompt, "POSITIVE")
			l_bind.put (a_shot.negative, "NEGATIVE")
			l_bind.put (cur_width.out, "WIDTH")
			l_bind.put (cur_height.out, "HEIGHT")
			l_bind.put (a_seed.out, "SEED")
			l_bind.put (still_steps, "STEPS")
			l_bind.put (checkpoint_for (a_shot), "CHECKPOINT")
			l_bind.put ("reel_" + a_shot.id + "_still", "PREFIX")
			if not a_shot.ref_image.is_empty and then attached ref_still_profile as rp then
				l_ref_name := "reel_ref_" + a_shot.id + ".png"
				create l_proc.make
				l_proc.execute ("cmd /c copy /Y %"" + native (resolve (a_shot.ref_image, a_out_dir)) +
					"%" %"" + native (comfy_input_dir + "/" + l_ref_name) + "%"")
				l_bind.put (l_ref_name, "REF_IMAGE")
				l_bind.put (weight_text (a_shot.ref_weight), "REF_WEIGHT")
				l_pid := client.submit_prompt (rp.render (l_bind))
			else
				l_pid := client.submit_prompt (still_profile.render (l_bind))
			end
			if attached l_pid as lp and then client.wait_for (lp, 300) then
				l_files := client.output_files (lp)
				if not l_files.is_empty and then
				   client.fetch_file (l_files.first, comfy_input_dir + "/" + l_files.first.filename) and then
				   client.fetch_file (l_files.first, a_out_dir + "/" + a_shot.id + "_still.png") then
					Result := l_files.first.filename
					say ("OK " + fmt (elapsed (t0)) + " -> " + a_shot.id + "_still.png%N")
				end
			end
		end

	process_video (a_shot: REEL_SHOT; a_image: STRING; a_seed: INTEGER; a_out_dir: STRING)
			-- Wan image-to-video from the still, then 4K upscale.
		local
			l_bind: HASH_TABLE [STRING, STRING]
			l_pid: detachable STRING
			l_files: ARRAYED_LIST [COMFY_OUTPUT_FILE]
			l_clip: STRING
			t0: INTEGER
		do
			t0 := now_secs
			say ("  video  ... (wan i2v, this takes minutes) ")
			create l_bind.make (10)
			l_bind.put (a_shot.motion_prompt, "POSITIVE")
			l_bind.put (a_shot.negative, "NEGATIVE")
			l_bind.put (a_image, "IMAGE")
			l_bind.put (cur_width.out, "WIDTH")
			l_bind.put (cur_height.out, "HEIGHT")
			l_bind.put ((a_shot.duration * cur_fps + 1).out, "LENGTH")
			l_bind.put (a_seed.out, "SEED")
			l_bind.put (video_steps, "STEPS")
			l_bind.put (cur_fps.out, "FPS")
			l_bind.put ("reel_" + a_shot.id, "PREFIX")
			l_pid := client.submit_prompt (video_profile.render (l_bind))
			if attached l_pid as lp and then client.wait_for (lp, 1800) then
				l_files := client.output_files (lp)
				if not l_files.is_empty then
					l_clip := a_out_dir + "/" + a_shot.id + ".mp4"
					if client.fetch_file (l_files.first, l_clip) then
						say ("OK " + fmt (elapsed (t0)) + " -> " + a_shot.id + ".mp4%N")
						upscale_clip (l_clip)
					else
						say ("FAIL fetch clip%N")
					end
				end
			else
				say ("FAIL i2v: " + client.last_error + "%N")
			end
		end

	rasterize_svg (a_shot: REEL_SHOT; a_out_dir: STRING): detachable STRING
			-- Rasterize the shot's SVG into its still slot (resvg), and copy it into
			-- ComfyUI input/ (for i2v). Returns the input-relative filename, or Void.
		require
			has_svg: a_shot.has_svg
		local
			l_proc: SIMPLE_PROCESS
			l_svg, l_png, l_input_name: STRING
			l_file: SIMPLE_FILE
			t0: INTEGER
		do
			t0 := now_secs
			l_svg := resolve (a_shot.svg_file, a_out_dir)
			create l_file.make (native (l_svg))
			if not l_file.exists then
				say ("FAIL svg not found: " + l_svg + "%N")
			else
				l_png := a_out_dir + "/" + a_shot.id + "_still.png"
				create l_proc.make
				l_proc.execute ("%"" + resvg_exe + "%" --width " + cur_width.out +
					" --height " + cur_height.out +
					" %"" + native (l_svg) + "%" %"" + native (l_png) + "%"")
				create l_file.make (native (l_png))
				if l_proc.was_successful and then l_file.exists then
					l_input_name := "reel_" + a_shot.id + "_still.png"
					create l_proc.make
					l_proc.execute ("cmd /c copy /Y %"" + native (l_png) + "%" %"" +
						native (comfy_input_dir + "/" + l_input_name) + "%"")
					Result := l_input_name
					say ("OK " + fmt (elapsed (t0)) + " -> " + a_shot.id + "_still.png%N")
				else
					say ("FAIL resvg (exit " + l_proc.last_exit_code.out + ")%N")
				end
			end
		end

	process_manim (a_shot: REEL_SHOT; a_out_dir: STRING)
			-- Run the shot's Manim scene script (one Scene class, rendered with -a at
			-- the reel's size/fps) and take the produced movie as <id>.mp4.
		require
			manim_shot: a_shot.is_manim
			has_script: not a_shot.script.is_empty
		local
			l_proc: SIMPLE_PROCESS
			l_script, l_media, l_clip, l_found: STRING
			l_out: STRING_32
			t0: INTEGER
		do
			t0 := now_secs
			say ("  manim  ... ")
			l_script := resolve (a_shot.script, a_out_dir)
			l_media := a_out_dir + "/" + a_shot.id + "_manim"
			create l_proc.make
			l_out := l_proc.command_output (python_cmd + " -m manim render -a -q h --fps " + cur_fps.out +
				" -r " + cur_width.out + "," + cur_height.out +
				" --media_dir %"" + native (l_media) + "%" %"" + native (l_script) + "%"")
			if l_proc.was_successful then
				l_found := find_first_mp4 (l_media)
				if not l_found.is_empty then
					l_clip := a_out_dir + "/" + a_shot.id + ".mp4"
					create l_proc.make
					l_proc.execute ("cmd /c copy /Y %"" + native (l_found) + "%" %"" + native (l_clip) + "%"")
					if l_proc.was_successful then
						say ("OK " + fmt (elapsed (t0)) + " -> " + a_shot.id + ".mp4%N")
					else
						say ("FAIL copying manim clip%N")
					end
				else
					say ("FAIL no mp4 under " + l_media + "%N")
				end
			else
				say ("FAIL manim (exit " + l_proc.last_exit_code.out + ")%N")
			end
		end

	process_blender (a_shot: REEL_SHOT; a_out_dir: STRING)
			-- Run the shot's bpy script headless. The script honors the argv contract
			-- (after `--': frames_dir width height fps duration_s) and renders PNG
			-- frames named f_#### into frames_dir; then encode them as <id>.mp4.
		require
			blender_shot: a_shot.is_blender
			has_script: not a_shot.script.is_empty
		local
			l_proc: SIMPLE_PROCESS
			l_script, l_frames, l_clip: STRING
			l_out: STRING_32
			t0: INTEGER
		do
			t0 := now_secs
			say ("  blender... (headless render, may take a while) ")
			l_script := resolve (a_shot.script, a_out_dir)
			l_frames := a_out_dir + "/" + a_shot.id + "_frames"
			ensure_dir (l_frames)
			create l_proc.make
			l_out := l_proc.command_output ("%"" + blender_exe + "%" -b --factory-startup -P %"" +
				native (l_script) + "%" -- %"" + native (l_frames) + "%" " +
				cur_width.out + " " + cur_height.out + " " + cur_fps.out + " " + a_shot.duration.out)
			if l_proc.was_successful then
				l_clip := a_out_dir + "/" + a_shot.id + ".mp4"
				create l_proc.make
				l_proc.execute ("ffmpeg -y -framerate " + cur_fps.out + " -i %"" + l_frames +
					"/f_%%04d.png%" -c:v libx264 -pix_fmt yuv420p -crf 18 %"" + l_clip + "%"")
				if l_proc.was_successful then
					say ("OK " + fmt (elapsed (t0)) + " -> " + a_shot.id + ".mp4%N")
				else
					say ("FAIL encoding frames (exit " + l_proc.last_exit_code.out + ")%N")
				end
			else
				say ("FAIL blender (exit " + l_proc.last_exit_code.out + ")%N")
			end
		end

	process_ken_burns (a_shot: REEL_SHOT; a_out_dir: STRING)
			-- Turn the still into a moving clip with ffmpeg pan/zoom.
		local
			l_proc: SIMPLE_PROCESS
			l_in, l_out: STRING
			t0: INTEGER
		do
			t0 := now_secs
			say ("  motion ... (ken burns " + a_shot.motion + ") ")
			l_in := a_out_dir + "/" + a_shot.id + "_still.png"
			l_out := a_out_dir + "/" + a_shot.id + ".mp4"
			create l_proc.make
			l_proc.execute (ken_burns_command (l_in, l_out, a_shot.motion, a_shot.duration))
			if l_proc.was_successful then
				say ("OK " + fmt (elapsed (t0)) + " -> " + a_shot.id + ".mp4%N")
			else
				say ("FAIL ffmpeg (exit " + l_proc.last_exit_code.out + ")%N")
			end
		end

	upscale_clip (a_clip: STRING)
			-- Run the external 4K upscaler on `a_clip'.
		local
			l_proc: SIMPLE_PROCESS
			t0: INTEGER
		do
			t0 := now_secs
			say ("  4K     ... ")
			create l_proc.make
			l_proc.execute ("%"" + python_exe + "%" %"" + upscaler_script + "%" %"" + a_clip + "%"")
			if l_proc.was_successful then
				say ("OK " + fmt (elapsed (t0)) + "%N")
			else
				say ("SKIP (upscale failed)%N")
			end
		end

feature {NONE} -- ffmpeg Ken Burns

	ken_burns_command (a_in, a_out, a_motion: STRING; a_duration: INTEGER): STRING
			-- ffmpeg command that pans/zooms the still `a_in' into `a_out'.
		local
			l_n, l_sw, l_sh: INTEGER
			l_z, l_x, l_y, l_vf, l_nn: STRING
		do
			l_n := a_duration * cur_fps
			l_nn := l_n.out
				-- Supersample the still 4x before zoompan so its integer-pixel crop steps
				-- become sub-output-pixel: this removes the slow-pan "stair-step" jerk.
			l_sw := cur_width * 4
			l_sh := cur_height * 4
			if a_motion.is_case_insensitive_equal ("push_out") then
				l_z := "if(eq(on,0),1.2,max(1.2-0.2*on/" + l_nn + ",1.0))"
				l_x := "iw/2-iw/zoom/2"
				l_y := "ih/2-ih/zoom/2"
			elseif a_motion.is_case_insensitive_equal ("pan_left") then
				l_z := "1.15"
				l_x := "(iw-iw/zoom)*(1-on/" + l_nn + ")"
				l_y := "ih/2-ih/zoom/2"
			elseif a_motion.is_case_insensitive_equal ("pan_right") then
				l_z := "1.15"
				l_x := "(iw-iw/zoom)*(on/" + l_nn + ")"
				l_y := "ih/2-ih/zoom/2"
			elseif a_motion.is_case_insensitive_equal ("pan_up") then
				l_z := "1.15"
				l_x := "iw/2-iw/zoom/2"
				l_y := "(ih-ih/zoom)*(1-on/" + l_nn + ")"
			elseif a_motion.is_case_insensitive_equal ("pan_down") then
				l_z := "1.15"
				l_x := "iw/2-iw/zoom/2"
				l_y := "(ih-ih/zoom)*(on/" + l_nn + ")"
			else
				l_z := "min(1.0+0.2*on/" + l_nn + ",1.2)"
				l_x := "iw/2-iw/zoom/2"
				l_y := "ih/2-ih/zoom/2"
			end
			l_vf := "scale=" + l_sw.out + ":" + l_sh.out + ":flags=lanczos,zoompan=z='" + l_z +
				"':x='" + l_x + "':y='" + l_y + "':d=" + l_nn +
				":s=" + cur_width.out + "x" + cur_height.out + ":fps=" + cur_fps.out
			Result := "ffmpeg -y -loop 1 -i %"" + a_in + "%" -vf %"" + l_vf +
				"%" -frames:v " + l_nn + " -c:v libx264 -pix_fmt yuv420p -crf 18 %"" + a_out + "%""
		end

feature {NONE} -- Progress

	report_progress (a_scene_start, a_run_start, a_done, a_total: INTEGER)
			-- Print scene time, running elapsed, average and ETA.
		local
			l_elapsed, l_avg, l_eta: INTEGER
		do
			l_elapsed := elapsed (a_run_start)
			if a_done > 0 then
				l_avg := l_elapsed // a_done
			end
			l_eta := l_avg * (a_total - a_done)
			say ("  scene " + fmt (elapsed (a_scene_start)) +
				" | elapsed " + fmt (l_elapsed) +
				" | avg/scene " + fmt (l_avg) +
				" | eta ~" + fmt (l_eta) +
				"  (" + a_done.out + "/" + a_total.out + ")%N%N")
		end

	say (a_msg: STRING)
			-- Print `a_msg' immediately (flushed).
		do
			io.put_string (a_msg)
			io.output.flush
		end

feature {NONE} -- Manifest

	done_ids: ARRAYED_LIST [STRING]
			-- Ids of shots already rendered.

	load_manifest (a_path: STRING)
			-- Populate `done_ids' from a prior run, if any.
		local
			l_file: SIMPLE_FILE
			l_json: SIMPLE_JSON
			i: INTEGER
		do
			create l_file.make (native (a_path))
			if l_file.exists then
				create l_json
				if attached l_json.parse (l_file.content) as parsed and then
				   attached parsed.as_object as obj and then
				   attached obj.array_item (({STRING_32} "done")) as arr then
					from i := 1 until i > arr.count loop
						if attached arr.string_item (i) as s then
							done_ids.extend (s.to_string_8)
						end
						i := i + 1
					end
				end
			end
		end

	mark_done (a_id, a_path: STRING)
			-- Record `a_id' as done and persist the manifest.
		local
			l_file: SIMPLE_FILE
			l_json: STRING
			l_first: BOOLEAN
			l_ok: BOOLEAN
		do
			done_ids.extend (a_id)
			l_json := "{" + q ("done") + ":["
			l_first := True
			across done_ids as ic loop
				if not l_first then
					l_json.append (",")
				end
				l_json.append (q (ic))
				l_first := False
			end
			l_json.append ("]}")
			create l_file.make (native (a_path))
			l_ok := l_file.set_content (l_json)
		end

	q (a_s: STRING): STRING
			-- `a_s' wrapped in double quotes for JSON.
		do
			Result := "%"" + a_s + "%""
		end

feature {NONE} -- Time helpers

	now_secs: INTEGER
			-- Seconds since midnight.
		local
			l_now: SIMPLE_TIME
		do
			create l_now.make_now
			Result := l_now.seconds_since_midnight
		end

	elapsed (a_start: INTEGER): INTEGER
			-- Seconds elapsed since `a_start' (handles a midnight wrap).
		do
			Result := now_secs - a_start
			if Result < 0 then
				Result := Result + 86400
			end
		end

	fmt (a_secs: INTEGER): STRING
			-- "MmSSs" formatting of `a_secs'.
		do
			Result := (a_secs // 60).out + "m" + (a_secs \\ 60).out + "s"
		end

	checkpoint_for (a_shot: REEL_SHOT): STRING
			-- Checkpoint file for the shot's profile (shot > storyboard > "default").
		do
			if a_shot.profile.is_empty then
				Result := checkpoint_for_profile (cur_default_profile)
			else
				Result := checkpoint_for_profile (a_shot.profile)
			end
		ensure
			result_attached: Result /= Void and then not Result.is_empty
		end

	checkpoint_for_profile (a_profile: STRING): STRING
			-- Checkpoint file for profile `a_profile' ("" = "default").
		local
			l_profile: STRING
		do
			l_profile := a_profile
			if l_profile.is_empty then
				l_profile := "default"
			end
			if attached checkpoint_map.item (l_profile) as ck then
				Result := ck
			elseif attached checkpoint_map.item ("default") as dk then
				Result := dk
			else
				Result := "sd_xl_base_1.0.safetensors"
			end
		ensure
			result_attached: Result /= Void and then not Result.is_empty
		end

	weight_text (a_w: DOUBLE): STRING
			-- `a_w' as a compact JSON number with two decimals (0.0 .. 1.0).
		local
			n: INTEGER
		do
			n := (a_w * 100).rounded
			if n >= 100 then
				Result := "1.0"
			elseif n <= 0 then
				Result := "0.0"
			else
				Result := "0." + (n // 10).out + (n \\ 10).out
			end
		ensure
			result_attached: Result /= Void
		end

	resolve (a_path, a_base_dir: STRING): STRING
			-- `a_path' itself when absolute; otherwise `a_base_dir'/`a_path'.
		require
			path_not_empty: not a_path.is_empty
		do
			if a_path.count >= 2 and then a_path [2] = ':' then
				Result := a_path
			elseif a_path.starts_with ("/") or a_path.starts_with ("\") then
				Result := a_path
			else
				Result := a_base_dir + "/" + a_path
			end
		ensure
			result_attached: Result /= Void
		end

	find_first_mp4 (a_dir: STRING): STRING
			-- Full path of the first .mp4 under `a_dir' (skipping Manim's
			-- partial_movie_files cache); "" when none.
		local
			l_proc: SIMPLE_PROCESS
			l_out, l_line: STRING
		do
			create Result.make_empty
			create l_proc.make
			l_out := l_proc.command_output ("cmd /c dir /s /b %"" + native (a_dir) + "\*.mp4%"").to_string_8
			if l_proc.was_successful and then not l_out.is_empty then
				across l_out.split ('%N') as ic loop
					if Result.is_empty then
						l_line := ic.twin
						l_line.prune_all ('%R')
						l_line.left_adjust
						l_line.right_adjust
						if not l_line.is_empty and then not l_line.has_substring ("partial_movie_files") then
							Result := l_line
						end
					end
				end
			end
		ensure
			result_attached: Result /= Void
		end

	seed_for (a_shot: REEL_SHOT; a_index: INTEGER): INTEGER
			-- The shot's fixed seed, or a per-run derived one.
		do
			if a_shot.has_seed then
				Result := a_shot.seed
			else
				Result := (now_secs * 1000 + a_index) \\ 2147483000
			end
		end

	ensure_dir (a_path: STRING)
			-- Create directory `a_path' if absent.
		local
			l_dir: DIRECTORY
		do
			create l_dir.make (native (a_path))
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
		end

	native (a_path: STRING): STRING
			-- `a_path' with forward slashes turned into Windows backslashes.
			-- ISE FILE/DIRECTORY creation fails on absolute forward-slash paths;
			-- external tools (curl/ffmpeg) are given the original forward-slash form.
		do
			Result := a_path.twin
			Result.replace_substring_all ("/", "\")
		ensure
			result_attached: Result /= Void
		end

feature {NONE} -- Current reel state

	cur_width: INTEGER
	cur_height: INTEGER
	cur_fps: INTEGER

	cur_default_profile: STRING
			-- The running storyboard's reel-wide checkpoint profile.

invariant
	client_attached: client /= Void
	profiles_attached: still_profile /= Void and video_profile /= Void
	done_ids_attached: done_ids /= Void
	checkpoint_map_attached: checkpoint_map /= Void
	cur_default_profile_attached: cur_default_profile /= Void
	tools_attached: resvg_exe /= Void and blender_exe /= Void and python_cmd /= Void

end
