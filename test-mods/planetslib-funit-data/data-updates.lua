-- data-updates stage fixtures.
--
-- Runs after PlanetsLib's own data-updates.lua (dependencies load first), so
-- APIs intended for the data-updates stage can be exercised here.

local manifest = require("prototypes.fixtures.manifest")
for _, fixture in ipairs(manifest.data_updates) do
	require("prototypes.fixtures." .. fixture)
end
