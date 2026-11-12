-- Runtime tests for scripts/unreachable-techs.lua.
--
-- The module is required into this Lua state (the headless FUnit scenario), so
-- its global reads (`prototypes`, `game`, `log`) can be replaced with small
-- test doubles for the duration of a test. This never touches PlanetsLib's own
-- runtime Lua state.
--
-- URT-1..2 drive warn_unreachable_techs / warn_unlinked_prerequisites with fake
-- prototype tables. URT-4 asserts the real on-join gating through the
-- `should_warn_on_join` / `warn_on_join` seams, then also routes the event
-- through FUnit's mocker to prove the handler is registered.

local function seam(name)
	local iface = remote.interfaces["planetslib_funit"]
	return iface ~= nil and iface[name] ~= nil
end

local function seam_call(name, ...)
	return remote.call("planetslib_funit", name, ...)
end

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
			print = function(message, print_settings)
				prints[#prints + 1] = { message = message, settings = print_settings }
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

	runner.test("URT-4 on-join tick-0 warning is gated by PlanetsLib-warn-on-hidden-prerequisites", function()
		local setting = settings.startup["PlanetsLib-warn-on-hidden-prerequisites"]
		runner.assert(setting ~= nil, "the PlanetsLib-warn-on-hidden-prerequisites startup setting is missing")
		runner.assert(type(setting.value) == "boolean", "the warn setting should expose a boolean value")

		runner.assert(
			seam("should_warn_on_join"),
			"PlanetsLib did not expose the should_warn_on_join test seam"
		)
		runner.assert(seam("warn_on_join"), "PlanetsLib did not expose the warn_on_join test seam")

		-- The decision is a pure function of (tick, setting), so all axes can be
		-- asserted without touching startup settings: only the first tick of a
		-- newly started save with the setting enabled should warn.
		local cases = {
			{ tick = 0, setting = true, expected = true, label = "tick 0 with the setting enabled" },
			{ tick = 1, setting = true, expected = false, label = "a later tick with the setting enabled" },
			{ tick = 0, setting = false, expected = false, label = "tick 0 with the setting disabled" },
			{ tick = 0, setting = nil, expected = false, label = "tick 0 with the setting unset" },
		}
		for _, case in ipairs(cases) do
			runner.assert(
				unreachable_techs.should_warn_on_join(case.tick, case.setting) == case.expected,
				"should_warn_on_join must return "
					.. tostring(case.expected)
					.. " for "
					.. case.label
			)
			runner.assert(
				seam_call("should_warn_on_join", case.tick, case.setting) == case.expected,
				"the should_warn_on_join seam must return "
					.. tostring(case.expected)
					.. " for "
					.. case.label
			)
		end

		-- The seam wraps control.lua's real gating: it returns the decision and
		-- must not raise. At tick 0 that decision is the current setting value;
		-- on a later tick it is always false.
		local ok, result = pcall(seam_call, "warn_on_join")
		runner.assert(ok, "warn_on_join raised: " .. tostring(result))
		if game.tick == 0 then
			runner.assert(
				result == setting.value,
				"warn_on_join at tick 0 must return the current setting value ("
					.. tostring(setting.value)
					.. "), got "
					.. tostring(result)
			)
		else
			runner.assert(
				result == false,
				"warn_on_join must not warn after tick 0 (game.tick is " .. tostring(game.tick) .. ")"
			)
			runner.log("URT-4 limitation: game.tick is not 0, so only the false gating branch was observable")
		end

		-- Also route the on-join event through FUnit's mocker to prove the
		-- handler is registered and does not crash. Its printed text lives in
		-- PlanetsLib's VM, so the assertions above are the real coverage.
		local mock_interface = remote.interfaces["__funit_mock_event__PlanetsLib"]
		runner.assert(
			mock_interface ~= nil and mock_interface.call_event_handler ~= nil,
			"PlanetsLib did not register with FUnit's event mocker"
		)

		local mock_ok, mock_err = pcall(mock.mock_event, {
			name = defines.events.on_player_joined_game,
			player_index = 1,
		})
		runner.assert(mock_ok, "mocking on_player_joined_game raised: " .. tostring(mock_err))
	end)
end
