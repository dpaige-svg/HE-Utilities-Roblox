local root = script.Parent.Parent
local Auto = require(root.Scanner.AutoScanService)
local Reporter = require(root.Scanner.DetectionReporter)
local Test = {}

local function waitFor(predicate)
	local deadline = os.clock() + 15
	repeat
		if predicate() then return end
		task.wait(0.05)
	until os.clock() > deadline
	error("Timed out waiting for Auto Scan")
end

function Test.Run(expectOnline)
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot, "Workspace.AssetTrustMonitor_TestRoot is required")
	assert(not Auto.IsRunning(), "Stop the existing Auto Scan before testing")
	local fixtures, scanned, reports, results = {}, {}, {}, {}
	local success, failure = pcall(function()
		for _, class in ipairs({ "Script", "LocalScript", "ModuleScript" }) do
			local item = Instance.new(class)
			item.Name = "Phase4_" .. class
			if item:IsA("BaseScript") then item.Disabled = true end
			item.Source = "-- clean controlled fixture"
			item.Parent = testRoot
			table.insert(fixtures, item)
		end
		Auto.SetCallbacks({
			OnScanCompleted = function(item, findings, counts)
				if table.find(fixtures, item) then
					scanned[item] = (scanned[item] or 0) + 1
					results[item] = { findings = findings, counts = counts }
				end
			end,
			OnReportCompleted = function(ok, counts)
				table.insert(reports, { ok = ok, counts = counts })
			end,
		})
		assert(Auto.Start(testRoot))
		assert(Auto.IsRunning())
		for i = 1, 8 do
			for _, item in ipairs(fixtures) do item.Source = "-- suspicious_marker edit " .. i end
			task.wait(0.03)
		end
		assert(next(scanned) == nil, "Debounce fired too early")
		assert(Auto.GetQueueSize() == 3, "Duplicate queue entries")
		assert(not Auto.Queue(fixtures[1]), "Duplicate Queue accepted")
		waitFor(function() return #reports > 0 end)
		for _, item in ipairs(fixtures) do
			assert(scanned[item] == 1, "Expected exactly one scan per script")
			local result = results[item]
			assert(#result.findings == 1 and result.findings[1].RuleId == "SIG-TEST-001", "Unexpected finding")
			assert(result.counts["SIG-TEST-001"] == 1)
		end
		local total = 0
		for _, report in ipairs(reports) do
			assert(report.ok == expectOnline, "Unexpected reporting status")
			total += report.counts["SIG-TEST-001"] or 0
		end
		assert(total == 3, "Counts were not aggregated")
		local counts = Reporter.Aggregate({ { RuleId = "SIG-TEST-001" }, { RuleId = "SIG-TEST-001" }, { RuleId = "KEY-TEST-001" } })
		assert(counts["SIG-TEST-001"] == 2 and counts["KEY-TEST-001"] == 1)
		-- Cancel queued work, then prove listeners stay disconnected.
		fixtures[1].Source = "-- suspicious_marker pending"
		Auto.Stop()
		assert(not Auto.IsRunning() and Auto.GetQueueSize() == 0)
		fixtures[1].Source = "-- suspicious_marker after stop"
		task.wait(1)
		assert(scanned[fixtures[1]] == 1 and Auto.GetQueueSize() == 0)
	end)
	Auto.Stop()
	Auto.SetCallbacks({ OnScanCompleted = false, OnReportCompleted = false })
	for _, item in ipairs(fixtures) do item:Destroy() end
	assert(success, failure)
	print("PHASE 4 AUTO SCAN PASS", expectOnline and "online" or "offline")
	return true
end

function Test.RunQueue()
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot and not Auto.IsRunning())
	local fixtures, times = {}, {}
	local success, failure = pcall(function()
		for i = 1, 1001 do
			local item = Instance.new("ModuleScript")
			item.Name = "Phase4_Queue_" .. i
			item.Source = "-- clean"
			item.Parent = testRoot
			table.insert(fixtures, item)
			if i % 50 == 0 then task.wait() end
		end
		local scanner = require(root.Scanner.ScriptScanner)
		local library = require(root.Security.SecurityLibrary)
		Auto.SetCallbacks({ OnScanCompleted = function() table.insert(times, os.clock()) end })
		assert(Auto.Start(testRoot, scanner, library))
		for i = 1, 1000 do assert(Auto.Queue(fixtures[i])) end
		assert(not Auto.Queue(fixtures[1]), "Duplicate accepted")
		assert(not Auto.Queue(fixtures[1001]), "Queue exceeded limit")
		assert(Auto.IsPaused() and Auto.GetQueueSize() == 1000)
		Auto.ClearQueue()
		assert(Auto.Resume())
		for i = 1, 12 do assert(Auto.Queue(fixtures[i])) end
		waitFor(function() return #times == 12 end)
		assert(times[6] - times[1] >= 0.025 and times[11] - times[6] >= 0.025, "Missing batch yield")
		-- A script leaving the root must lose its listener and queued work.
		fixtures[1].Parent = nil
		fixtures[1].Source = "-- changed outside watched root"
		task.wait(1)
		assert(#times == 12 and not Auto.Queue(fixtures[1]))
		Auto.Stop()
		assert(Auto.Start(testRoot, scanner, library))
		fixtures[2].Source = "-- changed after restart"
		waitFor(function() return #times == 13 end)
		Auto.Stop()
		task.wait(0.1)
		assert(Auto.GetQueueSize() == 0 and not Auto.IsRunning())
	end)
	Auto.Stop()
	Auto.SetCallbacks({ OnScanCompleted = false })
	for _, item in ipairs(fixtures) do item:Destroy() end
	assert(success, failure)
	print("PHASE 4 QUEUE PASS")
	return true
end

return Test
