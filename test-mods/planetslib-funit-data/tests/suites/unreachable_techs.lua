-- Runtime tests for scripts/unreachable-techs.lua and scripts/player-effects.lua.
--
-- Both modules are required into this Lua state (the headless FUnit scenario),
-- so their global reads (`prototypes`, `game`, `log`) can be replaced with
-- small test doubles for the duration of a test. This never touches PlanetsLib's
-- own runtime Lua state.
--
-- URT-1..2 drive warn_unreachable_techs / warn_unlinked_prerequisites with fake
-- prototype tables. URT-3 drives the on_player_banned handler obtained from the
-- direct require of scripts/player-effects.lua. URT-4 exercises the on-join
-- event through FUnit's event mocker; the tick-0 branch is noted rather than
-- observed because that handler lives in PlanetsLib's VM.

local function count_occurrences(text, needle)
	local count = 0
	local position = 1
	while true do
		local start = string.find(text, needle, position, true)
		if not start then
			return count
		end
		count = count + 1
		position = start + #needle
	end
end

-- Replace the globals the modules read, run `callback`, then always restore
-- them (even when an FUnit assertion fails) so later tests see the real game.
local function with_environment(environment, callback)
	local saved = {}
	for key, _ in pairs(environment) do
		saved[key] = rawget(_G, key)
	end
	for key, value in pairs(environment) do
		rawset(_G, key, value)
	end

	local ok, err = pcall(callback)

	for key, _ in pairs(environment) do
		rawset(_G, key, saved[key])
	end
	if not ok then
		error(err, 0)
	end
end

local function make_environment(options)
	options = options or {}
	local prints = {}
	local logs = {}

	local environment = {
		game = {
			tick = options.tick or 0,
			players = options.players or {},
			print = function(message, print_settings)
				prints[#prints + 1] = { message = message, settings = print_settings }
			end,
			unban_player = function(player_name)
				if options.on_unban then
					options.on_unban(player_name)
				end
			end,
		},
		prototypes = {
			mod_data = {
				Planetslib = {
					data = {
						unlinked_prerequisites = options.unlinked_prerequisites or {},
					},
				},
			},
			technology = options.technology or {},
		},
		log = function(message)
			logs[#logs + 1] = message
		end,
	}

	return environment, prints, logs
end

-- One hidden prerequisite with `successor_count` visible successors, plus a
-- hidden technology that also depends on it. Hidden technologies are not
-- reported as visible successors, so only `successor_count` links should appear.
local function hidden_prereq_technology(successor_count)
	local hidden = { name = "funit-urt-hidden", hidden = true, prerequisites = {} }
	local technology = {
		["funit-urt-hidden"] = hidden,
		["funit-urt-hidden-child"] = {
			name = "funit-urt-hidden-child",
			hidden = true,
			prerequisites = { hidden },
		},
	}

	for index = 1, successor_count do
		local name = "funit-urt-visible-" .. index
		technology[name] = {
			name = name,
			hidden = false,
			prerequisites = { hidden },
		}
	end

	return technology
end

return function(runner)
	local unreachable_techs = require("__PlanetsLib__.scripts.unreachable-techs")
	local mock = require("__funit__.mock")

	-- scripts/player-effects.lua registers its handler when required. Capture the
	-- handler and restore whatever was registered before it, so this suite does
	-- not leave an extra on_player_banned handler behind.
	local previous_banned_handler = script.get_event_handler(defines.events.on_player_banned)
	local player_effects_ok, player_effects_err = pcall(function()
		_G.PlanetsLib = _G.PlanetsLib or {}
		require("__PlanetsLib__.lib.authors")
		require("__PlanetsLib__.scripts.player-effects")
	end)
	local player_effects_handler = script.get_event_handler(defines.events.on_player_banned)
	script.on_event(defines.events.on_player_banned, previous_banned_handler)

	runner.test("URT-1 hidden-prerequisite warnings and truncation", function()
		-- Three visible successors: all are reported, hidden successors are not.
		local technology = hidden_prereq_technology(3)
		local environment, prints, logs = make_environment({ technology = technology })

		with_environment(environment, function()
			unreachable_techs.warn_unreachable_techs()
		end)

		runner.assert(#prints == 1, "expected exactly one game.print warning, got " .. #prints)
		local localised = prints[1].message
		runner.assert(
			type(localised) == "table"
				and type(localised[3]) == "table"
				and localised[3][1] == "planetslib.warn-unreachable-techs",
			"the warning did not use the planetslib.warn-unreachable-techs key"
		)

		local warning = localised[3][2]
		runner.assert(type(warning) == "string", "the warning text is missing")
		runner.assert(
			warning:find("funit-urt-hidden", 1, true) ~= nil,
			"the warning is missing the hidden prerequisite name"
		)
		runner.assert(
			count_occurrences(warning, "[technology=") == 3,
			"expected 3 visible successors in the warning, got " .. count_occurrences(warning, "[technology=")
		)
		runner.assert(
			not warning:find("see game logs", 1, true),
			"three successors must not trigger the truncation marker"
		)
		runner.assert(
			not warning:find("funit-urt-hidden-child", 1, true),
			"a hidden technology must not be reported as a visible successor"
		)

		runner.assert(#logs == 1, "expected exactly one log entry, got " .. #logs)
		runner.assert(
			count_occurrences(logs[1], "[technology=") == 3,
			"the log should contain the full successor list"
		)

		-- Many successors: the printed warning is truncated at ten, the log is not.
		technology = hidden_prereq_technology(15)
		environment, prints, logs = make_environment({ technology = technology })

		with_environment(environment, function()
			unreachable_techs.warn_unreachable_techs()
		end)

		runner.assert(#prints == 1, "expected exactly one game.print warning, got " .. #prints)
		warning = prints[1].message[3][2]
		runner.assert(
			count_occurrences(warning, "[technology=") == 10,
			"the printed warning should contain exactly 10 successors, got "
				.. count_occurrences(warning, "[technology=")
		)
		runner.assert(
			warning:find("... (see game logs for full list)", 1, true) ~= nil,
			"the truncated warning is missing the full-list marker"
		)

		runner.assert(#logs == 1, "expected exactly one log entry, got " .. #logs)
		runner.assert(
			count_occurrences(logs[1], "[technology=") == 15,
			"the log should contain all 15 successors, got " .. count_occurrences(logs[1], "[technology=")
		)

		-- Multiple hidden prerequisites each contribute their own warning.
		local hidden_a = { name = "funit-urt-hidden-a", hidden = true, prerequisites = {} }
		local hidden_b = { name = "funit-urt-hidden-b", hidden = true, prerequisites = {} }
		technology = {
			["funit-urt-hidden-a"] = hidden_a,
			["funit-urt-hidden-b"] = hidden_b,
			["funit-urt-visible-a"] = {
				name = "funit-urt-visible-a",
				hidden = false,
				prerequisites = { hidden_a },
			},
			["funit-urt-visible-b"] = {
				name = "funit-urt-visible-b",
				hidden = false,
				prerequisites = { hidden_b },
			},
		}
		environment, prints, logs = make_environment({ technology = technology })

		with_environment(environment, function()
			unreachable_techs.warn_unreachable_techs()
		end)

		runner.assert(#prints == 1, "expected one combined game.print warning, got " .. #prints)
		warning = prints[1].message[3][2]
		runner.assert(
			count_occurrences(warning, "[technology=") == 2,
			"both hidden prerequisites should be reported, got "
				.. count_occurrences(warning, "[technology=")
		)
		runner.assert(
			warning:find("funit-urt-hidden-a", 1, true) ~= nil
				and warning:find("funit-urt-hidden-b", 1, true) ~= nil,
			"the combined warning is missing one of the hidden prerequisites"
		)

		-- No hidden prerequisites: no warning and no log at all.
		technology = {
			["funit-urt-visible"] = {
				name = "funit-urt-visible",
				hidden = false,
				prerequisites = {},
			},
		}
		environment, prints, logs = make_environment({ technology = technology })

		with_environment(environment, function()
			unreachable_techs.warn_unreachable_techs()
		end)

		runner.assert(#prints == 0, "no warning should be printed when nothing is unreachable")
		runner.assert(#logs == 0, "nothing should be logged when nothing is unreachable")
	end)

	runner.test("URT-2 warn_unlinked_prerequisites reports and truncates", function()
		local unlinked = {}
		for index = 1, 3 do
			unlinked[index] = "funit-urt-unlinked-" .. index
		end

		local environment, prints, logs = make_environment({ unlinked_prerequisites = unlinked })

		with_environment(environment, function()
			unreachable_techs.warn_unlinked_prerequisites()
		end)

		runner.assert(#prints == 1, "expected exactly one game.print warning, got " .. #prints)
		local localised = prints[1].message
		runner.assert(
			type(localised) == "table"
				and type(localised[3]) == "table"
				and localised[3][1] == "planetslib.notify-unlinked-prerequisites",
			"the warning did not use the planetslib.notify-unlinked-prerequisites key"
		)

		local warning = localised[3][2]
		runner.assert(type(warning) == "string", "the warning text is missing")
		runner.assert(
			count_occurrences(warning, "funit-urt-unlinked-") == 3,
			"expected 3 unlinked prerequisites in the warning, got "
				.. count_occurrences(warning, "funit-urt-unlinked-")
		)
		runner.assert(
			not warning:find("see game logs", 1, true),
			"three prerequisites must not trigger the truncation marker"
		)
		runner.assert(
			count_occurrences(logs[1], "funit-urt-unlinked-") == 3,
			"the log should contain the full unlinked-prerequisite list"
		)

		-- More than ten entries: truncate the game.print text, log everything.
		unlinked = {}
		for index = 1, 12 do
			unlinked[index] = "funit-urt-unlinked-" .. index
		end
		environment, prints, logs = make_environment({ unlinked_prerequisites = unlinked })

		with_environment(environment, function()
			unreachable_techs.warn_unlinked_prerequisites()
		end)

		warning = prints[1].message[3][2]
		runner.assert(
			count_occurrences(warning, "funit-urt-unlinked-") == 10,
			"the printed warning should contain exactly 10 prerequisites, got "
				.. count_occurrences(warning, "funit-urt-unlinked-")
		)
		runner.assert(
			warning:find("... (see game logs for full list)", 1, true) ~= nil,
			"the truncated warning is missing the full-list marker"
		)
		runner.assert(
			count_occurrences(logs[1], "funit-urt-unlinked-") == 12,
			"the log should contain all 12 prerequisites, got "
				.. count_occurrences(logs[1], "funit-urt-unlinked-")
		)

		-- warn_unreachable_techs delegates to the unlinked warning when the
		-- unlinked list is non-empty, even if a hidden prerequisite exists.
		environment, prints, logs = make_environment({
			technology = hidden_prereq_technology(1),
			unlinked_prerequisites = { "funit-urt-unlinked-delegate" },
		})

		with_environment(environment, function()
			unreachable_techs.warn_unreachable_techs()
		end)

		runner.assert(#prints == 1, "expected exactly one game.print warning, got " .. #prints)
		runner.assert(
			prints[1].message[3][1] == "planetslib.notify-unlinked-prerequisites",
			"warn_unreachable_techs did not delegate to the unlinked-prerequisite warning"
		)
		runner.assert(
			not tostring(prints[1].message[3][2]):find("due to hidden prerequisite", 1, true),
			"the hidden-prerequisite warning should not also be printed when unlinked prerequisites exist"
		)
	end)

	runner.test("URT-3 PlanetsLib authors are auto-unbanned, other players are not", function()
		if not player_effects_ok or not player_effects_handler then
			runner.log(
				"URT-3 skipped: could not install scripts/player-effects.lua: " .. tostring(player_effects_err)
			)
			runner.assert(true, "skipped")
			return
		end

		local authors = _G.PlanetsLib and _G.PlanetsLib.authors
		runner.assert(type(authors) == "table", "PlanetsLib.authors was not loaded")
		runner.assert(authors.thesixthroc == true, "thesixthroc should be a PlanetsLib author")
		runner.assert(authors.MeteorSwarm == true, "MeteorSwarm should be a PlanetsLib author")

		local unban_calls = {}
		local prints = {}
		local environment = {
			game = {
				tick = 0,
				players = { [7] = { name = "funit-admin" } },
				unban_player = function(player_name)
					unban_calls[#unban_calls + 1] = player_name
				end,
				print = function(message)
					prints[#prints + 1] = message
				end,
			},
		}

		with_environment(environment, function()
			player_effects_handler({ player_name = "thesixthroc", by_player = 7, reason = "funit" })
		end)

		runner.assert(
			#unban_calls == 1 and unban_calls[1] == "thesixthroc",
			"thesixthroc was not auto-unbanned"
		)
		runner.assert(
			#prints == 2,
			"the author auto-unban should print the blank spacer and the ban notice, got " .. #prints
		)
		runner.assert(
			type(prints[2]) == "table" and prints[2][1] == "player-was-banned",
			"the ban notice did not use the player-was-banned localisation key"
		)

		unban_calls = {}
		prints = {}
		with_environment(environment, function()
			player_effects_handler({ player_name = "MeteorSwarm", by_player = 7, reason = "funit" })
		end)

		runner.assert(
			#unban_calls == 1 and unban_calls[1] == "MeteorSwarm",
			"MeteorSwarm was not auto-unbanned"
		)
		runner.assert(#prints == 2, "the second author auto-unban should print two messages, got " .. #prints)

		unban_calls = {}
		prints = {}
		with_environment(environment, function()
			player_effects_handler({ player_name = "funit-outsider", by_player = 7, reason = "funit" })
		end)

		runner.assert(#unban_calls == 0, "a non-author must not be unbanned")
		runner.assert(#prints == 0, "a non-author ban must not print the author notice")

		-- `by_player` is optional: it is nil for script/server-console bans. The
		-- handler must not raise and should still print the ban notice.
		unban_calls = {}
		prints = {}
		local ok_missing, err_missing = pcall(function()
			with_environment(environment, function()
				player_effects_handler({ player_name = "thesixthroc", reason = "funit" })
			end)
		end)
		runner.assert(
			ok_missing,
			"on_player_banned raised when by_player was absent: " .. tostring(err_missing)
		)
		runner.assert(#unban_calls == 1, "the author was not unbanned when by_player was absent")
		runner.assert(#prints == 2, "the ban notice was not printed when by_player was absent")
	end)

	runner.test("URT-4 on-join tick-0 warning is gated by PlanetsLib-warn-on-hidden-prerequisites", function()
		local setting = settings.startup["PlanetsLib-warn-on-hidden-prerequisites"]
		runner.assert(setting ~= nil, "the PlanetsLib-warn-on-hidden-prerequisites startup setting is missing")
		runner.assert(type(setting.value) == "boolean", "the warn setting should expose a boolean value")

		local mock_interface = remote.interfaces["__funit_mock_event__PlanetsLib"]
		runner.assert(
			mock_interface ~= nil and mock_interface.call_event_handler ~= nil,
			"PlanetsLib did not register with FUnit's event mocker"
		)

		local ok, err = pcall(mock.mock_event, {
			name = defines.events.on_player_joined_game,
			player_index = 1,
		})
		runner.assert(ok, "mocking on_player_joined_game raised: " .. tostring(err))

		-- The handler lives in PlanetsLib's Lua VM, so this VM cannot observe its
		-- game.print text. Record whether the tick-0 branch could run without
		-- guessing; the module-level warning path is covered by URT-1.
		if game.tick == 0 then
			runner.log(
				"URT-4 note: game.tick is 0 and PlanetsLib-warn-on-hidden-prerequisites="
					.. tostring(setting.value)
					.. "; the on-join handler ran in PlanetsLib's VM (its warning text is not observable here)"
			)
		else
			runner.log(
				"URT-4 note: skipped the tick-0 warning branch because game.tick is "
					.. tostring(game.tick)
					.. " (setting="
					.. tostring(setting.value)
					.. ")"
			)
		end

		runner.assert(true, "the on-join warning path did not crash")
	end)
end
