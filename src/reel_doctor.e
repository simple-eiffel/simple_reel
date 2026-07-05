note
	description: "[
		Preflight and startup for the reel toolchain. `report' prints a checklist of
		everything the pipeline leans on (ffmpeg, curl, workflow templates, the
		ComfyUI server and install, edge-tts). `ensure_comfy_up'
		brings the one startable dependency -- ComfyUI -- up in its own console
		window and waits until the server answers, so a render can proceed
		unattended.
	]"
	author: "Larry Rix"

class
	REEL_DOCTOR

create
	make

feature {NONE} -- Initialization

	make (a_root: STRING)
			-- Doctor for the simple_reel installation at `a_root'.
		require
			root_not_empty: not a_root.is_empty
		do
			app_root := a_root
			comfy_dir := "D:\AI\ComfyUI_windows_portable"
			create client.make
			client.set_temp_dir (a_root + "\data\tmp")
				-- Short HTTP timeout: the probe GETs (is_up / history polls) must fail
				-- fast while ComfyUI is still booting, or `up' hangs on one stuck GET.
			client.http.set_timeout (10)
		ensure
			root_set: app_root = a_root
		end

feature -- Access

	app_root: STRING
			-- simple_reel install root (templates\ lives here).

	comfy_dir: STRING
			-- ComfyUI portable install root.

	client: COMFY_CLIENT
			-- Client used to probe (and later drive) the ComfyUI server.

feature -- Checks

	is_render_ready: BOOLEAN
			-- Can a render start right now (tools, templates and server all present)?
		do
			Result := has_ffmpeg and then has_curl and then has_templates and then client.is_up
		end

	has_ffmpeg: BOOLEAN
			-- Is ffmpeg on the PATH? (Ken Burns, assemble.)
		do
			Result := runs_ok ("ffmpeg -version")
		end

	has_curl: BOOLEAN
			-- Is curl on the PATH? (ComfyUI POST and file download.)
		do
			Result := runs_ok ("curl --version")
		end

	has_templates: BOOLEAN
			-- Are both workflow templates present under `app_root'?
		do
			Result := file_exists (app_root + "\templates\sdxl_still.json") and then
				file_exists (app_root + "\templates\wan_i2v.json")
		end

	has_comfy_install: BOOLEAN
			-- Is the ComfyUI portable install (embedded python) where we expect it?
		do
			Result := file_exists (comfy_dir + "\python_embeded\python.exe")
		end

	has_edge_tts: BOOLEAN
			-- Can the system python import edge_tts? (Needed by timing.py only.)
		do
			Result := runs_ok ("python -c %"import edge_tts%"")
		end

	has_resvg: BOOLEAN
			-- Is the resvg rasterizer installed? (Needed by svg shots only.)
		do
			Result := file_exists (app_root + "\tools\resvg.exe")
		end

	has_manim: BOOLEAN
			-- Can the system python import manim? (Needed by manim shots only.)
		do
			Result := runs_ok ("python -c %"import manim%"")
		end

	has_blender: BOOLEAN
			-- Is Blender installed where the pipeline expects it? (blender shots only.)
		do
			Result := file_exists (blender_exe)
		end

	blender_exe: STRING = "D:\AI\blender\blender.exe"
			-- Where the pipeline looks for headless Blender.

feature -- Report

	report
			-- Print the full checklist and the render-ready verdict.
		do
			line (has_ffmpeg, "ffmpeg on PATH (ken burns, assemble)")
			line (has_curl, "curl on PATH (ComfyUI POST/download)")
			line (has_templates, "templates\sdxl_still.json + wan_i2v.json under " + app_root)
			line (has_comfy_install, "ComfyUI install at " + comfy_dir)
			line (client.is_up, "ComfyUI server at " + client.base_url)
			line (has_edge_tts, "python + edge-tts (timing.py only)")
			line (has_resvg, "resvg at tools\resvg.exe (svg shots only)")
			line (has_manim, "python + manim (manim shots only)")
			line (has_blender, "Blender at " + blender_exe + " (blender shots only)")
			if is_render_ready then
				say ("ready to render: YES%N")
			else
				say ("ready to render: NO -- run: simple_reel up%N")
			end
		end

feature -- Startup

	ensure_comfy_up (a_wait_seconds: INTEGER): BOOLEAN
			-- True when ComfyUI answers. When down, launch it in its own console
			-- and wait up to `a_wait_seconds' for the server to come up.
		require
			positive_wait: a_wait_seconds > 0
		local
			l_proc: SIMPLE_PROCESS
			l_env: EXECUTION_ENVIRONMENT
			l_elapsed: INTEGER
		do
			if client.is_up then
				Result := True
			elseif not has_comfy_install then
				say ("ComfyUI install not found at " + comfy_dir + "%N")
			else
				say ("ComfyUI is down -- starting it in a new console ... ")
				create l_proc.make
				l_proc.execute (comfy_start_command)
				create l_env
				from
					l_elapsed := 0
				until
					Result or l_elapsed >= a_wait_seconds
				loop
					l_env.sleep ({INTEGER_64} 2_000_000_000)
					l_elapsed := l_elapsed + 2
					Result := client.is_up
				end
				if Result then
					say ("up after ~" + l_elapsed.out + "s%N")
				else
					say ("not answering after " + a_wait_seconds.out + "s%N")
				end
			end
		end

feature {NONE} -- Implementation

	comfy_start_command: STRING
			-- Shell command that launches ComfyUI detached, in its own console window.
		do
			Result := "cmd /c start %"ComfyUI%" /D %"" + comfy_dir + "%" %"" + comfy_dir +
				"\python_embeded\python.exe%" -s %"" + comfy_dir +
				"\ComfyUI\main.py%" --windows-standalone-build --port 8188"
		ensure
			result_attached: Result /= Void
		end

	runs_ok (a_command: STRING): BOOLEAN
			-- Does `a_command' execute and exit 0?
		require
			command_not_empty: not a_command.is_empty
		local
			l_proc: SIMPLE_PROCESS
		do
			create l_proc.make
			l_proc.execute (a_command)
			Result := l_proc.was_successful
		end

	file_exists (a_path: STRING): BOOLEAN
			-- Is there a file at `a_path'?
		require
			path_not_empty: not a_path.is_empty
		local
			l_file: SIMPLE_FILE
		do
			create l_file.make (a_path)
			Result := l_file.exists
		end

	line (a_ok: BOOLEAN; a_label: STRING)
			-- Print one checklist line for `a_label'.
		do
			if a_ok then
				say ("  [OK]  " + a_label + "%N")
			else
				say ("  [--]  " + a_label + "%N")
			end
		end

	say (a_msg: STRING)
			-- Print `a_msg' immediately (flushed).
		do
			io.put_string (a_msg)
			io.output.flush
		end

invariant
	app_root_attached: app_root /= Void and then not app_root.is_empty
	comfy_dir_attached: comfy_dir /= Void and then not comfy_dir.is_empty
	client_attached: client /= Void

end
