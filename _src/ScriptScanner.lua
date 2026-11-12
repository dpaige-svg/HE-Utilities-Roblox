local ScriptScanner =
	require(script.Parent["ScriptScanner"])

local ProjectScanner = {}

function ProjectScanner.Scan(
	root,
	securityLibrary
)
	local findings = {}

	local function scanInstance(instance)
		local success, results =
			pcall(function()
				return ScriptScanner.ScanInstance(
					instance,
					securityLibrary
				)
			end)

		if not success then
			warn(
				"HE-Utilties v0.3 could not scan:",
				instance:GetFullName()
			)

			return
		end

		for _, finding in ipairs(results) do
			table.insert(findings, finding)
		end
	end

	scanInstance(root)

	for _, descendant in ipairs(
		root:GetDescendants()
		) do
		scanInstance(descendant)
	end

	return findings
end

return ProjectScanner