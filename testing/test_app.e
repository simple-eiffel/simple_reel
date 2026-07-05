note
	description: "Test runner for simple_reel."
	author: "Larry Rix"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run simple_reel tests.
		do
			passed := 0
			failed := 0
			print ("Running simple_reel tests...%N%N")
			test_facade
			test_storyboard
			test_extended_shot_fields
			test_comfy
			test_profile
			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")
			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- State

	passed: INTEGER
	failed: INTEGER

feature {NONE} -- Assertions

	check_that (a_name: STRING; a_condition: BOOLEAN)
			-- Record a pass/fail line.
		require
			name_not_empty: not a_name.is_empty
		do
			if a_condition then
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			else
				print ("  FAIL: " + a_name + "%N")
				failed := failed + 1
			end
		end

feature {NONE} -- Tests

	test_facade
			-- Facade constructs and reports a version.
		local
			l_reel: SIMPLE_REEL
		do
			create l_reel.make
			check_that ("version not empty", not l_reel.version.is_empty)
			check_that ("version is 0.3.0", l_reel.version ~ "0.3.0")
		end

	test_comfy
			-- End-to-end probe against a live ComfyUI: submit -> poll -> fetch a produced file.
		local
			l_client: COMFY_CLIENT
			l_pid: detachable STRING
			l_files: ARRAYED_LIST [COMFY_OUTPUT_FILE]
			l_dest: STRING
			l_probe: RAW_FILE
			l_now: SIMPLE_TIME
			l_token: INTEGER
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_client.make
				if not l_client.is_up then
					print ("  SKIP: ComfyUI not reachable at " + l_client.base_url + "%N")
				else
					print ("  INFO: ComfyUI device = " + l_client.device_name + "%N")
					create l_now.make_now
					l_token := l_now.seconds_since_midnight
					l_pid := l_client.submit_prompt (probe_graph (l_token))
					check_that ("submit returned prompt_id", l_pid /= Void)
					if attached l_pid as lp then
						check_that ("completed within 60s", l_client.wait_for (lp, 60))
						l_files := l_client.output_files (lp)
						check_that ("produced at least one output", l_files.count >= 1)
						if not l_files.is_empty then
							ensure_output_dir
							l_dest := "data/output/" + l_files.first.filename
							check_that ("fetched output to disk", l_client.fetch_file (l_files.first, l_dest))
							create l_probe.make_with_name (l_dest)
							check_that ("output file exists on disk", l_probe.exists)
						end
					else
						print ("  ERROR: " + l_client.last_error + "%N")
					end
				end
			end
		rescue
			print ("  ERROR: exception during comfy probe (transport/DLL?)%N")
			failed := failed + 1
			l_retried := True
			retry
		end

	probe_graph (a_token: INTEGER): STRING
			-- Instant EmptyImage -> SaveImage graph, made unique by `a_token' (color + prefix)
			-- so ComfyUI re-executes rather than returning a cached, output-less result.
		do
			Result := "{%"1%":{%"class_type%":%"EmptyImage%",%"inputs%":{%"width%":64,%"height%":64,%"batch_size%":1,%"color%":" +
				a_token.out +
				"}},%"2%":{%"class_type%":%"SaveImage%",%"inputs%":{%"filename_prefix%":%"reel_probe_" +
				a_token.out + "%",%"images%":[%"1%",0]}}}"
		end

	test_storyboard
			-- Load a storyboard.json into typed shots (no GPU needed).
		local
			l_sb: REEL_STORYBOARD
		do
			create l_sb.make_from_file ("data/input/storyboard.json")
			check_that ("storyboard is valid", l_sb.is_valid)
			check_that ("reel name loaded", l_sb.reel_name ~ "test_reel")
			check_that ("fps parsed", l_sb.fps = 24)
			check_that ("width parsed", l_sb.width = 1280)
			check_that ("two shots loaded", l_sb.count = 2)
			if l_sb.count >= 1 then
				check_that ("shot 1 id", l_sb.shots.first.id ~ "s01")
				check_that ("shot 1 is video", l_sb.shots.first.is_video)
				check_that ("shot 1 still prompt parsed", l_sb.shots.first.still_prompt.has_substring ("ancient scroll"))
				check_that ("shot 1 seed parsed", l_sb.shots.first.seed = 111)
			end
			if l_sb.count >= 2 then
				check_that ("shot 2 duration parsed", l_sb.shots.i_th (2).duration = 4)
				check_that ("shot 2 defaults kind to video", l_sb.shots.i_th (2).is_video)
			end
		end

	test_extended_shot_fields
			-- v0.3 schema: profile / svg / script fields and the new kinds (no GPU needed).
		local
			l_json: SIMPLE_JSON
			l_sb: REEL_STORYBOARD
		do
			create l_json
			if attached l_json.parse ({STRING_32} "[
				{"reel":"x","profile":"anime","output_dir":"D:/reels/x","shots":[
				 {"id":"s01","kind":"ken_burns","svg":"s01.svg","duration":5},
				 {"id":"s02","kind":"manim","script":"s02.py","duration":8},
				 {"id":"s03","kind":"blender","script":"s03.py","duration":6},
				 {"id":"s04","kind":"ken_burns","profile":"photo","still_prompt":"a hill","duration":5}]}
			]") as parsed and then attached parsed.as_object as obj then
				create l_sb.make_from_json_object (obj)
				check_that ("storyboard default profile parsed", l_sb.default_profile ~ "anime")
				check_that ("four shots loaded", l_sb.count = 4)
				check_that ("svg field parsed", l_sb.shots.i_th (1).svg_file ~ "s01.svg")
				check_that ("svg shot needs no diffusion", not l_sb.shots.i_th (1).needs_diffusion_still)
				check_that ("manim kind recognized", l_sb.shots.i_th (2).is_manim)
				check_that ("manim shot is scripted", l_sb.shots.i_th (2).is_scripted)
				check_that ("blender kind recognized", l_sb.shots.i_th (3).is_blender)
				check_that ("script field parsed", l_sb.shots.i_th (3).script ~ "s03.py")
				check_that ("per-shot profile parsed", l_sb.shots.i_th (4).profile ~ "photo")
				check_that ("diffusion shot flagged", l_sb.shots.i_th (4).needs_diffusion_still)
				check_that ("storyboard needs comfy (s04)", l_sb.needs_comfy)
			else
				check_that ("extended-fields json parsed", False)
			end
		end

	test_profile
			-- MODEL_PROFILE token substitution, then a real SDXL still through the pipeline.
		local
			l_profile: MODEL_PROFILE
			l_bind: HASH_TABLE [STRING, STRING]
			l_graph: STRING
			l_client: COMFY_CLIENT
			l_pid: detachable STRING
			l_files: ARRAYED_LIST [COMFY_OUTPUT_FILE]
			l_now: SIMPLE_TIME
			l_seed: INTEGER
			l_retried: BOOLEAN
		do
			if not l_retried then
				create l_profile.make_from_file ("sdxl_still", "templates/sdxl_still.json")
				check_that ("profile template loaded", l_profile.is_loaded)

				create l_now.make_now
				l_seed := l_now.seconds_since_midnight
				create l_bind.make (8)
				l_bind.put ("a lone red sailboat on a calm sea, cinematic", "POSITIVE")
				l_bind.put ("blurry, low quality, text, watermark", "NEGATIVE")
				l_bind.put ("512", "WIDTH")
				l_bind.put ("512", "HEIGHT")
				l_bind.put (l_seed.out, "SEED")
				l_bind.put ("8", "STEPS")
				l_bind.put ("sd_xl_base_1.0.safetensors", "CHECKPOINT")
				l_bind.put ("reel_sdxl_" + l_seed.out, "PREFIX")
				l_graph := l_profile.render (l_bind)
				check_that ("render filled POSITIVE token", l_graph.has_substring ("lone red sailboat"))
				check_that ("render left no WIDTH placeholder", not l_graph.has_substring ("%%WIDTH%%"))
				check_that ("render filled CHECKPOINT token", l_graph.has_substring ("sd_xl_base_1.0.safetensors"))

				create l_client.make
				if not l_client.is_up then
					print ("  SKIP: ComfyUI not reachable for SDXL render%N")
				else
					l_pid := l_client.submit_prompt (l_graph)
					check_that ("SDXL submit returned prompt_id", l_pid /= Void)
					if attached l_pid as lp then
						check_that ("SDXL render completed within 180s", l_client.wait_for (lp, 180))
						l_files := l_client.output_files (lp)
						check_that ("SDXL produced a still", l_files.count >= 1)
					else
						print ("  ERROR: " + l_client.last_error + "%N")
					end
				end
			end
		rescue
			print ("  ERROR: exception during profile render%N")
			failed := failed + 1
			l_retried := True
			retry
		end

	ensure_output_dir
			-- Make sure data/output exists.
		local
			l_dir: DIRECTORY
		do
			create l_dir.make ("data/output")
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
		end

end
