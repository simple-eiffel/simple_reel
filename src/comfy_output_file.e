note
	description: "A file produced by a ComfyUI prompt: filename, subfolder, and type (output/temp/input)."
	author: "Larry Rix"

class
	COMFY_OUTPUT_FILE

create
	make, make_from_json

feature {NONE} -- Initialization

	make (a_filename, a_subfolder, a_type: STRING)
			-- Create from explicit parts.
		require
			filename_not_empty: not a_filename.is_empty
		do
			filename := a_filename
			subfolder := a_subfolder
			type_name := a_type
		ensure
			filename_set: filename = a_filename
		end

	make_from_json (a_obj: SIMPLE_JSON_OBJECT)
			-- Create from a ComfyUI output entry {filename, subfolder, type}.
		do
			if attached a_obj.string_item (("filename").to_string_32) as f then
				filename := f.to_string_8
			else
				create filename.make_empty
			end
			if attached a_obj.string_item (("subfolder").to_string_32) as s then
				subfolder := s.to_string_8
			else
				create subfolder.make_empty
			end
			if attached a_obj.string_item (("type").to_string_32) as t then
				type_name := t.to_string_8
			else
				create type_name.make_empty
			end
		ensure
			all_attached: filename /= Void and subfolder /= Void and type_name /= Void
		end

feature -- Access

	filename: STRING
			-- Output file name.

	subfolder: STRING
			-- Subfolder within the ComfyUI output/ tree ("" for root).

	type_name: STRING
			-- ComfyUI file class: "output", "temp", or "input".

invariant
	filename_attached: filename /= Void
	subfolder_attached: subfolder /= Void
	type_attached: type_name /= Void

end
