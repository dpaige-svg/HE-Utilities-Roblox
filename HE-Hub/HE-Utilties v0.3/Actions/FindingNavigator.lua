local Selection = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")

local FindingNavigator = {}

function FindingNavigator.FindMatchRange(source, matchedText)
	if type(source) ~= "string" or type(matchedText) ~= "string" or matchedText == "" then return nil end
	-- The editor uses line/UTF-8-byte coordinates. Normalize Windows newlines.
	source = source:gsub("\r\n", "\n")
	matchedText = matchedText:gsub("\r\n", "\n")
	local first, last = string.find(source, matchedText, 1, true)
	if not first then return nil end
	local function position(offset)
		local prefix = source:sub(1, offset - 1)
		local _, newlines = prefix:gsub("\n", "")
		local previousNewline = prefix:match(".*()\n") or 0
		return { Line = newlines + 1, Character = offset - previousNewline }
	end
	return { Start = position(first), End = position(last + 1) }
end

function FindingNavigator.GoToFinding(finding)
	local instance = finding and finding.Instance
	if finding and finding.LocationKind then
		if typeof(instance) ~= "Instance" or not instance:IsDescendantOf(game) then
			return false, "This object is no longer available."
		end
		Selection:Set({ instance })
		return true
	end
	if typeof(instance) ~= "Instance" or not instance:IsA("LuaSourceContainer")
		or not instance:IsDescendantOf(game) then
		return false, "This script is no longer available."
	end

	local ok, opened, message = pcall(function()
		Selection:Set({ instance })
		local range = FindingNavigator.FindMatchRange(ScriptEditorService:GetEditorSource(instance), finding.MatchedText)
		local success, reason = ScriptEditorService:OpenScriptDocumentAsync(instance,
			range and { HighlightRange = range } or nil)
		if not success then return false, reason end
		local document = ScriptEditorService:FindScriptDocument(instance)
		if not document then return false, "The script editor document is unavailable." end
		-- Re-resolve after opening in case the user edited the source meanwhile.
		range = FindingNavigator.FindMatchRange(document:GetText(), finding.MatchedText)
		if not range then return false, "The script opened, but the matched text is no longer present." end
		return document:ForceSetSelectionAsync(range.Start.Line, range.Start.Character,
			range.End.Line, range.End.Character)
	end)
	if not ok or not opened then
		return false, "Could not navigate to the match. " .. tostring(ok and message or opened)
	end
	return true
end

return FindingNavigator
