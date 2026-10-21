-- Composite icon helpers (lib.recipe, lib.icon-entry, lib.images).
--
-- build_icon_entry operates on prototype tables and the recipe helpers are pure,
-- so they can be tested at runtime. Functions that look prototypes up in
-- data.raw (detect_type/get_prototype/dual_icon/melting_icon) are covered by the
-- `icons` data fixture instead.

local support = require("__planetslib-funit-data__.tests.suites.support")

-- Every id the icons fixture records.
local ICONS_IDS = {
	"RCP-ICONS-1",
	"RCP-ICONS-2",
	"RCP-ICONS-3",
	"RCP-ICONS-4",
	"RCP-ICONS-5",
}

local function assert_shift(runner, entry, expected_x, expected_y, label)
	runner.assert(entry.shift ~= nil, label .. " has no shift")
	runner.assert(
		entry.shift[1] == expected_x and entry.shift[2] == expected_y,
		("%s shift is {%s, %s}, expected {%s, %s}"):format(
			label,
			entry.shift[1],
			entry.shift[2],
			expected_x,
			expected_y
		)
	)
end

return function(runner)
	package.loaded["util"] = require("__core__.lualib.util")
	_G.util = package.loaded["util"]
	package.loaded["lib.icon-entry"] = require("__PlanetsLib__.lib.icon-entry")

	local icon_entry = package.loaded["lib.icon-entry"]
	local recipe = require("__PlanetsLib__.lib.recipe")
	local images = require("__PlanetsLib__.lib.images")

	runner.test("RCP-1 crushing_recipe_icons layout", function()
		local icons = recipe.crushing_recipe_icons("funit/ore.png", 128)
		runner.assert(#icons == 2, "expected 2 icon entries")

		runner.assert(icons[1].icon == "funit/ore.png", "first icon should be the supplied sprite")
		runner.assert(icons[1].icon_size == 64, "first icon size should be 64")
		runner.assert(icons[1].scale == 50 / 128, "first icon scale should be 50/128")
		runner.assert(icons[1].draw_background == true, "first icon should draw a background")
		assert_shift(runner, icons[1], 0, -3, "first icon")

		runner.assert(
			icons[2].icon == "__PlanetsLib__/graphics/icons/generic-crushing.png",
			"second icon should be the generic crushing sprite"
		)
		runner.assert(icons[2].scale == 0.5 and icons[2].icon_size == 64, "second icon layout is wrong")
	end)

	runner.test("RCP-2 asteroid_crushing_recipe_icons layout", function()
		local icons = recipe.asteroid_crushing_recipe_icons("funit/asteroid.png", 128)
		runner.assert(#icons == 2, "expected 2 icon entries")
		runner.assert(icons[1].icon == "funit/asteroid.png", "first icon should be the supplied sprite")
		runner.assert(icons[1].scale == 50 / 128 and icons[1].icon_size == 64, "first icon layout is wrong")
		assert_shift(runner, icons[1], 0, -3, "first icon")
		runner.assert(
			icons[2].icon == "__PlanetsLib__/graphics/icons/asteroid-crushing.png",
			"second icon should be the asteroid crushing sprite"
		)
		runner.assert(icons[2].scale == 0.5, "second icon scale is wrong")
	end)

	runner.test("RCP-3 advanced_crushing_recipe_icons variants", function()
		local function product_order(icons)
			return table.concat({ icons[1].icon, icons[2].icon, icons[3].icon, icons[4].icon }, ",")
		end

		local checkerboard = recipe.advanced_crushing_recipe_icons("a", "p1", "p2")
		runner.assert(#checkerboard == 5, "an advanced crushing icon must have 5 entries")
		runner.assert(product_order(checkerboard) == "p1,p1,p2,p2", "checkerboard (default) order is wrong")
		runner.assert(checkerboard[5].icon == "a" and checkerboard[5].scale == 0.4, "asteroid icon is wrong")
		assert_shift(runner, checkerboard[1], -8, 8, "checkerboard product 1")
		assert_shift(runner, checkerboard[2], 8, -8, "checkerboard product 2")
		assert_shift(runner, checkerboard[3], -8, -8, "checkerboard product 3")
		assert_shift(runner, checkerboard[4], 8, 8, "checkerboard product 4")

		local explicit_checkerboard = recipe.advanced_crushing_recipe_icons("a", "p1", "p2", "checkerboard")
		runner.assert(product_order(explicit_checkerboard) == "p1,p1,p2,p2", "explicit checkerboard order is wrong")

		local horizontal = recipe.advanced_crushing_recipe_icons("a", "p1", "p2", "horizontal")
		runner.assert(product_order(horizontal) == "p2,p1,p1,p2", "horizontal order is wrong")

		local vertical = recipe.advanced_crushing_recipe_icons("a", "p1", "p2", "vertical")
		runner.assert(product_order(vertical) == "p1,p2,p1,p2", "vertical order is wrong")

		runner.assert(
			not pcall(recipe.advanced_crushing_recipe_icons, "a", "p1", "p2", "diagonal"),
			"an unknown variant must raise an error"
		)
	end)

	runner.test("RCP-4 build_icon_entry singular icon form", function()
		local prototype = { icon = "funit/singular.png", icon_size = 128 }
		local shift = { 3, -4 }

		local entry = icon_entry.build_icon_entry(prototype, "item", "funit", 0.4, shift)
		runner.assert(entry.icon == "funit/singular.png", "singular icon path was not copied")
		runner.assert(entry.icon_size == 128, "singular icon size was not copied")
		runner.assert(
			math.abs(entry.scale - 0.2) < 1e-12,
			"singular scale did not apply the icon-size correction"
		)
		runner.assert(entry.draw_background == true, "singular entry should draw a background")
		assert_shift(runner, entry, 3, -4, "singular entry")
		runner.assert(entry.shift ~= shift, "shift must be copied, not aliased")

		-- Without icon_size, no correction is applied.
		local uncorrected = icon_entry.build_icon_entry({ icon = "x.png" }, "item", "x", 0.5)
		runner.assert(uncorrected.scale == 0.5, "missing icon_size should leave the scale untouched")
		runner.assert(uncorrected.shift == nil, "nil shift should not create a shift")

		-- Without an icon, the placeholder is used.
		local placeholder = icon_entry.build_icon_entry(nil, "item", "funit-missing", 0.3, { 1, 2 })
		runner.assert(placeholder.icon == "__core__/graphics/filter-blacklist.png", "placeholder icon is wrong")
		runner.assert(placeholder.icon_size == 101, "placeholder icon size is wrong")
		runner.assert(placeholder.scale == 0.3, "placeholder scale is wrong")
		assert_shift(runner, placeholder, 1, 2, "placeholder")
	end)

	runner.test("RCP-5 build_icon_entry plural icons form", function()
		local prototype = {
			icons = {
				{ icon = "funit/first.png", icon_size = 64, tint = { 0.1, 0.2, 0.3, 0.4 } },
				{ icon = "funit/second.png", icon_size = 64 },
			},
		}

		-- plural_shift = nil reuses shift.
		local reused = icon_entry.build_icon_entry(prototype, "item", "funit", 0.3, { 5, 6 }, nil, true)
		runner.assert(reused.icon == "funit/first.png", "plural form should use icons[1]")
		runner.assert(reused.icon_size == 64, "plural icon_size was not copied")
		runner.assert(reused.scale == 0.3, "plural form must not apply the icon-size correction")
		assert_shift(runner, reused, 5, 6, "plural entry using shift")
		runner.assert(reused.tint[1] == 0.1 and reused.tint[4] == 0.4, "plural tint was not copied")

		-- plural_shift = false suppresses the shift (reversed helper behavior).
		local unshifted = icon_entry.build_icon_entry(prototype, "item", "funit", 0.3, { 5, 6 }, false, false)
		runner.assert(unshifted.shift == nil, "plural_shift = false must suppress the shift")
		runner.assert(unshifted.tint == nil, "copy_tint = false must not copy the tint")
	end)

	runner.test("RCP-6 blur_technology_icon count, tint and immutability", function()
		local original = {
			{ icon = "funit/a.png", icon_size = 64, shift = { 2, 3 } },
		}
		local blurred = images.blur_technology_icon(original, 1)

		-- 1 original + blur_count * ((5 - 1) / 1 + 1) = 1 + 8 * 5 = 41.
		runner.assert(#blurred == 41, "blur_technology_icon produced " .. #blurred .. " entries, expected 41")

		runner.assert(blurred[1].tint[1] == 1 and blurred[1].tint[2] == 1 and blurred[1].tint[3] == 1,
			"the unblurred copy should be opaque white")
		runner.assert(blurred[1] ~= original[1], "the original icon must not be reused")

		local alpha = blurred[2].tint[4]
		runner.assert(alpha and alpha > 0 and alpha < 1, "blurred copies should be nearly transparent")
		runner.assert(blurred[2].blend_mode == "multiplicative-with-alpha", "blurred copies need the blend mode")

		runner.assert(original[1].shift[1] == 2 and original[1].shift[2] == 3, "the input icons were mutated")
		runner.assert(original[1].tint == nil and original[1].blend_mode == nil, "the input icons gained blur fields")

		local two_icons = images.blur_technology_icon({
			{ icon = "funit/a.png" },
			{ icon = "funit/b.png" },
		}, 2)
		runner.assert(#two_icons == 82, "two icons should produce 82 entries")
	end)

	runner.test("RCP-7 blur_technology_icon validates blurriness", function()
		for _, bad in ipairs({ 0, -1, "1" }) do
			local ok, err = pcall(images.blur_technology_icon, {}, bad)
			runner.assert(not ok, "blurriness " .. tostring(bad) .. " should be rejected")
			runner.assert(
				tostring(err):find("blurriness must be a number greater than 0", 1, true),
				"the assertion message should name the argument"
			)
		end
	end)

	runner.test("RCP-8 data-stage icon fixture results", function()
		support.assert_all(runner, "icons", { expected = ICONS_IDS })
	end)
end
