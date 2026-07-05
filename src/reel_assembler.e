note
	description: "[
		The final step. Concatenates every scene clip in data/output/<reel>/ -- in
		storyboard order -- into one continuous film via ffmpeg's concat filter, with
		each clip normalized to the reel's size/fps for clean joins. Optionally muxes a
		narration track over the result.
	]"
	author: "Larry Rix"

class
	REEL_ASSEMBLER

create
	make

feature {NONE} -- Initialization

	make (a_sb: REEL_STORYBOARD)
			-- Assembler for the reel described by `a_sb'.
		do
			storyboard := a_sb
			create last_error.make_empty
			clip_count := 0
		end

feature -- Access

	storyboard: REEL_STORYBOARD
			-- The reel whose clips are stitched.

	last_error: STRING
			-- Failure message ("" if none).

	clip_count: INTEGER
			-- Clips found and included in the last assembly.

feature -- Assembly

	assemble (a_out_path: STRING; a_audio: detachable STRING): BOOLEAN
			-- Stitch the reel's clips (in storyboard order) into `a_out_path'.
			-- If `a_audio' is attached, mux it over the film. True on success.
		require
			out_not_empty: not a_out_path.is_empty
		local
			l_dir: STRING
			l_clips: ARRAYED_LIST [STRING]
			l_file, l_dest: SIMPLE_FILE
			l_proc: SIMPLE_PROCESS
			l_cmd, l_list, l_list_path, l_vf: STRING
		do
			last_error := ""
			clip_count := 0
			l_dir := storyboard.output_dir
			create l_clips.make (storyboard.count)
			across storyboard.shots as ic_shot loop
				create l_file.make (l_dir + "/" + ic_shot.id + ".mp4")
				if l_file.exists then
					l_clips.extend (l_dir + "/" + ic_shot.id + ".mp4")
				end
			end
			clip_count := l_clips.count
			if l_clips.is_empty then
				last_error := "no scene clips found in " + l_dir
			else
					-- concat demuxer via a list file (kept in the reel's own output dir,
					-- so the exe works from any current directory): one short command
					-- regardless of clip count.
				create l_list.make_empty
				across l_clips as ic_clip loop
					l_list.append ("file '" + ic_clip + "'%N")
				end
				l_list_path := l_dir + "/" + storyboard.reel_name + "_concat.txt"
				create l_file.make (native (l_list_path))
				if l_file.set_content (l_list) then
					l_vf := "scale=" + storyboard.width.out + ":" + storyboard.height.out +
						",setsar=1,fps=" + storyboard.fps.out + ",format=yuv420p"
					create l_cmd.make_from_string ("ffmpeg -y -f concat -safe 0 -i %"" + l_list_path + "%"")
					if attached a_audio as au then
						l_cmd.append (" -i %"" + au + "%" -map 0:v:0 -map 1:a:0")
					end
					l_cmd.append (" -vf %"" + l_vf + "%" -c:v libx264 -crf 18 -pix_fmt yuv420p")
					if a_audio /= Void then
						l_cmd.append (" -c:a aac -shortest")
					end
					l_cmd.append (" %"" + a_out_path + "%"")
					create l_proc.make
					l_proc.execute (l_cmd)
					create l_dest.make (a_out_path)
					if l_proc.was_successful and then l_dest.exists then
						Result := True
					else
						last_error := "ffmpeg concat failed (exit " + l_proc.last_exit_code.out + ")"
					end
				else
					last_error := "could not write concat list " + l_list_path
				end
			end
		end

feature {NONE} -- Implementation

	native (a_path: STRING): STRING
			-- `a_path' with forward slashes turned into Windows backslashes
			-- (ISE file creation fails on absolute forward-slash paths).
		do
			Result := a_path.twin
			Result.replace_substring_all ("/", "\")
		ensure
			result_attached: Result /= Void
		end

end
