-- Only the current burst is retained. No history and no network access.
local NotificationBatch = {}
NotificationBatch.__index = NotificationBatch
local ranks = { Info = 0, Low = 1, Medium = 2, High = 3, Critical = 4 }

function NotificationBatch.new()
	return setmetatable({ findings = {}, seen = {}, assets = {}, checked = 0, critical = 0, severity = "Info" }, NotificationBatch)
end

function NotificationBatch:Add(asset, instance, findings)
	self.checked += 1
	local identity = instance or "unknown"
	local scriptSeen = self.seen[identity]
	if not scriptSeen then scriptSeen = {}; self.seen[identity] = scriptSeen end
	for _, finding in ipairs(findings) do
		local location = (finding.LocationKind or "Source") .. ":" .. (finding.LocationName or "")
		local rule = tostring(finding.RuleId or "")
		local matched = tostring(finding.MatchedText or "")
		-- Nested keys avoid delimiter collisions in paths or matched text.
		local key = finding.Instance or finding.Path or identity
		local locations = scriptSeen[key]
		if not locations then locations = {}; scriptSeen[key] = locations end
		local paths = locations[location]
		if not paths then paths = {}; locations[location] = paths end
		local matches = paths[rule]
		if not matches then matches = {}; paths[rule] = matches end
		if not matches[matched] then
			matches[matched] = true
			self.assets[asset] = true
			table.insert(self.findings, { Finding = finding, Asset = asset.Name })
			local severity = finding.Severity or "Low"
			if (ranks[severity] or 1) > (ranks[self.severity] or 0) then self.severity = severity end
			if severity == "Critical" then self.critical += 1 end
		end
	end
end

function NotificationBatch:Summary()
	if self.checked == 0 then return nil end
	local assets, name = 0, "asset"
	for asset in pairs(self.assets) do assets += 1; name = asset.Name end
	local count = #self.findings
	local message
	if count == 0 then
		message = "Asset checked — No known suspicious patterns found."
	elseif assets == 1 then
		message = string.format("Suspicious content detected — %d finding%s in %s.", count, count == 1 and "" or "s", name)
	else
		message = string.format("Multiple threats detected\n%d assets require review\n%d suspicious findings\n%d critical finding%s", assets, count, self.critical, self.critical == 1 and "" or "s")
	end
	return { Message = message, Severity = self.severity, Findings = self.findings,
		AssetCount = assets, FindingCount = count, CriticalCount = self.critical }
end

return NotificationBatch
