note
	description: "Test-only view of REEL_DOCTOR's secret command check."
	author: "Larry Rix"

class
	REEL_DOCTOR_PROBE

inherit
	REEL_DOCTOR

create
	make

feature -- Probe

	command_runs_ok (a_command: STRING): BOOLEAN
			-- `runs_ok' made visible to the tests.
		require
			command_not_empty: not a_command.is_empty
		do
			Result := runs_ok (a_command)
		end

end
