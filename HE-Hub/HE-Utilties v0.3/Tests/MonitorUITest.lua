local root = script.Parent.Parent
local Batch = require(root.UI.NotificationBatch)
local Controller = require(root.UI.MonitorController)
local Widget = require(root.UI.MonitorWidget)
local Test = {}

local function waitFor(predicate, seconds)
	local deadline = os.clock() + (seconds or 10)
	repeat
		if predicate() then return end
		task.wait(0.05)
	until os.clock() > deadline
	error("Phase 5 test timed out")
end

local function fakeView()
	local view = { notifications = {}, visible = false }
	function view:Bind(actions) self.actions = actions end
	function view:SetStatus(state) self.state = table.clone(state) end
	function view:ShowNotification(summary) table.insert(self.notifications, summary); self.current = summary end
	function view:HideNotification() self.current = nil end
	function view:ShowNotice(message) self.notice = message end
	function view:ShowFinding(entry, index, total) self.entry = entry; self.index = index; self.total = total; self.visible = true end
	function view:HideReview() self.visible = false end
	function view:Destroy() self.destroyed = true end
	return view
end

local function fixture(parent, name, markers)
	local asset = Instance.new("Model")
	asset.Name = name
	for index, marker in ipairs(markers) do
		local item = Instance.new("ModuleScript")
		item.Name = "Component" .. index
		item.Source = "-- " .. marker
		item.Parent = asset
	end
	asset.Parent = parent
	return asset
end

function Test.Run()
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot, "Workspace.AssetTrustMonitor_TestRoot is required")
	local assets = {}
	local monitor
	local success, failure = pcall(function()
		local view = fakeView()
		local running, callbacks = false, {}
		local auto = {
			SetCallbacks = function(value) callbacks = value end,
			Start = function() running = true; return true end,
			Stop = function() running = false end,
			IsRunning = function() return running end,
			IsPaused = function() return false end,
			GetQueueSize = function() return 0 end,
			IsProcessing = function() return false end,
			Queue = function() return true end,
		}
		local source = "Remote"
		local navigated
		monitor = Controller.new(view, testRoot, { AutoScan = auto,
			Provider = { GetLibrary = function() return source ~= "Unavailable" and {} or nil, source end },
			Navigator = { GoToFinding = function(finding) navigated = finding; return true end } })
		monitor:Start()
		assert(running and view.state.Enabled and not view.state.Paused and view.state.Library == "Remote")
		local safe = fixture(testRoot, "Phase5Safe", { "clean", "clean" }); table.insert(assets, safe)
		for _, item in ipairs(safe:GetChildren()) do callbacks.OnScanCompleted(item, {}) end
		waitFor(function() return #view.notifications == 1 end)
		assert(view.current.FindingCount == 0)
		waitFor(function() return view.current == nil end, 6)
		assert(#view.notifications == 1, "Safe asset emitted multiple notifications")
		local pack = fixture(testRoot, "WeaponPack", { "clean", "clean" }); table.insert(assets, pack)
		local children = pack:GetChildren()
		local first = { Instance = children[1], Path = children[1]:GetFullName(), RuleId = "SIG-TEST-001", MatchedText = "marker", Severity = "High" }
		local second = { Instance = children[2], Path = children[2]:GetFullName(), RuleId = "KEY-TEST-001", MatchedText = "keyword", Severity = "Medium" }
		callbacks.OnScanCompleted(children[1], { first, first })
		callbacks.OnScanCompleted(children[1], { first })
		callbacks.OnScanCompleted(children[2], { second })
		waitFor(function() return #view.notifications == 2 end)
		assert(view.current.AssetCount == 1 and view.current.FindingCount == 2 and view.current.Severity == "High")
		assert(view.current.Message:find("WeaponPack", 1, true))
		view.actions.Review(); assert(view.index == 1 and view.total == 2)
		view.actions.Previous(); assert(view.index == 1)
		view.actions.Next(); assert(view.index == 2)
		view.actions.Next(); assert(view.index == 2)
		view.actions.GoTo(); assert(navigated == second)
		view.actions.Previous(); assert(view.index == 1)
		view.actions.Close(); assert(not view.visible and monitor.review == nil)
		view.actions.Dismiss(); assert(view.current == nil)
		local other = fixture(testRoot, "OtherPack", { "clean" }); table.insert(assets, other)
		local critical = { Instance = other.Component1, RuleId = "SIG-TEST-002", MatchedText = "critical", Severity = "Critical" }
		callbacks.OnScanCompleted(children[1], { first })
		task.wait(0.3)
		callbacks.OnScanCompleted(other.Component1, { critical })
		waitFor(function() return #view.notifications == 3 end)
		assert(view.current.AssetCount == 2 and view.current.FindingCount == 2 and view.current.CriticalCount == 1)
		assert(view.current.Severity == "Critical" and view.current.Message:find("Multiple threats detected", 1, true))
		view.actions.Review()
		other:Destroy()
		waitFor(function() return view.current and view.current.FindingCount == 1 and view.total == 1 end)
		assert(view.current.AssetCount == 1 and monitor.review[1].Finding == first)
		pack:Destroy()
		waitFor(function() return view.current == nil and not view.visible end)
		assert(monitor.review == nil, "Removed test objects remained reviewable")
		view.actions.Toggle(); assert(not running and not view.state.Enabled)
		source = "LocalFallback"; view.actions.Toggle()
		assert(running and view.state.Library == "LocalFallback")
		view.actions.Toggle(); source = "Unavailable"; view.actions.Toggle()
		assert(not running and view.state.Library == "Unavailable" and view.state.Paused)
	end)
	if monitor then monitor:Destroy() end
	for _, asset in ipairs(assets) do asset:Destroy() end
	assert(success, failure)
	print("PHASE 5 NOTIFICATIONS / REVIEW / STATUS PASS")
	return true
end

function Test.RunIntegration(expectOnline)
	local Auto = require(root.Scanner.AutoScanService)
	assert(not Auto.IsRunning(), "Turn the installed monitor OFF before integration testing")
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot)
	local view = fakeView()
	local monitor = Controller.new(view, testRoot)
	local reports = {}
	Auto.SetCallbacks({ OnReportCompleted = function(ok, counts)
		table.insert(reports, { ok = ok, counts = counts })
	end })
	local assets = {}
	local previousSelection = game:GetService("Selection"):Get()
	local success, failure = pcall(function()
		monitor:Start()
		waitFor(function() return Auto.IsRunning() end)
		assert(view.state.Library == (expectOnline and "Remote" or "LocalFallback"))
		local safe = fixture(testRoot, "Phase5Safe", { "clean", "clean" }); table.insert(assets, safe)
		waitFor(function() return #view.notifications == 1 end)
		assert(view.current.FindingCount == 0 and view.state.LastCheck ~= "Never")
		local pack = fixture(testRoot, "WeaponPack", { "suspicious_marker", "suspicious_keyword" }); table.insert(assets, pack)
		waitFor(function() return #view.notifications == 2 end)
		assert(view.current.FindingCount == 2 and view.current.AssetCount == 1)
		view.actions.Review(); view.actions.Next(); assert(view.index == 2)
		assert(monitor:GoTo())
		assert(game:GetService("Selection"):Get()[1] == view.entry.Finding.Instance)
		assert(game:GetService("ScriptEditorService"):FindScriptDocument(view.entry.Finding.Instance), "Finding script did not open in the editor")
		view.actions.Close(); view.actions.Dismiss()
		local a = fixture(testRoot, "ThreatPackA", { "suspicious_marker" }); table.insert(assets, a)
		local b = fixture(testRoot, "ThreatPackB", { "backdoor_test_marker" }); table.insert(assets, b)
		waitFor(function() return #view.notifications == 3 end)
		assert(view.current.AssetCount == 2 and view.current.FindingCount == 2 and view.current.CriticalCount == 1)
		-- Source changes continue to use the original imported asset identity.
		view.actions.Dismiss()
		a.Component1.Source = "-- suspicious_keyword changed"
		waitFor(function() return #view.notifications == 4 end)
		assert(view.current.FindingCount == 1 and view.current.Message:find("ThreatPackA", 1, true))
		waitFor(function()
			local total = 0
			for _, report in ipairs(reports) do for _, count in pairs(report.counts) do total += count end end
			return total == 5
		end, 15)
		for _, report in ipairs(reports) do assert(report.ok == expectOnline, "Unexpected detection reporting status") end
		view.actions.Toggle(); assert(not Auto.IsRunning())
		a.Component1.Source = "-- clean while off"
		task.wait(1)
		assert(#view.notifications == 4)
	end)
	monitor:Destroy()
	Auto.SetCallbacks({ OnReportCompleted = false })
	for _, asset in ipairs(assets) do asset:Destroy() end
	game:GetService("Selection"):Set(previousSelection)
	assert(success, failure)
	print("PHASE 5 IMPORT / NAVIGATION / AUTO SCAN PASS", expectOnline and "online" or "offline")
	return true
end

function Test.Open(pluginObject)
	assert(pluginObject, "Run Open(plugin) from a Studio plugin")
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot, "Workspace.AssetTrustMonitor_TestRoot is required")
	local view = Widget.new(pluginObject)
	local monitor = Controller.new(view, testRoot)
	monitor:Start()
	return monitor
end

return Test
