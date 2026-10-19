-- Planet-string encoding (lib.lib) and set/get/generate behavior (lib.planet-str).
--
-- planet-str is stored as a double. Doubles have 53 bits of integer precision,
-- so only strings of up to 6 bytes round-trip exactly; the 8-character limit in
-- the implementation is therefore not round-trip safe. Tests here stay within
-- the safe range (see the known-limitations list in ../AGENTS.md).

local RESULTS_MOD_DATA = "PlanetsLib-funit-results"

local function assert_fixture_namespace(runner, suite)
	local mod_data = prototypes.mod_data[RESULTS_MOD_DATA]
	runner.assert(mod_data, "mod-data prototype '" .. RESULTS_MOD_DATA .. "' is missing")
	local entries = mod_data.data[suite]
	runner.assert(entries, "no data-stage results recorded for '" .. suite .. "'")
	for id, entry in pairs(entries) do
		runner.assert(entry.ok, "data fixture '" .. id .. "' failed: " .. tostring(entry.err))
	end
end

return function(runner)
	package.loaded["util"] = require("__core__.lualib.util")
	local lib = require("__PlanetsLib__.lib.lib")

	runner.test("PSTR-1 encode/decode short strings and the empty string", function()
		runner.assert(lib.encode_string_to_double("") == 0, "empty string should encode to 0")
		runner.assert(lib.decode_double_to_string(0) == "", "0 should decode to the empty string")

		runner.assert(lib.encode_string_to_double("a") == 97, "single-byte encoding is wrong")
		runner.assert(
			lib.encode_string_to_double("abc123") == 56290669978209,
			"multi-byte encoding is wrong"
		)

		for _, value in ipairs({ "a", "ab", "abc", "funit", "abc123" }) do
			local encoded = lib.encode_string_to_double(value)
			local decoded = lib.decode_double_to_string(encoded)
			runner.assert(decoded == value, ("round-trip failed for %q: got %q"):format(value, decoded))
		end
	end)

	runner.test("PSTR-2 encode rejects strings longer than 8 characters", function()
		runner.assert(
			pcall(lib.encode_string_to_double, "12345678"),
			"8 characters should be accepted by the encoder"
		)
		runner.assert(
			not pcall(lib.encode_string_to_double, "123456789"),
			"9 characters must be rejected"
		)
	end)

	runner.test("PSTR-3 set/get/fallback data-stage behavior", function()
		assert_fixture_namespace(runner, "planet_str")
	end)

	runner.test("PSTR-4 data-final-fixes auto-assignment", function()
		assert_fixture_namespace(runner, "planet_str_auto")
	end)
end
