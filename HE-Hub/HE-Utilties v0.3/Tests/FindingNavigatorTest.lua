local Navigator = require(script.Parent.Parent.Actions.FindingNavigator)
local Test = {}

function Test.Run()
	local function check(source, match, sl, sc, el, ec)
		local range = Navigator.FindMatchRange(source, match)
		assert(range and range.Start.Line == sl and range.Start.Character == sc)
		assert(range.End.Line == el and range.End.Character == ec)
	end
	check("-- clean\n-- suspicious_marker", "suspicious_marker", 2, 4, 2, 21)
	check("-- clean\r\n-- suspicious_marker", "suspicious_marker", 2, 4, 2, 21)
	check("é marker", "marker", 1, 4, 1, 10)
	check("x\nabc\ndef\ny", "abc\ndef", 2, 1, 3, 4)
	check("marker marker", "marker", 1, 1, 1, 7)
	check("a.b", "a.b", 1, 1, 1, 4)
	assert(Navigator.FindMatchRange("clean", "missing") == nil)
	assert(Navigator.FindMatchRange("clean", "") == nil)
	print("FINDING NAVIGATOR RANGE PASS")
	return true
end

function Test.RunEditor()
	local testRoot = workspace:FindFirstChild("AssetTrustMonitor_TestRoot")
	assert(testRoot)
	local item = Instance.new("ModuleScript")
	item.Name = "NavigationFixture"
	item.Source = "-- clean\n-- suspicious_marker\nreturn {}"
	item.Parent = testRoot
	local previous = game:GetService("Selection"):Get()
	local ok, failure = pcall(function()
		assert(Navigator.GoToFinding({ Instance = item, MatchedText = "suspicious_marker" }))
		local document = game:GetService("ScriptEditorService"):FindScriptDocument(item)
		assert(document and document:GetSelectedText() == "suspicious_marker")
		local line, column = document:GetSelectionStart()
		assert(line == 2 and column == 4)
	end)
	item:Destroy()
	game:GetService("Selection"):Set(previous)
	assert(ok, failure)
	print("FINDING NAVIGATOR EDITOR PASS")
	return true
end

return Test
