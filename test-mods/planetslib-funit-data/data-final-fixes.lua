-- data-final-fixes stage fixtures.
--
-- Runs after PlanetsLib's own data-final-fixes.lua, so APIs intended for the
-- data-final-fixes stage (e.g. PlanetsLib:update) can be exercised here.

local manifest = require("prototypes.fixtures.manifest")
for _, fixture in ipairs(manifest.data_final_fixes) do
	require("prototypes.fixtures." .. fixture)
end
