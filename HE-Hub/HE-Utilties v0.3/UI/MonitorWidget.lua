local Widget = {}
Widget.__index = Widget
local palette = {
	-- Shared visual values from the existing HE-Utilities theme.
	Background = Color3.fromRGB(13, 13, 18), Panel = Color3.fromRGB(22, 22, 30),
	Surface = Color3.fromRGB(30, 30, 42), Border = Color3.fromRGB(50, 50, 68),
	Text = Color3.fromRGB(225, 225, 235), Muted = Color3.fromRGB(120, 120, 150),
	Primary = Color3.fromRGB(35, 70, 140),
	Info = Color3.fromRGB(55, 175, 110), Low = Color3.fromRGB(65, 130, 230),
	Medium = Color3.fromRGB(220, 150, 40), High = Color3.fromRGB(210, 55, 55),
	Critical = Color3.fromRGB(255, 70, 70),
}

local function create(class, parent, properties)
	local item = Instance.new(class)
	for key, value in pairs(properties) do item[key] = value end
	item.Parent = parent
	return item
end

local function outline(item)
	create("UICorner", item, { CornerRadius = UDim.new(0, 6) })
	create("UIStroke", item, { Color = palette.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function panel(parent, name, y, height)
	local item = create("Frame", parent, { Name = name, Position = UDim2.fromOffset(7, y),
		Size = UDim2.new(1, -14, 0, height), BackgroundColor3 = palette.Panel, BorderSizePixel = 0 })
	outline(item)
	return item
end

local function label(parent, name, text, y, height, size)
	return create("TextLabel", parent, { Name = name, Text = text, Position = UDim2.fromOffset(16, y),
		Size = UDim2.new(1, -32, 0, height), BackgroundTransparency = 1, TextColor3 = palette.Text,
		Font = Enum.Font.Gotham, TextSize = size or 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, RichText = false })
end

local function button(parent, name, text, position, size)
	local item = create("TextButton", parent, { Name = name, Text = text, Position = position, Size = size,
		BackgroundColor3 = palette.Surface, BorderSizePixel = 0, TextColor3 = palette.Text,
		TextSize = 11, Font = Enum.Font.GothamBold, AutoButtonColor = true })
	outline(item)
	return item
end

function Widget.new(pluginObject)
	local dock = pluginObject:CreateDockWidgetPluginGuiAsync("AssetTrustMonitor.Background",
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, true, false, 350, 320, 320, 320))
	dock.Title = "HE-Utilties v0.3"
	local review = pluginObject:CreateDockWidgetPluginGuiAsync("AssetTrustMonitor.Review",
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 390, 600, 350, 600))
	review.Title = "HE-Utilties v0.3 — Review"
	local self = setmetatable({ Dock = dock, ReviewDock = review, connections = {}, actions = {}, noticeToken = 0 }, Widget)
	local frame = create("Frame", dock, { Name = "Monitor", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = palette.Background })
	panel(frame, "HeaderPanel", 4, 36)
	panel(frame, "StatusPanel", 45, 109)
	panel(frame, "NotificationPanel", 159, 151)
	self.statusDot = create("Frame", frame, { Name = "StatusDot", Position = UDim2.fromOffset(16, 17),
		Size = UDim2.fromOffset(10, 10), BackgroundColor3 = palette.Medium, BorderSizePixel = 0 })
	create("UICorner", self.statusDot, { CornerRadius = UDim.new(1, 0) })
	local title = label(frame, "Title", "HE-Utilties v0.3", 14, 22, 13)
	title.Position = UDim2.fromOffset(34, 14)
	title.Size = UDim2.new(1, -50, 0, 22)
	title.Font = Enum.Font.GothamBold
	self.protection = label(frame, "Protection", "Protection Paused", 55, 22, 12)
	self.protection.Font = Enum.Font.GothamBold
	self.auto = label(frame, "AutoScan", "Auto Scan ON", 81, 19)
	self.library = label(frame, "Library", "Library: Unavailable", 105, 19)
	self.last = label(frame, "LastCheck", "Last Check: Never", 129, 19)
	self.library.TextColor3 = palette.Muted; self.last.TextColor3 = palette.Muted
	self.toggle = button(frame, "Toggle", "Turn Auto Scan OFF", UDim2.new(1, -166, 0, 77), UDim2.fromOffset(150, 27))
	self.toggle.BackgroundColor3 = palette.Primary
	self.message = label(frame, "Notification", "Monitoring new assets and script changes.", 172, 81, 12)
	self.message.TextColor3 = palette.Muted
	self.reviewButton = button(frame, "Review", "Review", UDim2.new(0, 16, 0, 263), UDim2.new(0.5, -24, 0, 30))
	self.dismissButton = button(frame, "Dismiss", "Dismiss", UDim2.new(0.5, 8, 0, 263), UDim2.new(0.5, -24, 0, 30))
	self.reviewButton.BackgroundColor3 = palette.Primary
	self.reviewButton.Visible = false; self.dismissButton.Visible = false
	local reviewFrame = create("Frame", review, { Name = "Finding", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = palette.Background })
	panel(reviewFrame, "HeaderPanel", 4, 36)
	panel(reviewFrame, "DetailsPanel", 45, 457)
	self.heading = label(reviewFrame, "Position", "Finding 0 of 0", 14, 22, 13)
	self.heading.Font = Enum.Font.GothamBold
	self.fields = {}
	local y = 55
	for _, spec in ipairs({ {"Severity", 20}, {"Asset", 22}, {"Location", 20}, {"Rule ID", 20}, {"Confidence", 20},
		{"Category", 22}, {"Description", 44}, {"Script path", 36}, {"Matched text", 42} }) do
		local fieldLabel = label(reviewFrame, spec[1] .. "Label", spec[1], y, 17, 11)
		fieldLabel.TextColor3 = palette.Muted
		fieldLabel.Font = Enum.Font.GothamBold
		if spec[1] == "Script path" then self.pathLabel = fieldLabel end
		self.fields[spec[1]] = create("TextBox", reviewFrame, { Name = spec[1], Text = "", Position = UDim2.fromOffset(16, y + 17),
			Size = UDim2.new(1, -32, 0, spec[2]), BackgroundTransparency = 1, TextColor3 = palette.Text,
			Font = (spec[1] == "Script path" or spec[1] == "Matched text") and Enum.Font.Code or Enum.Font.Gotham,
			TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, MultiLine = true,
			ClearTextOnFocus = false, TextEditable = false, RichText = false })
		y += spec[2] + 22
	end
	-- Keep one finding on screen. Long values remain selectable in read-only text boxes.
	self.previous = button(reviewFrame, "Previous", "Previous", UDim2.new(0, 16, 1, -82), UDim2.new(0.28, -14, 0, 30))
	self.goTo = button(reviewFrame, "GoTo", "Go To Script", UDim2.new(0.28, 8, 1, -82), UDim2.new(0.44, -16, 0, 30))
	self.goTo.BackgroundColor3 = palette.Primary
	self.next = button(reviewFrame, "Next", "Next", UDim2.new(0.72, 6, 1, -82), UDim2.new(0.28, -22, 0, 30))
	self.close = button(reviewFrame, "Close", "Close", UDim2.new(0, 16, 1, -42), UDim2.new(1, -32, 0, 30))
	for name, control in pairs({ Toggle = self.toggle, Review = self.reviewButton, Dismiss = self.dismissButton,
		Previous = self.previous, Next = self.next, GoTo = self.goTo, Close = self.close }) do
		table.insert(self.connections, control.Activated:Connect(function()
			local action = self.actions[name]
			if action then action() end
		end))
	end
	table.insert(self.connections, review:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not review.Enabled and self.actions.Close then self.actions.Close() end
	end))
	local toolbar = pluginObject:CreateToolbar("HE-Utilties v0.3")
	local open = toolbar:CreateButton("AssetTrustMonitor.Open", "Show HE-Utilties v0.3", "", "HE-Utilties v0.3")
	open.ClickableWhenViewportHidden = true
	table.insert(self.connections, open.Click:Connect(function() dock.Enabled = not dock.Enabled end))
	table.insert(self.connections, dock:GetPropertyChangedSignal("Enabled"):Connect(function() open:SetActive(dock.Enabled) end))
	open:SetActive(dock.Enabled)
	self.toolbar = toolbar
	return self
end

function Widget:Bind(actions) self.actions = actions end

function Widget:SetStatus(state)
	self.protection.Text = state.Paused and "Protection Paused" or "Protection Active"
	self.protection.TextColor3 = state.Paused and palette.Medium or palette.Info
	self.statusDot.BackgroundColor3 = self.protection.TextColor3
	self.auto.Text = "Auto Scan " .. (state.Enabled and "ON" or "OFF")
	self.toggle.Text = state.Enabled and "Turn Auto Scan OFF" or "Turn Auto Scan ON"
	local names = { Remote = "Remote", LocalFallback = "Local Fallback", Unavailable = "Unavailable" }
	self.library.Text = "Library: " .. (names[state.Library] or "Unavailable")
	self.last.Text = "Last Check: " .. state.LastCheck
	self.idleText = not state.Enabled and "Auto Scan is off." or state.Paused
		and "Protection is paused." or "Monitoring new assets and script changes."
	if not self.current and not self.showingNotice then self.message.Text = self.idleText end
end

function Widget:ShowNotification(summary)
	self.noticeToken += 1
	self.showingNotice = false
	self.current = summary
	self.message.Text = summary.Message
	self.message.TextColor3 = palette[summary.Severity] or palette.Low
	self.reviewButton.Visible = summary.FindingCount > 0
	self.dismissButton.Visible = summary.FindingCount > 0
end

function Widget:HideNotification()
	self.noticeToken += 1
	self.showingNotice = false
	self.current = nil
	self.message.Text = self.idleText or "Monitoring new assets and script changes."
	self.message.TextColor3 = palette.Muted
	self.reviewButton.Visible = false; self.dismissButton.Visible = false
end

function Widget:ShowNotice(message, severity)
	self.noticeToken += 1
	self.showingNotice = true
	local token = self.noticeToken
	self.message.Text = message
	self.message.TextColor3 = palette[severity] or palette.Medium
	task.delay(5, function()
		if self.destroyed or self.noticeToken ~= token then return end
		if self.current then self:ShowNotification(self.current) else self:HideNotification() end
	end)
end

function Widget:ShowFinding(entry, index, total)
	local finding = entry.Finding
	self.heading.Text = string.format("Finding %d of %d", index, total)
	local values = { Severity = finding.Severity, Asset = entry.Asset, ["Rule ID"] = finding.RuleId,
		Location = finding.LocationKind and (finding.LocationKind .. " · " .. (finding.LocationName or "")) or "Script Source",
		Confidence = finding.Confidence, Category = finding.Category, Description = finding.Description,
		["Script path"] = finding.Path, ["Matched text"] = finding.MatchedText }
	for name, field in pairs(self.fields) do field.Text = tostring(values[name] or "—") end
	self.pathLabel.Text = finding.LocationKind and "Object path" or "Script path"
	self.goTo.Text = finding.LocationKind and "Go To Object" or "Go To Script"
	self.fields.Severity.TextColor3 = palette[finding.Severity] or palette.Low
	self.previous.Active = index > 1; self.previous.AutoButtonColor = index > 1
	self.next.Active = index < total; self.next.AutoButtonColor = index < total
	self.previous.TextTransparency = index == 1 and 0.5 or 0
	self.next.TextTransparency = index == total and 0.5 or 0
	self.ReviewDock.Enabled = true
end

function Widget:HideReview() self.ReviewDock.Enabled = false end

function Widget:Destroy()
	self.destroyed = true
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.actions = {}; self.current = nil
	self.Dock:Destroy(); self.ReviewDock:Destroy(); self.toolbar:Destroy()
end

return Widget
