local AutoScanService = {}
local DefaultScanner = require(script.Parent.ScriptScanner)
local Provider = require(script.Parent.Parent.Security.SecurityLibraryProvider)
local Reporter = require(script.Parent.DetectionReporter)
local generation = 0
local starting = false
local reportBusy = false
local pendingReports = {}
local pendingRuleCount = 0



local BATCH_SIZE = 5


local BATCH_DELAY = 0.03

local SOURCE_DEBOUNCE = 0.75

local MAX_QUEUE_SIZE = 1000

local enabled = false
local running = false
local pausedForLargeQueue = false

local rootInstance = nil
local function inRoot(instance)
	return rootInstance ~= nil and (instance == rootInstance or instance:IsDescendantOf(rootInstance))
end
local scriptScanner = nil
local securityLibrary = nil

local queue = {}


local queued = {}


local debounceTokens = {}

local connections = {}

local watchedScripts = {}


local callbacks = {
	OnFindings = nil,
	OnScanError = nil,
	OnQueueChanged = nil,
	OnLargeQueue = nil,
	OnEnabledChanged = nil,
}


local function fireCallback(
	callbackName,
	...
)
	local callback =
		callbacks[callbackName]

	if type(callback) ~= "function" then
		return
	end

	local success, errorMessage =
		pcall(
			callback,
			...
		)

	if not success then
		warn(
			"[HE-Utilties v0.3]",
			"Callback failed:",
			callbackName,
			errorMessage
		)
	end
end

local function getQueueSize()
	return #queue
end

local function updateQueueCallback()
	fireCallback(
		"OnQueueChanged",
		getQueueSize()
	)
end

local function isScript(instance)
	if not scriptScanner then
		return false
	end

	return (scriptScanner.CanScan or scriptScanner.IsScript)(instance)
end

local function clearQueue()
	table.clear(queue)
	table.clear(queued)

	updateQueueCallback()
end

local function queueScript(instance)
	if not enabled then
		return false
	end

	if pausedForLargeQueue then
		return false
	end

	if not instance or not inRoot(instance) then
		return false
	end

	if instance.Parent == nil then
		return false
	end

	if not isScript(instance) then
		return false
	end

	if queued[instance] then
		return false
	end


	if #queue >= MAX_QUEUE_SIZE then
		pausedForLargeQueue = true

		fireCallback(
			"OnLargeQueue",
			#queue
		)

		warn(
			"[HE-Utilties v0.3]",
			"Auto Scan paused because the scan queue",
			"became too large."
		)

		return false
	end

	queued[instance] = true

	table.insert(
		queue,
		instance
	)

	updateQueueCallback()

	return true
end


local function scanScript(instance)
	if not instance or not inRoot(instance) then
		return
	end

	if instance.Parent == nil then
		return
	end

	local success, findings =
		pcall(function()
			return scriptScanner.ScanInstance(
				instance,
				securityLibrary
			)
		end)

	if not success then
		warn(
			"[HE-Utilties v0.3]",
			"Could not scan:",
			instance:GetFullName()
		)

		fireCallback(
			"OnScanError",
			instance,
			findings
		)

		return
	end

	local counts = Reporter.Aggregate(findings)
	fireCallback("OnScanCompleted", instance, findings, counts)
	if #findings > 0 then
		fireCallback(
			"OnFindings",
			instance,
			findings
		)
	end
	return counts
end

local function processQueue()
	if running then
		return
	end

	if not enabled then
		return
	end

	if pausedForLargeQueue then
		return
	end

	running = true
	local session = generation

	task.defer(function()

		while enabled and generation == session
			and not pausedForLargeQueue
			and #queue > 0 do

			local processed =
				0
			local counts = {}
			local remaining = #queue

			while processed < BATCH_SIZE and remaining > 0
				and enabled and generation == session and #queue > 0 do
				remaining -= 1

				local instance =
					table.remove(
						queue,
						1
					)

				if instance and debounceTokens[instance] and debounceTokens[instance] > os.clock() then
					table.insert(queue, instance)
					continue
				end
				if instance then
					queued[instance] = nil
					debounceTokens[instance] = nil

					local result = scanScript(instance)
					for id, count in pairs(result or {}) do
						counts[id] = (counts[id] or 0) + count
					end
				end

				processed += 1
			end

			if generation ~= session or not enabled then return end
			-- Bounded count-only outbox, with one HTTP request in flight.
			for id, count in pairs(counts) do
				if pendingReports[id] or pendingRuleCount < 1000 then
					if not pendingReports[id] then pendingRuleCount += 1 end
					pendingReports[id] = math.min((pendingReports[id] or 0) + count, 2147483647)
				end
			end
			if next(pendingReports) and not reportBusy then
				reportBusy = true
				task.spawn(function()
					while next(pendingReports) do
						local reportSession = generation
						local report = pendingReports
						pendingReports = {}
						pendingRuleCount = 0
						local ok, success, detail = pcall(Reporter.Report, report)
						if generation == reportSession and enabled then
							fireCallback("OnReportCompleted", ok and success, report, detail)
						end
						task.wait(BATCH_DELAY)
					end
					reportBusy = false
				end)
			end
			updateQueueCallback()


			task.wait(BATCH_DELAY)
		end

		if generation ~= session then return end
		running = false

		updateQueueCallback()

		if enabled
			and not pausedForLargeQueue
			and #queue > 0 then

			processQueue()
		end
	end)
end


local function scheduleSourceScan(instance)
	if not enabled or not inRoot(instance) then return end
	-- Debounce deadlines share the bounded queue; no task is spawned per edit.
	if queued[instance] or queueScript(instance) then
		debounceTokens[instance] = os.clock() + SOURCE_DEBOUNCE
	end
	processQueue()
end

local function watchScript(instance)
	if not enabled or not isScript(instance) or watchedScripts[instance] then return end
	if scriptScanner.WatchInstance then
		watchedScripts[instance] = scriptScanner.WatchInstance(instance, function() scheduleSourceScan(instance) end)
		return
	end
	local sourceConnection = instance:GetPropertyChangedSignal("Source"):Connect(function()
		scheduleSourceScan(instance)
	end)
	watchedScripts[instance] = sourceConnection
end

local function unwatchScript(instance)
	local connection = watchedScripts[instance]
	if connection then connection:Disconnect() end
	watchedScripts[instance] = nil
	debounceTokens[instance] = nil
	queued[instance] = nil
	local index = table.find(queue, instance)
	if index then table.remove(queue, index) end
end

function AutoScanService.SetCallbacks(
	newCallbacks
)
	if type(newCallbacks) ~= "table" then
		return
	end

	for name, callback in pairs(
		newCallbacks
		) do
		if callbacks[name] ~= nil
			or name == "OnFindings"
			or name == "OnScanError"
			or name == "OnQueueChanged"
			or name == "OnLargeQueue"
			or name == "OnEnabledChanged"
			or name == "OnScanCompleted"
			or name == "OnReportCompleted" then

			callbacks[name] =
				callback
		end
	end
end


function AutoScanService.Start(
	root,
	scanner,
	library
)
	if enabled or starting then
		return false,
			"Auto Scan is already running."
	end

	if typeof(root) ~= "Instance" then
		return false,
			"Auto Scan requires a root Instance."
	end

	scanner = scanner or DefaultScanner
	if library == nil then
		starting = true
		local session = generation
		local ok, result = pcall(Provider.GetLibrary)
		if generation ~= session then return false, "Start cancelled" end
		starting = false
		if not ok then return false, "Security library unavailable" end
		library = result
	end
	if type(scanner) ~= "table" then
		return false,
			"Auto Scan requires ScriptScanner."
	end

	if type(scanner.ScanInstance)
		~= "function" then

		return false,
			"ScriptScanner.ScanInstance is missing."
	end

	if type(scanner.IsScript)
		~= "function" then

		return false,
			"ScriptScanner.IsScript is missing."
	end

	if type(library) ~= "table" then
		return false,
			"Security library is invalid."
	end


	rootInstance =
		root

	scriptScanner =
		scanner

	securityLibrary =
		library

	enabled =
		true

	running =
		false

	pausedForLargeQueue =
		false

	clearQueue()

	table.clear(
		debounceTokens
	)

	table.clear(
		watchedScripts
	)


	watchScript(rootInstance)


	local descendantAddedConnection =
		rootInstance.DescendantAdded:Connect(
			function(instance)

				if not enabled then
					return
				end

				if not isScript(instance) then
					return
				end

				watchScript(instance)

				if not scriptScanner.ShouldQueue or scriptScanner.ShouldQueue(instance) then
					scheduleSourceScan(instance)
				end
			end
		)

	table.insert(
		connections,
		descendantAddedConnection
	)
	table.insert(connections, rootInstance.DescendantRemoving:Connect(unwatchScript))
	table.insert(connections, rootInstance.Destroying:Connect(AutoScanService.Stop))
	if scriptScanner.WatchRoot then
		table.insert(connections, scriptScanner.WatchRoot(rootInstance, scheduleSourceScan))
	end
	local session = generation
	local extended = scriptScanner.WatchInstance ~= nil
	for index, instance in ipairs(rootInstance:GetDescendants()) do
		if not enabled or generation ~= session then return false, "Start cancelled" end
		watchScript(instance)
		if extended and index % 100 == 0 then task.wait() end
	end
	if not enabled or generation ~= session then return false, "Start cancelled" end

	fireCallback(
		"OnEnabledChanged",
		true
	)

	print(
		"[HE-Utilties v0.3]",
		"Auto Scan enabled."
	)

	return true
end


function AutoScanService.Stop()
	generation += 1
	starting = false
	pendingReports = {}
	pendingRuleCount = 0
	if not enabled then
		return
	end

	enabled = false
	running = false
	pausedForLargeQueue = false
	for instance, connection in pairs(watchedScripts) do
		connection:Disconnect()
	end

	for _, connection in ipairs(
		connections
		) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

	table.clear(
		connections
	)


	clearQueue()

	table.clear(
		debounceTokens
	)

	table.clear(
		watchedScripts
	)

	rootInstance =
		nil

	scriptScanner =
		nil

	securityLibrary =
		nil

	fireCallback(
		"OnEnabledChanged",
		false
	)

	print(
		"[HE-Utilties v0.3]",
		"Auto Scan disabled."
	)
end

function AutoScanService.Queue(
	instance
)
	local added =
		queueScript(instance)

	if added then
		processQueue()
	end

	return added
end

function AutoScanService.Resume()
	if not enabled then
		return false
	end

	if not pausedForLargeQueue then
		return true
	end

	pausedForLargeQueue =
		false

	processQueue()

	return true
end


function AutoScanService.ClearQueue()
	clearQueue()

	pausedForLargeQueue =
		false
end


function AutoScanService.IsEnabled()
	return enabled
end

function AutoScanService.IsRunning()
	return enabled
end

function AutoScanService.IsProcessing()
	return running
end

function AutoScanService.IsPaused()
	return pausedForLargeQueue
end

function AutoScanService.GetQueueSize()
	return #queue
end

return AutoScanService
