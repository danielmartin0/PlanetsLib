-- Pure (runtime-stage) tests for lib.lib, lib.predicates and
-- lib.remove-replace-object ("rro").
--
-- These modules are stateless. rro is normally required as a data-stage module,
-- so the suite pre-seeds `package.loaded` for its relative require and installs
-- the core `util` table (which also defines `table.deepcopy` at runtime).

local function sorted(tbl)
	local out = {}
	for _, value in pairs(tbl) do
		out[#out + 1] = value
	end
	table.sort(out)
	return out
end

return function(runner)
	local predicates = require("__PlanetsLib__.lib.predicates")
	package.loaded["lib.predicates"] = predicates
	package.loaded["util"] = require("__core__.lualib.util")
	_G.util = package.loaded["util"]

	local lib = require("__PlanetsLib__.lib.lib")
	local rro = require("__PlanetsLib__.lib.remove-replace-object")

	-- == lib.lib == == --

	runner.test("LIB-1 lib.merge copies and overrides, with 'nil' deleting", function()
		local old = { a = 1, keep = { nested = true }, remove_me = "x" }
		local merged = lib.merge(old, { a = 2, remove_me = "nil", added = "y" })

		runner.assert(merged.a == 2, "override was not applied")
		runner.assert(merged.remove_me == nil, "'nil' sentinel did not delete the key")
		runner.assert(merged.added == "y", "new key was not added")
		runner.assert(merged.keep.nested == true, "untouched nested value was not preserved")
		runner.assert(old.a == 1 and old.remove_me == "x", "lib.merge must not mutate the input table")
		runner.assert(merged.keep ~= old.keep, "lib.merge must deep-copy the input table")
	end)

	runner.test("LIB-2 lib.find by value and by predicate", function()
		local t = { first = "a", second = "b", third = "c" }

		local value, key = lib.find(t, "b")
		runner.assert(value == "b" and key == "second", "lib.find by value returned the wrong entry")

		value, key = lib.find(t, function(v, k)
			return k == "third"
		end)
		runner.assert(value == "c" and key == "third", "lib.find by predicate returned the wrong entry")

		runner.assert(lib.find(t, "missing") == nil, "lib.find should return nil when nothing matches")
	end)

	runner.test("LIB-3 lib.contains checks values", function()
		runner.assert(lib.contains({ "a", "b" }, "b"), "existing value not found")
		runner.assert(not lib.contains({ "a", "b" }, "c"), "missing value reported as present")
		runner.assert(not lib.contains({}, "a"), "empty table must not contain anything")
	end)

	runner.test("LIB-4 lib.sort is a stable-enough bubble sort using compare_fn(a, b)", function()
		local arr = { 5, 1, 4, 2, 3 }
		lib.sort(arr, function(a, b)
			return a < b
		end)
		runner.assert(table.concat(arr, ",") == "1,2,3,4,5", "ascending sort failed: " .. table.concat(arr, ","))

		arr = { 1, 2, 3 }
		lib.sort(arr, function(a, b)
			return a > b
		end)
		runner.assert(table.concat(arr, ",") == "3,2,1", "descending sort failed: " .. table.concat(arr, ","))
	end)

	runner.test("LIB-5 lib.wrap_single_config accepts one config or a list", function()
		local single = { name = "funit-single" }
		local wrapped = lib.wrap_single_config(single)
		runner.assert(wrapped[1] == single and #wrapped == 1, "single config was not wrapped")

		local list = { { name = "a" }, { name = "b" } }
		runner.assert(lib.wrap_single_config(list) == list, "a list must be returned unchanged")
	end)

	runner.test("LIB-6 lib.event_name and event lists", function()
		runner.assert(lib.event_name(defines.events.on_tick) == "on_tick", "event_name failed for on_tick")
		runner.assert(
			lib.event_name(-123456789) == "-123456789",
			"unknown event ids must fall back to tostring"
		)

		runner.assert(lib.contains(lib.build_events, defines.events.on_built_entity), "build_events is missing on_built_entity")
		runner.assert(lib.contains(lib.build_events, defines.events.script_raised_built), "build_events is missing script_raised_built")
		runner.assert(lib.contains(lib.destroy_events, defines.events.on_entity_died), "destroy_events is missing on_entity_died")
		runner.assert(lib.contains(lib.destroy_events, defines.events.script_raised_destroy), "destroy_events is missing script_raised_destroy")
	end)

	runner.test("LIB-7 lib.detailed_log is callable and setting-gated", function()
		local setting = settings.startup["PlanetsLib-enable-detailed-logs"]
		runner.assert(setting ~= nil, "the detailed-logs setting should exist")
		lib.detailed_log("funit detailed log smoke test")
	end)

	-- == predicates == == --

	runner.test("LIB-8 predicates.compare supports every operator", function()
		local cases = {
			{ "<", 5, 4, true }, { "<", 5, 5, false },
			{ "<=", 5, 5, true }, { "<=", 5, 6, false },
			{ ">", 5, 6, true }, { ">", 5, 5, false },
			{ ">=", 5, 5, true }, { ">=", 5, 4, false },
			{ "==", 5, 5, true }, { "==", 5, 6, false },
			{ "~=", 5, 6, true }, { "~=", 5, 5, false },
		}
		for _, case in ipairs(cases) do
			local predicate = predicates.compare(case[1], case[2])
			runner.assert(
				predicate(case[3]) == case[4],
				("compare(%q, %s)(%s) returned the wrong value"):format(case[1], case[2], case[3])
			)
		end
	end)

	runner.test("LIB-9 predicates.compare rejects unknown operators and equals() delegates", function()
		local ok = pcall(predicates.compare, "!=", 1)
		runner.assert(not ok, "an unsupported comparator must raise an error")

		runner.assert(predicates.equals(3)(3), "equals() should match the same value")
		runner.assert(not predicates.equals(3)(4), "equals() should reject a different value")
	end)

	-- == remove-replace-object == == --

	runner.test("LIB-10 rro.deep_equals compares scalars, tables, '_any' and functions", function()
		runner.assert(rro.deep_equals(1, 1), "equal scalars were not equal")
		runner.assert(not rro.deep_equals(1, 2), "different scalars were equal")
		runner.assert(rro.deep_equals({ a = 1, b = { 2, 3 } }, { a = 1, b = { 2, 3 } }), "equal nested tables were not equal")
		runner.assert(not rro.deep_equals({ a = 1 }, { a = 1, b = 2 }), "extra key must differ")
		runner.assert(not rro.deep_equals({ a = 1, b = 2 }, { a = 1 }), "missing key must differ")

		runner.assert(rro.deep_equals("_any", 42), "'_any' should match a scalar")
		runner.assert(rro.deep_equals({ 1, 2 }, "_any"), "'_any' should match a table")

		runner.assert(
			rro.deep_equals(function(other)
				return other > 3
			end, 4),
			"a function predicate should be called"
		)

		local ok, err = pcall(rro.deep_equals, "_any", "_any")
		runner.assert(not ok and tostring(err):find("_any", 1, true), "two '_any' values must raise an error")
	end)

	runner.test("LIB-11 rro.remove removes one matching entry", function()
		local list = { "a", "b", "a", "c" }
		rro.remove(list, "a")
		runner.assert(#list == 3, "exactly one entry should be removed")
		runner.assert(rro.contains(list, "a"), "only the last matching entry should be removed")
		runner.assert(rro.contains(list, "b") and rro.contains(list, "c"), "other entries must be preserved")
	end)

	runner.test("LIB-12 rro.replace and replace_no_duplicates", function()
		local list = { "a", "b", "c" }
		rro.replace(list, "b", "B")
		runner.assert(table.concat(list, ",") == "a,B,c", "plain replace failed: " .. table.concat(list, ","))

		local ok = pcall(rro.replace, list, "a", nil)
		runner.assert(not ok, "replace with a nil replacement must raise (use remove)")

		rro.replace(list, "a", function(value)
			return value .. "!"
		end)
		runner.assert(rro.contains(list, "a!"), "function replacement was not applied")

		local duplicates = { "x", "y" }
		rro.replace_no_duplicates(duplicates, "x", "y")
		runner.assert(#duplicates == 1 and duplicates[1] == "y", "no-duplicates replace should collapse the list")
	end)

	runner.test("LIB-13 rro.deep_replace and deep_gsub work at the top level", function()
		local list = { "replace-me", "keep" }
		rro.deep_replace(list, "replace-me", "replaced")
		runner.assert(rro.contains(list, "replaced"), "deep_replace did not replace a top-level entry")

		local remove_me = { "a", "remove-me", "b" }
		rro.deep_replace(remove_me, "remove-me", nil)
		-- Removal sets the slot to nil (it does not compact the array), so do
		-- not use `#` on a table with a hole; check the slot and neighbours.
		runner.assert(
			remove_me[1] == "a" and remove_me[2] == nil and remove_me[3] == "b",
			"deep_replace with nil must remove the entry"
		)

		local gsub_list = { "funit-prefix-value" }
		rro.deep_gsub(gsub_list, "funit%-prefix%-", "funit-")
		runner.assert(gsub_list[1] == "funit-value", "deep_gsub did not gsub a top-level string")

		local nested_gsub = { { value = "funit-prefix-a" } }
		rro.deep_gsub(nested_gsub, "funit%-prefix%-", "funit-")
		runner.assert(nested_gsub[1].value == "funit-a", "deep_gsub did not recurse into nested tables")

		local excluded = { keep = "remove-me", other = "remove-me" }
		rro.deep_replace(excluded, "remove-me", "replaced", false, { "keep" })
		runner.assert(excluded.keep == "remove-me", "excluded_fields must be honoured")
		runner.assert(excluded.other == "replaced", "non-excluded fields must still be replaced")
	end)

	runner.test("LIB-14 rro.replace_field, replace_name and deep_replace_field", function()
		local list = { { name = "a", amount = 1 }, { name = "b", amount = 2 } }
		rro.replace_field(list, "name", "b", "c")
		runner.assert(list[2].name == "c", "replace_field did not rewrite the matching field")

		rro.replace_name(list, "a", "z")
		runner.assert(list[1].name == "z", "replace_name did not rewrite the name")

		local nested = { { name = "keep" }, { inner = { name = "old" } } }
		rro.deep_replace_field(nested, "name", "new")
		runner.assert(nested[1].name == "new" and nested[2].inner.name == "new", "deep_replace_field did not recurse")
	end)

	runner.test("LIB-15 rro.cut_paste moves every match", function()
		local from = { "a", "b", "a" }
		local to = { "z" }
		rro.cut_paste(from, to, "a")
		runner.assert(#from == 1 and from[1] == "b", "source list was not cleaned")
		runner.assert(#to == 3 and to[1] == "z", "destination list did not receive the matches")
	end)

	runner.test("LIB-16 rro containment helpers", function()
		local haystack = { { name = "a" }, { name = "b" } }
		runner.assert(rro.contains(haystack, { name = "a" }), "contains failed on a structural match")
		runner.assert(not rro.contains(haystack, { name = "c" }), "contains found a missing object")
		runner.assert(not rro.contains(nil, "a"), "contains(nil, ...) must be false")

		runner.assert(rro.contains_any(haystack, { { name = "c" }, { name = "b" } }), "contains_any missed a match")
		runner.assert(not rro.contains_any(haystack, { { name = "c" } }), "contains_any reported a false positive")
		runner.assert(rro.contains_all(haystack, { { name = "a" }, { name = "b" } }), "contains_all missed an entry")
		runner.assert(not rro.contains_all(haystack, { { name = "a" }, { name = "c" } }), "contains_all accepted a missing entry")

		local found = rro.find_contains(haystack, { name = "b" })
		runner.assert(found == haystack[2], "find_contains should return the stored object")
		runner.assert(rro.find_contains(haystack, { name = "c" }) == false, "find_contains must return false when missing")

		runner.assert(rro.find_many("funit-value", { "nope", "value" }), "find_many missed a pattern")
		runner.assert(not rro.find_many("funit-value", { "nope" }), "find_many reported a false positive")
		runner.assert(not rro.find_many("value", nil), "find_many(nil list) must be false")
	end)

	runner.test("LIB-17 rro.soft_insert does not duplicate", function()
		local list = { "a" }
		rro.soft_insert(list, "b")
		rro.soft_insert(list, "a")
		runner.assert(#list == 2 and list[2] == "b", "soft_insert duplicated or reordered")
	end)

	runner.test("LIB-18 rro.merge, util_merge and ammend", function()
		local old = { a = 1, drop = "x", keep = true }
		local merged = rro.merge(old, {
			a = function(value)
				return value + 1
			end,
			drop = "_nil",
			added = 2,
		})
		runner.assert(merged.a == 2, "function merge did not transform the old value")
		runner.assert(merged.drop == nil, "'_nil' sentinel did not delete the key")
		runner.assert(merged.added == 2 and merged.keep == true, "merge lost fields")
		runner.assert(old.a == 1, "merge must not mutate the input")

		local util_merged = rro.util_merge({ { a = 1 }, { a = 2 } })
		runner.assert(util_merged.a == 2, "util_merge did not delegate to merge")

		local target = { a = 1, drop = "x" }
		local returned = rro.ammend(target, { a = 3, drop = "_nil", added = 4 })
		runner.assert(target.a == 3, "ammend did not mutate its first argument")
		runner.assert(target.added == 4, "ammend did not copy an added field into its first argument")
		runner.assert(target.drop == nil, "ammend did not apply the '_nil' sentinel")
		runner.assert(returned == target, "ammend should return the table it mutated")
	end)

	runner.test("LIB-19 rro.get_concatenation copies both lists", function()
		local first = { 1, 2 }
		local second = { 3, 4 }
		local out = rro.get_concatenation(first, second)
		runner.assert(table.concat(out, ",") == "1,2,3,4", "concatenation failed: " .. table.concat(out, ","))
		runner.assert(out ~= first and out ~= second, "get_concatenation must return a copy")
	end)

	runner.test("LIB-20 rro.safe_find/safe_get, copy_fields, count, keys and range", function()
		local root = { a = { b = { c = 42 } }, present = "yes", list = { 1, 2, 3 } }
		runner.assert(rro.safe_find(root, { "a", "b", "c" }) == 42, "safe_find did not traverse")
		runner.assert(rro.safe_find(root, { "a", "missing", "c" }) == nil, "safe_find should stop at a nil level")
		runner.assert(rro.safe_get == rro.safe_find, "safe_get should alias safe_find")

		local target = { present = "old", only_here = true }
		rro.copy_fields(target, root, { "present", "absent" })
		runner.assert(target.present == "yes", "copy_fields did not copy a present field")
		runner.assert(target.absent == nil and target.only_here == true, "copy_fields must not clear missing fields")

		local shallow_target = {}
		rro.copy_fields(shallow_target, { nested = { value = 1 } }, { "nested" }, false)
		runner.assert(shallow_target.nested.value == 1, "shallow copy_fields lost the value")

		runner.assert(rro.count({ 1, 2, 3, 4 }, function(value)
			return value % 2 == 0
		end) == 2, "count predicate failed")

		local keys = sorted(rro.keys({ a = 1, b = 2 }))
		runner.assert(table.concat(keys, ",") == "a,b", "keys returned the wrong set")

		runner.assert(table.concat(rro.range(2, 4), ",") == "2,3,4", "range is inclusive of both ends")
	end)
end
