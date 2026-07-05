note
	description: "[
		Client for a local ComfyUI server. Submits a workflow graph to /prompt,
		polls /history for completion, and fetches produced files from /view.

		GET/JSON traffic uses SIMPLE_HTTP. POST and binary download use the system
		`curl' via SIMPLE_PROCESS, because SIMPLE_HTTP's POST path strips double
		quotes from raw JSON bodies (logged as a simple_http defect).
	]"
	author: "Larry Rix"

class
	COMFY_CLIENT

create
	make, make_with_base

feature {NONE} -- Initialization

	make
			-- Client for ComfyUI at the default http://127.0.0.1:8188.
		do
			make_with_base ("http://127.0.0.1:8188")
		ensure
			base_default: base_url.same_string ("http://127.0.0.1:8188")
		end

	make_with_base (a_base: STRING)
			-- Client for ComfyUI reachable at `a_base'.
		require
			base_not_empty: not a_base.is_empty
		do
			base_url := a_base
			temp_dir := "data/tmp"
			create http.make
			http.set_timeout (600)
			create logger.make
			create last_error.make_empty
		ensure
			base_set: base_url = a_base
		end

feature -- Access

	base_url: STRING
			-- ComfyUI server base URL.

	temp_dir: STRING
			-- Directory for transient request bodies.

	http: SIMPLE_HTTP
			-- Underlying HTTP client (GET/JSON only).

	logger: SIMPLE_LOGGER
			-- Logger.

	last_error: STRING
			-- Message from the most recent failure ("" if none).

feature -- Settings

	set_temp_dir (a_dir: STRING)
			-- Write transient request bodies under `a_dir'.
		require
			not_empty: not a_dir.is_empty
		do
			temp_dir := a_dir
		ensure
			set: temp_dir = a_dir
		end

feature -- Status

	is_up: BOOLEAN
			-- Is the ComfyUI server responding on /system_stats?
		do
			Result := http.get (base_url + "/system_stats").status = 200
		end

	device_name: STRING
			-- GPU device name from /system_stats ("" if unavailable).
		local
			l_resp: SIMPLE_HTTP_RESPONSE
		do
			create Result.make_empty
			l_resp := http.get (base_url + "/system_stats")
			if l_resp.status = 200 and then attached l_resp.json_object as obj and then
			   attached obj.array_item (key ("devices")) as devs and then devs.count >= 1 and then
			   attached devs.object_item (1) as d0 and then attached d0.string_item (key ("name")) as nm then
				Result := nm.to_string_8
			end
		ensure
			result_attached: Result /= Void
		end

feature -- Submission

	submit_prompt (a_graph_json: STRING): detachable STRING
			-- Queue workflow `a_graph_json' via POST /prompt (through curl); return its prompt_id, or Void.
		require
			graph_not_empty: not a_graph_json.is_empty
		local
			l_proc: SIMPLE_PROCESS
			l_body_file: RAW_FILE
			l_body_path: STRING
			l_out: STRING
			l_json: SIMPLE_JSON
		do
			last_error.wipe_out
			ensure_temp_dir
			l_body_path := temp_dir + "/reel_prompt.json"
			create l_body_file.make_open_write (l_body_path)
			l_body_file.put_string ("{%"prompt%":" + a_graph_json + "}")
			l_body_file.close

			create l_proc.make
			l_out := l_proc.command_output ("curl -s -X POST -H %"Content-Type: application/json%" --data-binary %"@" +
				l_body_path + "%" %"" + base_url + "/prompt%"").to_string_8
			if l_proc.was_successful and then not l_out.is_empty then
				create l_json
				if attached l_json.parse (l_out.to_string_32) as parsed and then
				   attached parsed.as_object as obj and then
				   attached obj.string_item (key ("prompt_id")) as pid then
					Result := pid.to_string_8
				else
					last_error := "unexpected /prompt response: " + l_out
				end
			else
				last_error := "curl POST /prompt failed (exit " + l_proc.last_exit_code.out + ")"
			end
		end

feature -- Polling

	wait_for (a_prompt_id: STRING; a_timeout_seconds: INTEGER): BOOLEAN
			-- Poll /history/<id> until outputs appear or `a_timeout_seconds' elapse.
		require
			id_not_empty: not a_prompt_id.is_empty
			timeout_positive: a_timeout_seconds > 0
		local
			l_env: EXECUTION_ENVIRONMENT
			l_elapsed, l_interval: INTEGER
		do
			create l_env
			l_interval := 2
			from
				l_elapsed := 0
			until
				Result or l_elapsed >= a_timeout_seconds
			loop
				if attached history_entry (a_prompt_id) as entry and then
				   attached entry.object_item (key ("status")) as st and then st.boolean_item (key ("completed")) then
					Result := True
				else
					l_env.sleep (l_interval.to_integer_64 * 1_000_000_000)
					l_elapsed := l_elapsed + l_interval
				end
			end
		end

feature -- Results

	output_files (a_prompt_id: STRING): ARRAYED_LIST [COMFY_OUTPUT_FILE]
			-- Files (images/gifs/videos) produced by the completed prompt.
		require
			id_not_empty: not a_prompt_id.is_empty
		do
			create Result.make (4)
			if attached history_entry (a_prompt_id) as entry and then
			   attached entry.object_item (key ("outputs")) as outs then
				across outs.keys as ic_node loop
					if attached outs.object_item (ic_node) as nd then
						collect_files (nd, "images", Result)
						collect_files (nd, "gifs", Result)
						collect_files (nd, "videos", Result)
					end
				end
			end
		end

	fetch_file (a_file: COMFY_OUTPUT_FILE; a_dest_path: STRING): BOOLEAN
			-- Download `a_file' via /view to `a_dest_path' (through curl). True on success.
		require
			dest_not_empty: not a_dest_path.is_empty
		local
			l_proc: SIMPLE_PROCESS
			l_url: STRING
			l_dest: RAW_FILE
		do
			last_error.wipe_out
			l_url := base_url + "/view?filename=" + a_file.filename +
				"&subfolder=" + a_file.subfolder + "&type=" + a_file.type_name
			create l_proc.make
			l_proc.execute ("curl -s -f -o %"" + a_dest_path + "%" %"" + l_url + "%"")
			create l_dest.make_with_name (a_dest_path)
			if l_proc.was_successful and then l_dest.exists then
				Result := True
			else
				last_error := "curl GET /view failed for " + a_file.filename +
					" (exit " + l_proc.last_exit_code.out + ")"
			end
		end

feature {NONE} -- Implementation

	history_entry (a_prompt_id: STRING): detachable SIMPLE_JSON_OBJECT
			-- The /history entry object for `a_prompt_id', or Void.
		require
			id_not_empty: not a_prompt_id.is_empty
		local
			l_resp: SIMPLE_HTTP_RESPONSE
		do
			l_resp := http.get (base_url + "/history/" + a_prompt_id)
			if l_resp.status = 200 and then attached l_resp.json_object as obj then
				Result := obj.object_item (a_prompt_id.to_string_32)
			end
		end

	collect_files (a_node: SIMPLE_JSON_OBJECT; a_kind: STRING; a_acc: ARRAYED_LIST [COMFY_OUTPUT_FILE])
			-- Append any files under the `a_kind' array of `a_node' to `a_acc'.
		require
			kind_not_empty: not a_kind.is_empty
		local
			i: INTEGER
		do
			if attached a_node.array_item (key (a_kind)) as arr then
				from i := 1 until i > arr.count loop
					if attached arr.object_item (i) as fo then
						a_acc.extend (create {COMFY_OUTPUT_FILE}.make_from_json (fo))
					end
					i := i + 1
				end
			end
		end

	ensure_temp_dir
			-- Make sure `temp_dir' exists.
		local
			l_dir: DIRECTORY
		do
			create l_dir.make (temp_dir)
			if not l_dir.exists then
				l_dir.recursive_create_dir
			end
		end

	key (a_key: STRING): STRING_32
			-- `a_key' as STRING_32 for JSON access.
		require
			not_empty: not a_key.is_empty
		do
			Result := a_key.to_string_32
		ensure
			result_attached: Result /= Void
		end

invariant
	base_url_attached: base_url /= Void and then not base_url.is_empty
	temp_dir_attached: temp_dir /= Void and then not temp_dir.is_empty
	http_attached: http /= Void
	logger_attached: logger /= Void
	last_error_attached: last_error /= Void

end
