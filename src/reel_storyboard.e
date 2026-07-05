note
	description: "[
		A loaded storyboard: reel metadata (name, fps, width, height) plus an ordered
		list of REEL_SHOT, parsed from a storyboard.json produced for a chapter.
	]"
	author: "Larry Rix"

class
	REEL_STORYBOARD

create
	make_from_file, make_from_json_object

feature {NONE} -- Initialization

	make_from_file (a_path: STRING)
			-- Load a storyboard from the JSON file at `a_path'.
		require
			path_not_empty: not a_path.is_empty
		local
			l_file: SIMPLE_FILE
			l_json: SIMPLE_JSON
		do
			default_create_state
			create l_file.make (a_path)
			if not l_file.exists then
				last_error := "storyboard not found: " + a_path
			else
				create l_json
				if attached l_json.parse (l_file.content) as parsed and then
				   attached parsed.as_object as obj then
					load_from_object (obj)
				else
					last_error := "invalid JSON in " + a_path
				end
			end
		end

	make_from_json_object (a_obj: SIMPLE_JSON_OBJECT)
			-- Load a storyboard from an already-parsed object.
		do
			default_create_state
			load_from_object (a_obj)
		end

feature -- Access

	reel_name: STRING
			-- Reel identifier / output basename.

	output_dir: STRING
			-- Where scene assets and the final film are written.
			-- Defaults to data/output/<reel_name> if not set in the storyboard.

	fps: INTEGER
			-- Frames per second for assembled video.

	width: INTEGER
			-- Render width in pixels.

	height: INTEGER
			-- Render height in pixels.

	default_profile: STRING
			-- Reel-wide checkpoint profile ("" = the pipeline's default).
			-- Individual shots may override with their own `profile'.

	shots: ARRAYED_LIST [REEL_SHOT]
			-- Ordered shots to render.

	last_error: STRING
			-- Load failure message ("" if none).

feature -- Status

	is_valid: BOOLEAN
			-- Loaded without error and has at least one shot?
		do
			Result := last_error.is_empty and then not shots.is_empty
		end

	count: INTEGER
			-- Number of shots.
		do
			Result := shots.count
		end

	needs_comfy: BOOLEAN
			-- Does any shot require the ComfyUI server (diffusion still or Wan video)?
		do
			across shots as ic loop
				if ic.needs_diffusion_still or ic.is_video then
					Result := True
				end
			end
		end

feature {NONE} -- Implementation

	default_create_state
			-- Initialize all fields to defaults.
		do
			create reel_name.make_empty
			create output_dir.make_empty
			create default_profile.make_empty
			create shots.make (16)
			create last_error.make_empty
			fps := Default_fps
			width := Default_width
			height := Default_height
		end

	load_from_object (a_obj: SIMPLE_JSON_OBJECT)
			-- Populate metadata and shots from `a_obj'.
		local
			i: INTEGER
		do
			if attached a_obj.string_item (key ("reel")) as r then
				reel_name := r.to_string_8
			end
			if attached a_obj.string_item (key ("output_dir")) as od and then not od.is_empty then
				output_dir := od.to_string_8
			end
			if attached a_obj.string_item (key ("profile")) as pr and then not pr.is_empty then
				default_profile := pr.to_string_8
			end
			if a_obj.has_key (key ("fps")) then
				fps := a_obj.integer_32_item (key ("fps"))
			end
			if a_obj.has_key (key ("width")) then
				width := a_obj.integer_32_item (key ("width"))
			end
			if a_obj.has_key (key ("height")) then
				height := a_obj.integer_32_item (key ("height"))
			end
			if attached a_obj.array_item (key ("shots")) as arr then
				from i := 1 until i > arr.count loop
					if attached arr.object_item (i) as so then
						shots.extend (create {REEL_SHOT}.make_from_json (so))
					end
					i := i + 1
				end
			end
			if output_dir.is_empty then
				output_dir := "data/output/" + reel_name
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

	Default_fps: INTEGER = 24
	Default_width: INTEGER = 1280
	Default_height: INTEGER = 704

invariant
	reel_name_attached: reel_name /= Void
	output_dir_attached: output_dir /= Void
	default_profile_attached: default_profile /= Void
	shots_attached: shots /= Void
	last_error_attached: last_error /= Void

end
