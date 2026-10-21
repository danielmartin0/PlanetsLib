-- Asteroid route helpers (lib.asteroids).
--
-- The route builder is pure, so it can be required directly from the runtime
-- scenario. The setter writes prototypes and is exercised by the `asteroids`
-- data fixture (AST-11).

local EPSILON = 1e-9

local function approx(actual, expected, tolerance)
	return type(actual) == "number"
		and type(expected) == "number"
		and math.abs(actual - expected) <= (tolerance or EPSILON)
end

local function find_definition(definitions, name)
	for _, definition in ipairs(definitions) do
		if definition.asteroid == name then
			return definition
		end
	end
	return nil
end

local function find_spawn_point(definition, distance)
	for _, point in ipairs(definition.spawn_points or {}) do
		if approx(point.distance, distance) then
			return point
		end
	end
	return nil
end

local function base_route()
	return {
		{
			position = 0.1,
			ratios = { metallic = 3, carbonic = 2, oxide = 1 },
			spawn = { chunk = 0.0125 },
		},
		{
			position = 0.9,
			ratios = { metallic = 4, carbonic = 3, oxide = 1 },
			spawn = { chunk = 0.0025 },
		},
	}
end

local function fixture_entries(runner, suite)
	local bag = prototypes.mod_data["PlanetsLib-funit-results"]
	runner.assert(bag, "results bag missing; is planetslib-funit-data enabled?")
	local entries = bag.data[suite]
	runner.assert(entries, "no data-stage results recorded for '" .. suite .. "'")
	return entries
end

return function(runner)
	local asteroids = require("__PlanetsLib__.lib.asteroids")

	runner.test("AST-1 connection output shape and vanilla-style values", function()
		local route = asteroids.asteroid_route(base_route())
		local definitions = route:connection()

		runner.assert(#definitions == 3, "expected one chunk entry per asteroid family, got " .. #definitions)

		local metallic = find_definition(definitions, "metallic-asteroid-chunk")
		runner.assert(metallic, "metallic chunk entry is missing")
		runner.assert(metallic.type == "asteroid-chunk", "chunk entries must set type = asteroid-chunk")
		runner.assert(#metallic.spawn_points == 2, "expected spawn points at 0.1 and 0.9")

		local start = find_spawn_point(metallic, 0.1)
		local finish = find_spawn_point(metallic, 0.9)
		runner.assert(start and finish, "metallic spawn points are incomplete")
		runner.assert(approx(start.probability, 0.0125), "metallic chunk probability at 0.1 is wrong")
		runner.assert(approx(finish.probability, 0.0025), "metallic chunk probability at 0.9 is wrong")
		runner.assert(approx(start.speed, 1 / 60), "default speed should be 1 m/s")
		runner.assert(approx(start.angle_when_stopped, 1), "chunk angle should default to 1")

		local carbonic = find_definition(definitions, "carbonic-asteroid-chunk")
		runner.assert(carbonic, "carbonic chunk entry is missing")
		local carbonic_start = find_spawn_point(carbonic, 0.1)
		runner.assert(
			approx(carbonic_start.probability, 0.0125 * 2 / 3),
			"carbonic probability should be scaled by ratio / max ratio"
		)

		local oxide = find_definition(definitions, "oxide-asteroid-chunk")
		runner.assert(oxide, "oxide chunk entry is missing")
		runner.assert(
			approx(find_spawn_point(oxide, 0.1).probability, 0.0125 / 3),
			"oxide probability should be scaled by ratio / max ratio"
		)
	end)

	runner.test("AST-2 planet output and default position", function()
		local route = asteroids.asteroid_route(base_route())
		local definitions = route:planet(0.9)

		runner.assert(#definitions == 3, "expected one planet entry per family")
		local metallic = find_definition(definitions, "metallic-asteroid-chunk")
		runner.assert(metallic, "metallic planet entry is missing")
		runner.assert(approx(metallic.probability, 0.0025), "metallic probability at 0.9 is wrong")
		runner.assert(metallic.spawn_points == nil, "planet entries must not have spawn_points")
		runner.assert(metallic.distance == nil, "planet entries must not have distance")
		runner.assert(metallic.type == "asteroid-chunk", "chunk planet entries must set type")
		runner.assert(approx(metallic.speed, 1 / 60), "planet speed is wrong")
		runner.assert(approx(metallic.angle_when_stopped, 1), "planet angle is wrong")

		local default_definitions = route:planet()
		runner.assert(#default_definitions == #definitions, "planet() should default to position 0.9")
		runner.assert(
			approx(find_definition(default_definitions, "metallic-asteroid-chunk").probability, 0.0025),
			"planet() default position is not 0.9"
		)

		local middle = route:planet(0.5)
		runner.assert(
			approx(find_definition(middle, "metallic-asteroid-chunk").probability, 0.0075),
			"planet probability should be interpolated at an intermediate position"
		)
	end)

	runner.test("AST-3 independent curves, interpolation and angle interpolation", function()
		local route = asteroids.asteroid_route {
			{
				position = 0.1,
				ratios = { metallic = 3, carbonic = 2, oxide = 1 },
				spawn = {
					chunk = { probability = 0.002, angle_when_stopped = 1 },
					medium = 0.002,
				},
			},
			{
				position = 0.5,
				ratios = { metallic = 1, carbonic = 1, oxide = 1 },
			},
			{
				position = 0.9,
				ratios = { metallic = 1, carbonic = 1, oxide = 1 },
				spawn = {
					chunk = { probability = 0.004, angle_when_stopped = 0.5 },
					medium = 0.004,
				},
			},
		}

		local definitions = route:connection()
		local metallic_chunk = find_definition(definitions, "metallic-asteroid-chunk")
		runner.assert(metallic_chunk, "metallic chunk entry is missing")
		local middle = find_spawn_point(metallic_chunk, 0.5)
		runner.assert(middle, "the ratio keyframe at 0.5 should be a spawn point")
		runner.assert(approx(middle.probability, 0.003), "chunk probability is not interpolated at 0.5")
		runner.assert(approx(middle.angle_when_stopped, 0.75), "angle_when_stopped is not interpolated")

		local metallic_medium = find_definition(definitions, "medium-metallic-asteroid")
		runner.assert(metallic_medium, "medium-metallic entry is missing")
		runner.assert(
			approx(find_spawn_point(metallic_medium, 0.5).probability, 0.003),
			"medium probability is not interpolated at 0.5"
		)

		-- Ratios are normalised per keyframe before interpolation, matching Space
		-- Age. The two endpoints here have different dominant families, so
		-- normalising after interpolation would produce a different result.
		local crossing = asteroids.asteroid_route {
			{
				position = 0.1,
				ratios = { metallic = 2, carbonic = 5, oxide = 1 },
				spawn = { chunk = 0.01 },
			},
			{
				position = 0.5,
				spawn = { chunk = 0.02 },
			},
			{
				position = 0.9,
				ratios = { metallic = 4, carbonic = 3, oxide = 1 },
				spawn = { chunk = 0.03 },
			},
		}
		local crossing_definitions = crossing:connection()
		runner.assert(
			approx(find_spawn_point(find_definition(crossing_definitions, "metallic-asteroid-chunk"), 0.5).probability, 0.014),
			"per-keyframe-normalised metallic ratio is wrong at 0.5"
		)
		runner.assert(
			approx(find_spawn_point(find_definition(crossing_definitions, "carbonic-asteroid-chunk"), 0.5).probability, 0.0175),
			"per-keyframe-normalised carbonic ratio is wrong at 0.5"
		)
		runner.assert(
			approx(find_spawn_point(find_definition(crossing_definitions, "oxide-asteroid-chunk"), 0.5).probability, 0.0045),
			"per-keyframe-normalised oxide ratio is wrong at 0.5"
		)
	end)

	runner.test("AST-4 endpoint clamping", function()
		local route = asteroids.asteroid_route {
			{
				position = 0.2,
				ratios = { metallic = 1 },
				spawn = { chunk = 0.01 },
			},
			{
				position = 0.8,
				ratios = { metallic = 1 },
				spawn = { chunk = 0.02 },
			},
		}

		local definitions = route:connection()
		local metallic = find_definition(definitions, "metallic-asteroid-chunk")
		runner.assert(metallic, "metallic chunk entry is missing")
		runner.assert(
			approx(find_spawn_point(metallic, 0.2).probability, 0.01),
			"the first spawn point should be used at the start"
		)
		runner.assert(
			approx(find_spawn_point(metallic, 0.8).probability, 0.02),
			"the last spawn point should be used at the end"
		)

		local early = route:planet(0.05)
		runner.assert(
			approx(find_definition(early, "metallic-asteroid-chunk").probability, 0.01),
			"planet positions before the first control point should clamp"
		)
		local late = route:planet(0.95)
		runner.assert(
			approx(find_definition(late, "metallic-asteroid-chunk").probability, 0.02),
			"planet positions after the last control point should clamp"
		)
	end)

	runner.test("AST-5 custom family gets default prototype names", function()
		local route = asteroids.asteroid_route {
			{
				position = 0.1,
				ratios = { auric = 1 },
				spawn = { chunk = 0.01 },
			},
			{
				position = 0.9,
				ratios = { auric = 1 },
				spawn = { chunk = 0.02, small = 0.003 },
			},
		}

		local definitions = route:connection()
		runner.assert(find_definition(definitions, "auric-asteroid-chunk"), "default chunk name is wrong")
		runner.assert(find_definition(definitions, "small-auric-asteroid"), "default small name is wrong")

		local planet = route:planet(0.9)
		runner.assert(find_definition(planet, "auric-asteroid-chunk"), "planet default chunk name is wrong")
	end)

	runner.test("AST-6 explicit names map limits the emitted sizes", function()
		local route = asteroids.asteroid_route {
			names = {
				anorthite = { chunk = "anorthite-chunk" },
			},
			{
				position = 0.1,
				ratios = { metallic = 1, anorthite = 1 },
				spawn = { chunk = 0.01, medium = 0.002 },
			},
			{
				position = 0.9,
				ratios = { metallic = 1, anorthite = 1 },
				spawn = { chunk = 0.02, medium = 0.004 },
			},
		}

		local definitions = route:connection()
		local anorthite_chunk = find_definition(definitions, "anorthite-chunk")
		runner.assert(anorthite_chunk, "explicit custom chunk name is missing")
		runner.assert(anorthite_chunk.type == "asteroid-chunk", "custom chunk must set type")

		runner.assert(
			find_definition(definitions, "metallic-asteroid-chunk"),
			"families without a names map should still use default names"
		)
		runner.assert(
			find_definition(definitions, "medium-metallic-asteroid"),
			"metallic medium entries should still be emitted"
		)
		runner.assert(
			find_definition(definitions, "medium-anorthite-asteroid") == nil,
			"sizes omitted from an explicit names map must not be emitted"
		)
		runner.assert(
			find_definition(definitions, "anorthite-asteroid-chunk") == nil,
			"the default name must not be used when an explicit map is supplied"
		)
	end)

	runner.test("AST-7 zero-probability families and sizes are omitted", function()
		local route = asteroids.asteroid_route {
			{
				position = 0.1,
				ratios = { metallic = 1, zero = 0 },
				spawn = { chunk = 0.01 },
			},
			{
				position = 0.9,
				ratios = { metallic = 1, zero = 0 },
				spawn = { chunk = 0.02 },
			},
		}

		local definitions = route:connection()
		runner.assert(find_definition(definitions, "metallic-asteroid-chunk"), "metallic entry is missing")
		runner.assert(
			find_definition(definitions, "zero-asteroid-chunk") == nil,
			"all-zero families must be omitted from connection output"
		)
		runner.assert(
			find_definition(route:planet(0.9), "zero-asteroid-chunk") == nil,
			"all-zero families must be omitted from planet output"
		)

		local empty = asteroids.asteroid_route {
			{
				position = 0.1,
				ratios = { metallic = 1 },
				spawn = { chunk = 0 },
			},
			{
				position = 0.9,
				ratios = { metallic = 1 },
				spawn = { chunk = 0 },
			},
		}
		runner.assert(#empty:connection() == 0, "an all-zero route must return no connection definitions")
		runner.assert(#empty:planet(0.9) == 0, "an all-zero route must return no planet definitions")
	end)

	runner.test("AST-8 route generation does not mutate its input", function()
		local spec = base_route()
		local route = asteroids.asteroid_route(spec)

		runner.assert(spec[1].position == 0.1, "frame position was mutated")
		runner.assert(spec[1].ratios.metallic == 3, "ratio was mutated")
		runner.assert(spec[1].spawn.chunk == 0.0125, "spawn probability was mutated")
		runner.assert(#spec == 2, "the number of frames was mutated")

		local first = route:connection()
		local second = route:connection()
		runner.assert(first ~= second, "each call must return a fresh table")
		find_definition(first, "metallic-asteroid-chunk").spawn_points[1].probability = 99
		runner.assert(
			approx(find_definition(second, "metallic-asteroid-chunk").spawn_points[1].probability, 0.0125),
			"mutating one result must not affect later results"
		)
	end)

	runner.test("AST-9 Space Age style table conversion", function()
		local vanilla = {
			probability_on_range_chunk = {
				{ position = 0.1, probability = 0.0125, angle_when_stopped = 1 },
				{ position = 0.9, probability = 0.0025, angle_when_stopped = 1 },
			},
			probability_on_range_medium = {
				{ position = 0.1, probability = 0, angle_when_stopped = 0.6 },
				{ position = 0.5, probability = 0.0075, angle_when_stopped = 0.6 },
				{ position = 0.9, probability = 0.0025, angle_when_stopped = 0.6 },
			},
			type_ratios = {
				{ position = 0.1, ratios = { 3, 2, 1, 0 } },
				{ position = 0.9, ratios = { 4, 3, 1, 0 } },
			},
		}

		local route = asteroids.asteroid_route(vanilla)
		local definitions = route:connection()
		local metallic_chunk = find_definition(definitions, "metallic-asteroid-chunk")
		runner.assert(metallic_chunk, "converted metallic chunk entry is missing")
		runner.assert(
			approx(find_spawn_point(metallic_chunk, 0.1).probability, 0.0125),
			"converted chunk probability is wrong"
		)

		local metallic_medium = find_definition(definitions, "medium-metallic-asteroid")
		runner.assert(metallic_medium, "converted medium entry is missing")
		runner.assert(
			approx(find_spawn_point(metallic_medium, 0.5).probability, 0.0075),
			"converted medium probability at 0.5 is wrong"
		)
		runner.assert(
			approx(find_spawn_point(metallic_medium, 0.5).angle_when_stopped, 0.6),
			"converted per-point angle is wrong"
		)
		runner.assert(
			approx(find_spawn_point(find_definition(definitions, "medium-carbonic-asteroid"), 0.5).probability, 0.0075 * 17 / 24),
			"converted carbonic ratio at 0.5 should match Space Age's per-keyframe normalisation"
		)
		runner.assert(
			approx(find_spawn_point(find_definition(definitions, "medium-oxide-asteroid"), 0.5).probability, 0.0075 * 7 / 24),
			"converted oxide ratio at 0.5 should match Space Age's per-keyframe normalisation"
		)

		runner.assert(vanilla.type_ratios[1].ratios[1] == 3, "the source table was mutated")
		runner.assert(#vanilla.probability_on_range_chunk == 2, "the source table was mutated")

		local custom = {
			probability_on_range_chunk = {
				{ position = 0.1, probability = 0.01, angle_when_stopped = 1 },
				{ position = 0.9, probability = 0.02, angle_when_stopped = 1 },
			},
			type_ratios = {
				{ position = 0.1, ratios = { 1, 1, 1, 5 } },
				{ position = 0.9, ratios = { 1, 1, 1, 5 } },
			},
		}
		local custom_route = asteroids.asteroid_route(custom, {
			families = { "metallic", "carbonic", "oxide", "auric" },
		})
		runner.assert(
			find_definition(custom_route:connection(), "auric-asteroid-chunk"),
			"custom families option was not honoured"
		)

		local promethium = {
			has_promethium_asteroids = true,
			probability_on_range_chunk = {
				{ position = 0.1, probability = 0.01, angle_when_stopped = 1 },
			},
			type_ratios = {
				{ position = 0.1, ratios = { 1, 1, 1, 1 } },
			},
		}
		runner.assert(
			find_definition(asteroids.asteroid_route(promethium):connection(), "promethium-asteroid-chunk"),
			"has_promethium_asteroids should include the fourth family"
		)
	end)

	runner.test("AST-10 validation errors", function()
		local cases = {
			{ label = "empty spec", spec = {} },
			{
				label = "missing ratios",
				spec = { { position = 0.1, spawn = { chunk = 0.01 } } },
			},
			{
				label = "missing spawn",
				spec = { { position = 0.1, ratios = { metallic = 1 } } },
			},
			{
				label = "duplicate positions",
				spec = {
					{ position = 0.1, ratios = { metallic = 1 }, spawn = { chunk = 0.01 } },
					{ position = 0.1, ratios = { metallic = 1 }, spawn = { chunk = 0.02 } },
				},
			},
			{
				label = "out-of-range position",
				spec = { { position = 1.5, ratios = { metallic = 1 }, spawn = { chunk = 0.01 } } },
			},
			{
				label = "unknown size",
				spec = {
					{ position = 0.1, ratios = { metallic = 1 }, spawn = { large = 0.01 } },
				},
			},
			{
				label = "probability above one",
				spec = {
					{ position = 0.1, ratios = { metallic = 1 }, spawn = { chunk = 2 } },
				},
			},
			{
				label = "inconsistent ratio families",
				spec = {
					{ position = 0.1, ratios = { metallic = 1, oxide = 1 }, spawn = { chunk = 0.01 } },
					{ position = 0.9, ratios = { metallic = 1 }, spawn = { chunk = 0.02 } },
				},
			},
			{
				label = "names family without ratios",
				spec = {
					names = { anorthite = { chunk = "anorthite-chunk" } },
					{ position = 0.1, ratios = { metallic = 1 }, spawn = { chunk = 0.01 } },
				},
			},
			{
				label = "unknown frame field",
				spec = {
					{ position = 0.1, ratio = { metallic = 1 }, spawn = { chunk = 0.01 } },
				},
			},
		}

		for _, case in ipairs(cases) do
			local ok, err = pcall(function()
				asteroids.asteroid_route(case.spec)
			end)
			runner.assert(not ok, "expected an error for " .. case.label)
			runner.assert(
				tostring(err):find("PlanetsLib.asteroid_route", 1, true),
				"error for " .. case.label .. " should name the API, got: " .. tostring(err)
			)
		end

		local ok = pcall(function()
			asteroids.asteroid_route(base_route(), { families = { "metallic" } })
		end)
		runner.assert(not ok, "options on a native route spec should be rejected")
	end)

	runner.test("AST-11 set_asteroid_spawn_definitions data fixture", function()
		local entries = fixture_entries(runner, "asteroids")
		runner.assert(entries["AST-11"], "AST-11 fixture result is missing")
		runner.assert(entries["AST-11"].ok, entries["AST-11"].err)
	end)
end
