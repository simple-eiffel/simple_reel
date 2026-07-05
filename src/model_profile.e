note
	description: "[
		A swappable render backend: a ComfyUI workflow graph template (JSON text with
		%TOKEN% placeholders) plus token substitution. One profile per model/task
		(sdxl_still, flux_still, wan_i2v, ...). Fill the tokens to get a ready graph
		for COMFY_CLIENT.submit_prompt. String values are JSON-escaped on the way in.
	]"
	author: "Larry Rix"

class
	MODEL_PROFILE

create
	make, make_from_file

feature {NONE} -- Initialization

	make (a_name: STRING; a_template: STRING)
			-- Profile `a_name' with an in-memory graph `a_template'.
		require
			name_not_empty: not a_name.is_empty
			template_not_empty: not a_template.is_empty
		do
			name := a_name
			template := a_template
		ensure
			name_set: name = a_name
			template_set: template = a_template
		end

	make_from_file (a_name: STRING; a_path: STRING)
			-- Profile `a_name' whose template text is read from `a_path'.
		require
			name_not_empty: not a_name.is_empty
			path_not_empty: not a_path.is_empty
		local
			l_file: SIMPLE_FILE
		do
			name := a_name
			create l_file.make (a_path)
			if l_file.exists then
				template := l_file.content.to_string_8
			else
				create template.make_empty
			end
		ensure
			name_set: name = a_name
		end

feature -- Access

	name: STRING
			-- Profile identifier.

	template: STRING
			-- Raw graph template text with %TOKEN% placeholders.

feature -- Status

	is_loaded: BOOLEAN
			-- Was a non-empty template loaded?
		do
			Result := not template.is_empty
		end

feature -- Rendering

	render (a_bindings: HASH_TABLE [STRING, STRING]): STRING
			-- Fill every %KEY% placeholder in `template' with the JSON-escaped value
			-- bound to KEY. Keys are token names without the surrounding percents.
		require
			loaded: is_loaded
			bindings_not_void: a_bindings /= Void
		do
			Result := template.twin
			from
				a_bindings.start
			until
				a_bindings.after
			loop
				Result.replace_substring_all ("%%" + a_bindings.key_for_iteration + "%%",
					json_escape (a_bindings.item_for_iteration))
				a_bindings.forth
			end
		ensure
			result_attached: Result /= Void
		end

feature {NONE} -- Implementation

	json_escape (a_value: STRING): STRING
			-- `a_value' with JSON-significant characters escaped for embedding in a JSON string.
		local
			i: INTEGER
			c: CHARACTER
		do
			create Result.make (a_value.count + 8)
			from
				i := 1
			until
				i > a_value.count
			loop
				c := a_value [i]
				if c = '%/092/' then
					Result.append_character ('%/092/')
					Result.append_character ('%/092/')
				elseif c = '%"' then
					Result.append_character ('%/092/')
					Result.append_character ('%"')
				elseif c = '%N' then
					Result.append_character ('%/092/')
					Result.append_character ('n')
				elseif c = '%R' then
					Result.append_character ('%/092/')
					Result.append_character ('r')
				elseif c = '%T' then
					Result.append_character ('%/092/')
					Result.append_character ('t')
				else
					Result.append_character (c)
				end
				i := i + 1
			end
		ensure
			result_attached: Result /= Void
		end

invariant
	name_attached: name /= Void and then not name.is_empty
	template_attached: template /= Void

end
