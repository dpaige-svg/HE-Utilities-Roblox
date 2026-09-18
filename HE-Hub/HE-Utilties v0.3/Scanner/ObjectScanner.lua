-- Adapter around the unchanged script scanner; metadata stays inside Studio.
local ScriptScanner = require(script.Parent.ScriptScanner)
local Finding = require(script.Parent.Finding)
local CollectionService = game:GetService("CollectionService")
local ObjectScanner = { IsScript = ScriptScanner.IsScript }
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

function ObjectScanner.CanScan(instance)
	local ancestor = instance
	while ancestor do
		if ancestor:IsA("DockWidgetPluginGui") then return false end
		if ancestor.Parent == game and (ancestor.Name == "CoreGui" or ancestor.Name == "CorePackages"
			or ancestor.Name == "PluginGuiService") then return false end
		ancestor = ancestor.Parent
	end
	return true
end

function ObjectScanner.ShouldQueue(instance)
	return ScriptScanner.IsScript(instance) or TEXT_CLASSES[instance.ClassName]
		or next(instance:GetAttributes()) ~= nil or #CollectionService:GetTags(instance) > 0
end

function ObjectScanner.ScanInstance(instance, library)
	local findings = ScriptScanner.ScanInstance(instance, library)
	local budget = 500000
	local function scan(text, kind, field)
		if type(text) ~= "string" or text == "" or #text > budget then return end
		budget -= #text
		local function match(rule, pattern, ruleType)
			if type(pattern) ~= "string" or pattern == "" or not string.find(text, pattern, 1, true) then return end
			local finding = Finding.new({ RuleId = rule.Id, RuleName = rule.Name or rule.Keyword,
				Instance = instance, Path = instance:GetFullName(), MatchedText = pattern,
				Severity = rule.Severity, Confidence = rule.Confidence, Category = rule.Category,
				Description = rule.Description, SourceType = ruleType })
			finding.LocationKind = kind
			finding.LocationName = field
			table.insert(findings, finding)
		end
		for _, rule in ipairs(library.Signatures or {}) do match(rule, rule.Pattern, "Signature") end
		for _, rule in ipairs(library.Keywords or {}) do match(rule, rule.Keyword, "Keyword") end
	end
	if TEXT_CLASSES[instance.ClassName] then scan(instance.Text, "UI Text", "Text") end
	if instance:IsA("TextBox") then scan(instance.PlaceholderText, "UI Text", "PlaceholderText") end
	-- Scan values only; attribute names are labels, not executable/text content.
	local attributes = instance:GetAttributes()
	local names = {}
	for name in pairs(attributes) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do
		local value = attributes[name]
		if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
			scan(tostring(value), "Attribute", name)
		end
	end
	local tags = CollectionService:GetTags(instance)
	table.sort(tags)
	for _, tag in ipairs(tags) do scan(tag, "Tag", tag) end
	return findings
end

local function connectionGroup(connections, onDisconnect)
	local group = { Connected = true }
	function group:Disconnect()
		if not self.Connected then return end
		self.Connected = false
		for _, connection in ipairs(connections) do connection:Disconnect() end
		if onDisconnect then onDisconnect() end
	end
	return group
end

function ObjectScanner.WatchInstance(instance, changed)
	local connections = { instance.AttributeChanged:Connect(changed) }
	if ScriptScanner.IsScript(instance) then
		table.insert(connections, instance:GetPropertyChangedSignal("Source"):Connect(changed))
	end
	if TEXT_CLASSES[instance.ClassName] then
		table.insert(connections, instance:GetPropertyChangedSignal("Text"):Connect(changed))
	end
	if instance:IsA("TextBox") then
		table.insert(connections, instance:GetPropertyChangedSignal("PlaceholderText"):Connect(changed))
	end
	return connectionGroup(connections)
end

function ObjectScanner.WatchRoot(root, changed)
	local active = true
	local tags = {}
	local function inRoot(instance)
		return active and (instance == root or instance:IsDescendantOf(root)) and ObjectScanner.CanScan(instance)
	end
	local function onChange(instance) if inRoot(instance) then changed(instance) end end
	local function watchTag(tag)
		if tags[tag] then return end
		tags[tag] = connectionGroup({ CollectionService:GetInstanceAddedSignal(tag):Connect(onChange),
			CollectionService:GetInstanceRemovedSignal(tag):Connect(onChange) })
	end
	local connections = {
		CollectionService.TagAdded:Connect(function(tag)
			if not active then return end
			watchTag(tag)
			-- The first use predates this tag's listener; include it explicitly.
			for index, instance in ipairs(CollectionService:GetTagged(tag)) do
				if not active then return end
				onChange(instance)
				if index % 100 == 0 then task.wait() end
			end
		end),
		CollectionService.TagRemoved:Connect(function(tag)
			-- Per-instance removal events perform the rescans; release unused listeners.
			task.defer(function()
				if active and tags[tag] and #CollectionService:GetTagged(tag) == 0 then
					tags[tag]:Disconnect(); tags[tag] = nil
				end
			end)
		end),
	}
	for _, tag in ipairs(CollectionService:GetAllTags()) do watchTag(tag) end
	return connectionGroup(connections, function()
		active = false
		for _, group in pairs(tags) do group:Disconnect() end
		table.clear(tags)
	end)
end

return ObjectScanner
