-- PlanetsLib_transfer_storage remote interface (control.lua).
--
-- The interface moves another mod's storage between forks. It is a real remote
-- interface, so the scenario can call it directly.
return function(runner)
	runner.test("REM-1 PlanetsLib_transfer_storage save/get/purge round-trip", function()
		local key = "funit-transfer"
		local payload = { a = 1, nested = { "x", "y" } }

		remote.call("PlanetsLib_transfer_storage", "save", key, payload)

		local got = remote.call("PlanetsLib_transfer_storage", "get", key)
		runner.assert(got, "get returned nil after save")
		runner.assert(got.a == 1, "a scalar field was lost")
		runner.assert(got.nested[1] == "x" and got.nested[2] == "y", "a nested table was lost")

		remote.call("PlanetsLib_transfer_storage", "purge", key)
		runner.assert(
			remote.call("PlanetsLib_transfer_storage", "get", key) == nil,
			"purge did not remove the saved entry"
		)
		runner.assert(
			remote.call("PlanetsLib_transfer_storage", "get", "funit-never-saved") == nil,
			"an unknown key should return nil"
		)
	end)
end
