note
	description: "[
		One storyboard shot. How it is brought to life depends on `kind':
			- "video"      : still -> Wan image-to-video (motion_prompt), for key beats
			- "ken_burns"  : still -> ffmpeg pan/zoom (`motion'), cheap and fast
			- "still"      : the still frame only
			- "manim"      : a Claude-authored Manim scene script -> clip (no still)
			- "blender"    : a Claude-authored bpy script -> frames -> clip (no still)
		For the still-based kinds the still comes from diffusion (`still_prompt',
		checkpoint chosen by `profile') -- unless `svg' names an SVG file, which is
		rasterized into the still slot instead (crisp text/diagrams).
	]"
	author: "Larry Rix"

class
	REEL_SHOT

create
	make, make_from_json

feature {NONE} -- Initialization

	make (a_id: STRING)
			-- A blank ken-burns shot with identifier `a_id'.
		require
			id_not_empty: not a_id.is_empty
		do
			id := a_id
			create section.make_empty
			create still_prompt.make_empty
			create motion_prompt.make_empty
			create negative.make_empty
			create narration.make_empty
			create profile.make_empty
			create svg_file.make_empty
			create script.make_empty
			create ref_image.make_empty
			ref_weight := Default_ref_weight
			kind := "ken_burns"
			motion := "push_in"
			duration := Default_duration
			seed := 0
		ensure
			id_set: id = a_id
		end

	make_from_json (a_obj: SIMPLE_JSON_OBJECT)
			-- Build a shot from a storyboard.json entry.
		do
			id := text (a_obj, "id")
			section := text (a_obj, "section")
			still_prompt := text (a_obj, "still_prompt")
			motion_prompt := text (a_obj, "motion_prompt")
			negative := text (a_obj, "negative")
			narration := text (a_obj, "narration")
			profile := text (a_obj, "profile")
			svg_file := text (a_obj, "svg")
			script := text (a_obj, "script")
			ref_image := text (a_obj, "ref_image")
			if a_obj.has_key (key ("ref_weight")) then
				ref_weight := a_obj.real_item (key ("ref_weight"))
			end
			if ref_weight <= 0.0 or ref_weight > 1.0 then
				ref_weight := Default_ref_weight
			end
			if attached a_obj.string_item (key ("kind")) as k and then not k.is_empty then
				kind := k.to_string_8
			else
				kind := "ken_burns"
			end
			motion := text (a_obj, "motion")
			if motion.is_empty then
				motion := "push_in"
			end
			if a_obj.has_key (key ("duration")) then
				duration := a_obj.integer_32_item (key ("duration"))
			else
				duration := Default_duration
			end
			if duration <= 0 then
				duration := Default_duration
			end
			seed := a_obj.integer_32_item (key ("seed"))
		ensure
			positive_duration: duration > 0
		end

feature -- Access

	id: STRING
			-- Shot identifier (e.g. "s01").

	section: STRING
			-- Chapter/section label this shot belongs to.

	still_prompt: STRING
			-- Prompt for the still (composition) pass.

	motion_prompt: STRING
			-- Prompt for the image-to-video pass (used when kind = video).

	negative: STRING
			-- Shared negative prompt.

	narration: STRING
			-- Spoken text for this scene (drives TTS duration + captions).

	profile: STRING
			-- Checkpoint profile for the diffusion still ("" = storyboard default).

	svg_file: STRING
			-- SVG file rasterized into the still slot instead of diffusion ("" = none).
			-- Relative paths resolve against the storyboard's output_dir.

	script: STRING
			-- Scene script for the manim/blender kinds ("" = none).
			-- Relative paths resolve against the storyboard's output_dir.

	ref_image: STRING
			-- Character/identity reference image for the diffusion still, applied via
			-- IP-Adapter ("" = none). Typically "characters/<name>.png" from a sheet
			-- rendered by the `characters' mode; resolves against output_dir.

	ref_weight: DOUBLE
			-- IP-Adapter strength for `ref_image' (0..1). Higher locks identity harder
			-- but bleeds the reference's background/pose into the scene; ~0.5-0.6
			-- keeps the scene while holding the character. Default 0.55.

	kind: STRING
			-- "video", "ken_burns", "still", "manim", or "blender".

	motion: STRING
			-- Ken Burns move: push_in, push_out, pan_left, pan_right, pan_up, pan_down.

	duration: INTEGER
			-- Clip length in seconds.

	seed: INTEGER
			-- Fixed seed, or 0 for automatic.

feature -- Status

	is_video: BOOLEAN
			-- Animate via Wan image-to-video?
		do
			Result := kind.is_case_insensitive_equal ("video")
		end

	is_ken_burns: BOOLEAN
			-- Animate the still via ffmpeg pan/zoom?
		do
			Result := kind.is_case_insensitive_equal ("ken_burns") or kind.is_case_insensitive_equal ("motion_still")
		end

	is_still_only: BOOLEAN
			-- Emit the still with no motion?
		do
			Result := kind.is_case_insensitive_equal ("still")
		end

	is_manim: BOOLEAN
			-- Produce the clip by running a Manim scene script?
		do
			Result := kind.is_case_insensitive_equal ("manim")
		end

	is_blender: BOOLEAN
			-- Produce the clip by running a Blender bpy script?
		do
			Result := kind.is_case_insensitive_equal ("blender")
		end

	is_scripted: BOOLEAN
			-- Clip comes from a script, not a still (manim or blender)?
		do
			Result := is_manim or is_blender
		end

	has_svg: BOOLEAN
			-- Does an SVG file supply the still instead of diffusion?
		do
			Result := not svg_file.is_empty
		end

	needs_diffusion_still: BOOLEAN
			-- Does this shot need a diffusion-rendered still?
		do
			Result := not is_scripted and then not has_svg
		end

	has_seed: BOOLEAN
			-- Is a fixed seed set?
		do
			Result := seed /= 0
		end

feature {NONE} -- Implementation

	text (a_obj: SIMPLE_JSON_OBJECT; a_key: STRING): STRING
			-- String value for `a_key' in `a_obj', or "".
		local
			s: detachable STRING_32
		do
			s := a_obj.string_item (key (a_key))
			if attached s as ls then
				Result := ls.to_string_8
			else
				create Result.make_empty
			end
		ensure
			result_attached: Result /= Void
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

	Default_duration: INTEGER = 5
			-- Default clip length in seconds.

	Default_ref_weight: DOUBLE = 0.55
			-- Default IP-Adapter strength.

invariant
	id_attached: id /= Void
	section_attached: section /= Void
	still_prompt_attached: still_prompt /= Void
	motion_prompt_attached: motion_prompt /= Void
	negative_attached: negative /= Void
	narration_attached: narration /= Void
	profile_attached: profile /= Void
	svg_file_attached: svg_file /= Void
	script_attached: script /= Void
	ref_image_attached: ref_image /= Void
	ref_weight_in_range: ref_weight > 0.0 and ref_weight <= 1.0
	kind_attached: kind /= Void
	motion_attached: motion /= Void
	duration_positive: duration > 0

end
