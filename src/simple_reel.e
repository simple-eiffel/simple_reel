note
	description: "Facade for the Simple Reel chapter-to-video render orchestrator over ComfyUI."
	author: "Larry Rix"

class
	SIMPLE_REEL

create
	make

feature {NONE} -- Initialization

	make
			-- Initialize the reel orchestrator facade.
		do
			create logger.make
			logger.info ("simple_reel " + version + " ready")
		ensure
			logger_attached: logger /= Void
		end

feature -- Access

	version: STRING = "0.3.0"
			-- Library version.

	logger: SIMPLE_LOGGER
			-- Shared logger.

invariant
	logger_attached: logger /= Void
	version_not_empty: not version.is_empty

end
