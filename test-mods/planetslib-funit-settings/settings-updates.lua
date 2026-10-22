local setting = data.raw["bool-setting"]["PlanetsLib-enable-entity-replacements"]
setting.hidden = true
setting.forced_value = false

-- Exercise the global kill switch as well as the per-rule default setting. The
-- no-replacements scenarios must not replace anything even though the fixture
-- rules are bound to their own (default-on) startup setting.
local disable_all = data.raw["bool-setting"]["PlanetsLib-disable-all-entity-replacements"]
disable_all.hidden = true
disable_all.forced_value = true
