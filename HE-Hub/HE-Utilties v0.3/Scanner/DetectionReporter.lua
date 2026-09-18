local HttpService = game:GetService("HttpService")
local DetectionReporter = {}
local URL = "http://localhost:8000/detections"

function DetectionReporter.Aggregate(findings, counts)
	counts = counts or {}
	for _, finding in ipairs(findings) do
		local id = finding.RuleId
		if type(id) == "string" and id:match("%S") then
			counts[id] = (counts[id] or 0) + 1
		end
	end
	return counts
end

function DetectionReporter.Report(counts)
	-- Construct a fresh allowlisted payload. Findings never enter JSONEncode.
	local detections = {}
	for id, count in pairs(counts) do
		if type(id) == "string" and id:match("%S")
			and type(count) == "number" and count > 0
			and count <= 2147483647 and count % 1 == 0 then
			table.insert(detections, { ruleId = id, count = count })
		end
	end
	if #detections == 0 then return true end
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ detections = detections }),
		})
	end)
	if not ok then return false, "Detection endpoint unavailable" end
	return response.Success, response.StatusCode
end

return DetectionReporter
