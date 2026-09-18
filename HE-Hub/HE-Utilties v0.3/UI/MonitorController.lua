local root = script.Parent.Parent
local Batch = require(script.Parent.NotificationBatch)
local AutoScan = require(root.Scanner.AutoScanService)
local Scanner = require(root.Scanner.ObjectScanner)
local Provider = require(root.Security.SecurityLibraryProvider)
local Navigator = require(root.Actions.FindingNavigator)
local Controller = {}
Controller.__index = Controller
local WINDOW = 1.5

function Controller.new(view, watchedRoot, dependencies)
	assert(typeof(watchedRoot) == "Instance", "Monitor requires an explicit root Instance")
	local deps = dependencies or {}
	local self = setmetatable({ view = view, root = watchedRoot, auto = deps.AutoScan or AutoScan,
		provider = deps.Provider or Provider, navigator = deps.Navigator or Navigator,
		connections = {}, added = setmetatable({}, { __mode = "k" }), batch = Batch.new(),
		notification = nil, review = nil, index = 1, token = 0, generation = 0,
		state = { Enabled = false, Paused = true, Library = "Unavailable", LastCheck = "Never", Starting = false },
		destroyed = false }, Controller)
	view:Bind({ Toggle = function() self:SetEnabled(not self.state.Enabled) end,
		Review = function() self:OpenReview() end, Dismiss = function() self:Dismiss() end,
		Previous = function() self:Move(-1) end, Next = function() self:Move(1) end,
		GoTo = function() self:GoTo() end, Close = function() self:CloseReview() end })
	self.auto.SetCallbacks({
		OnScanCompleted = function(instance, findings) self:Completed(instance, findings) end,
		OnQueueChanged = function() self:Refresh(); self:ScheduleFlush() end,
		OnLargeQueue = function()
			self:Refresh()
			view:ShowNotice("Protection paused — queue limit reached. Toggle Auto Scan off and on to resume monitoring new changes.", "High")
		end,
		OnEnabledChanged = function() self:Refresh() end,
		OnScanError = function()
			view:ShowNotice("A script could not be checked.", "Medium")
		end,
	})
	self.removalConnection = watchedRoot.DescendantRemoving:Connect(function(instance) self:RemoveObject(instance) end)
	self:Refresh()
	return self
end

function Controller:Refresh()
	if self.destroyed then return end
	self.state.Paused = not self.auto.IsRunning() or self.auto.IsPaused()
	local previous = self.rendered
	if previous and previous.Enabled == self.state.Enabled and previous.Paused == self.state.Paused
		and previous.Library == self.state.Library and previous.LastCheck == self.state.LastCheck then return end
	self.rendered = table.clone(self.state)
	self.view:SetStatus(self.state)
end

function Controller:Track(instance)
	-- One token per insertion turn. Resolve ancestry after all DescendantAdded
	-- events arrive, so a nested imported pack keeps its own asset identity.
	if not self.importToken then
		local token = {}
		self.importToken = token
		task.defer(function() if self.importToken == token then self.importToken = nil end end)
	end
	self.added[instance] = self.importToken
end

function Controller:AssetFor(instance)
	local token = self.added[instance]
	local asset = instance
	if token then
		while asset.Parent and asset.Parent ~= self.root and self.added[asset.Parent] == token do
			asset = asset.Parent
		end
		return asset
	end
	-- Existing scripts: prefer their containing Model/Tool, otherwise the
	-- outermost Folder beneath a service (or the supplied test root).
	local ancestor = instance.Parent
	while ancestor and ancestor ~= self.root and ancestor.Parent ~= game do
		if ancestor:IsA("Model") or ancestor:IsA("Tool") then return ancestor end
		if ancestor:IsA("Folder") then asset = ancestor end
		ancestor = ancestor.Parent
	end
	return asset
end

function Controller:Completed(instance, findings)
	if self.destroyed or not self.state.Enabled then return end
	self.state.LastCheck = os.date("%H:%M:%S")
	self.batch:Add(self:AssetFor(instance), instance, findings)
	self:Refresh()
	self:ScheduleFlush()
end

function Controller:ScheduleFlush()
	if self.destroyed or self.batch.checked == 0 or self.flushScheduled then return end
	self.flushScheduled = true
	local generation = self.generation
	-- One timer for the burst, never one timer per script.
	task.delay(WINDOW, function()
		if self.destroyed or generation ~= self.generation then return end
		self.flushScheduled = false
		if self.auto.GetQueueSize() > 0 or self.auto.IsProcessing() then
			-- Queue callbacks will schedule again. No polling loop.
			return
		end
		local summary = self.batch:Summary()
		self.batch = Batch.new()
		if summary then self:Notify(summary) end
	end)
end

function Controller:Notify(summary)
	if summary.FindingCount > 0 then
		local live = Batch.new()
		for _, entry in ipairs(summary.Findings) do
			local instance = entry.Finding.Instance
			if typeof(instance) == "Instance" and instance:IsDescendantOf(self.root) then
				live:Add(self:AssetFor(instance), instance, { entry.Finding })
			end
		end
		summary = live:Summary()
		if not summary then return end
	end
	-- A safe result must not erase an unresolved warning/review.
	if summary.FindingCount == 0 and self.notification and self.notification.FindingCount > 0 then return end
	self.token += 1
	local token = self.token
	self.notification = summary
	self.view:ShowNotification(summary)
	if summary.FindingCount == 0 then
		task.delay(4, function()
			if not self.destroyed and self.token == token then self:Dismiss() end
		end)
	end
end

function Controller:Dismiss()
	self.token += 1
	self.notification = nil
	self.view:HideNotification()
end

function Controller:OpenReview()
	if not self.notification or self.notification.FindingCount == 0 then return end
	self.review = self.notification.Findings
	self.index = 1
	self.view:ShowFinding(self.review[self.index], self.index, #self.review)
end

function Controller:Move(delta)
	if not self.review then return end
	self.index = math.clamp(self.index + delta, 1, #self.review)
	self.view:ShowFinding(self.review[self.index], self.index, #self.review)
end

function Controller:GoTo()
	if not self.review then return false end
	local ok, result, message = pcall(self.navigator.GoToFinding, self.review[self.index].Finding)
	if not ok or not result then self.view:ShowNotice(message or "Studio could not open this script.", "Low") end
	return ok and result
end

function Controller:CloseReview()
	self.review = nil
	self.view:HideReview()
end

function Controller:RemoveObject(instance)
	self.added[instance] = nil
	local function remains(entry)
		local object = entry.Finding.Instance
		return typeof(object) == "Instance" and object ~= instance
			and not object:IsDescendantOf(instance) and object:IsDescendantOf(self.root)
	end
	if self.notification and self.notification.FindingCount > 0 then
		local live = Batch.new()
		local changed = false
		for _, entry in ipairs(self.notification.Findings) do
			if remains(entry) then
				live:Add(self:AssetFor(entry.Finding.Instance), entry.Finding.Instance, { entry.Finding })
			else changed = true end
		end
		if changed then
			local summary = live:Summary()
			if summary then self:Notify(summary) else self:Dismiss() end
		end
	end
	if self.review then
		local live = {}
		local selected = self.review[self.index]
		for _, entry in ipairs(self.review) do if remains(entry) then table.insert(live, entry) end end
		if #live ~= #self.review then
			if #live == 0 then
				self:CloseReview()
				self.view:ShowNotice("The reviewed objects were removed from the place.", "Low")
			else
				self.review = live
				self.index = table.find(live, selected) or math.min(self.index, #live)
				self.view:ShowFinding(live[self.index], self.index, #live)
			end
		end
	end
end

function Controller:SetEnabled(enabled)
	if self.destroyed then return end
	self.generation += 1
	local generation = self.generation
	self.state.Enabled = enabled
	self.state.Starting = enabled
	self.flushScheduled = false
	self.batch = Batch.new()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	self.added = setmetatable({}, { __mode = "k" })
	self.importToken = nil
	self.auto.Stop()
	self:Refresh()
	if not enabled then self.state.Starting = false; self:Refresh(); return end
	-- Observe imports before library loading, then replay only the scripts
	-- inserted during that load. Existing project scripts are not scanned.
	local duringLoad = {}
	local count = 0
	table.insert(self.connections, self.root.DescendantAdded:Connect(function(instance)
		self:Track(instance)
		if self.state.Starting and Scanner.CanScan(instance) and Scanner.ShouldQueue(instance) and count < 1000 then
			count += 1; table.insert(duringLoad, instance)
		end
	end))
	task.spawn(function()
		local ok, library, source = pcall(self.provider.GetLibrary)
		if self.destroyed or generation ~= self.generation then return end
		self.state.Library = ok and library and source or "Unavailable"
		self.state.Starting = false
		if not ok or not library then
			self.view:ShowNotice("Protection paused — security library unavailable. Toggle Auto Scan to retry.", "High")
			self:Refresh(); return
		end
		local started, message = self.auto.Start(self.root, Scanner, library)
		if self.destroyed or generation ~= self.generation then return end
		if not started then self.view:ShowNotice(message or "Auto Scan could not start.", "High") end
		for _, instance in ipairs(duringLoad) do
			if started and instance:IsDescendantOf(self.root) then self.auto.Queue(instance) end
		end
		self:Refresh()
	end)
end

function Controller:Start()
	self:SetEnabled(true)
end

function Controller:Destroy()
	if self.destroyed then return end
	self:SetEnabled(false)
	self.destroyed = true
	self.removalConnection:Disconnect()
	self.auto.SetCallbacks({ OnScanCompleted = false, OnQueueChanged = false,
		OnLargeQueue = false, OnEnabledChanged = false, OnScanError = false })
	self.notification = nil; self.review = nil
	self.view:Destroy()
end

return Controller
