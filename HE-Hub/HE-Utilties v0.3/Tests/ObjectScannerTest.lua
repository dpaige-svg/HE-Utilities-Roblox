local root = script.Parent.Parent
local Scanner = require(root.Scanner.ObjectScanner)
local Library = require(root.Security.SecurityLibrary)
local Auto = require(root.Scanner.AutoScanService)
local Batch = require(root.UI.NotificationBatch)
local Navigator = require(root.Actions.FindingNavigator)
local Tags = game:GetService("CollectionService")
local Test = {}

local function waitFor(predicate)
	local deadline = os.clock() + 10
	repeat if predicate() then return end; task.wait(0.05) until os.clock() > deadline
	error("Object scanner test timed out")
end

function Test.Run()
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot and not Auto.IsRunning(), "Stop the monitor before testing")
	local fixture = Instance.new("Folder")
	fixture.Name = "MetadataTest"
	fixture.Parent = testRoot
	local selection = game:GetService("Selection"):Get()
	local ok, failure = pcall(function()
		for _, class in ipairs({ "TextLabel", "TextButton", "TextBox" }) do
			local item = Instance.new(class)
			item.Text = "suspicious_marker"
			item:SetAttribute("Config", "suspicious_keyword")
			Tags:AddTag(item, "backdoor_test_marker")
			item.Parent = fixture
			local findings = Scanner.ScanInstance(item, Library)
			assert(#findings == 3, "Expected UI text, attribute and tag findings")
			assert(findings[1].LocationKind == "UI Text" and findings[2].LocationKind == "Attribute"
				and findings[3].LocationKind == "Tag")
			assert(Navigator.GoToFinding(findings[2]))
			assert(game:GetService("Selection"):Get()[1] == item)
		end
		local item = Instance.new("ModuleScript")
		item.Source = "-- suspicious_marker"
		item:SetAttribute("First", "suspicious_marker")
		item:SetAttribute("Second", "suspicious_marker")
		item.Parent = fixture
		local findings = Scanner.ScanInstance(item, Library)
		assert(#findings == 3 and not findings[1].LocationKind, "Script scanning changed")
		local batch = Batch.new()
		batch:Add(fixture, item, findings); batch:Add(fixture, item, findings)
		assert(batch:Summary().FindingCount == 3, "Distinct fields lost or duplicate findings accepted")
		local clean = Instance.new("Part")
		clean:SetAttribute("suspicious_marker", "benign")
		Tags:AddTag(clean, "benign")
		clean.Parent = fixture
		assert(#Scanner.ScanInstance(clean, Library) == 0, "Ordinary metadata was flagged")
	end)
	fixture:Destroy()
	game:GetService("Selection"):Set(selection)
	assert(ok, failure)
	print("OBJECT SCANNER MATCHING / NAVIGATION PASS")
	return true
end

function Test.RunAuto()
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot and not Auto.IsRunning(), "Stop the monitor before testing")
	local fixture = Instance.new("Folder")
	fixture.Name = "MetadataAutoTest"
	fixture.Parent = testRoot
	local label = Instance.new("TextLabel")
	label.Text = "clean"; label.Parent = fixture
	local part = Instance.new("Part"); part.Parent = fixture
	local results, scans = {}, {}
	local ok, failure = pcall(function()
		Auto.SetCallbacks({ OnScanCompleted = function(item, findings)
			results[item] = findings; scans[item] = (scans[item] or 0) + 1
		end })
		assert(Auto.Start(testRoot, Scanner, Library))
		for i = 1, 8 do label.Text = "suspicious_marker " .. i; task.wait(0.03) end
		waitFor(function() return results[label] ~= nil end)
		assert(scans[label] == 1 and #results[label] == 1, "Text debounce failed")
		part:SetAttribute("Config", "suspicious_keyword")
		waitFor(function() return results[part] ~= nil end)
		assert(#results[part] == 1 and results[part][1].LocationKind == "Attribute")
		local before = scans[part]
		Tags:AddTag(part, "backdoor_test_marker")
		waitFor(function() return scans[part] > before end)
		assert(#results[part] == 2, "First use of a tag was missed")
		local inserted = Instance.new("TextButton")
		inserted.Text = "suspicious_marker"
		Tags:AddTag(inserted, "backdoor_test_marker")
		inserted.Parent = fixture
		waitFor(function() return results[inserted] ~= nil end)
		assert(#results[inserted] == 2, "Imported text/tag not scanned")
		before = scans[part]
		Tags:RemoveTag(part, "backdoor_test_marker")
		part:SetAttribute("Config", nil)
		waitFor(function() return scans[part] > before end)
		assert(#results[part] == 0)
		Auto.Stop()
		before = scans[part]
		part:SetAttribute("Config", "suspicious_keyword")
		Tags:AddTag(part, "backdoor_test_marker")
		task.wait(1)
		assert(scans[part] == before and Auto.GetQueueSize() == 0, "Listeners survived Stop")
	end)
	Auto.Stop(); Auto.SetCallbacks({ OnScanCompleted = false })
	fixture:Destroy()
	assert(ok, failure)
	print("OBJECT AUTO SCAN TEXT / ATTRIBUTES / TAGS PASS")
	return true
end

return Test
