local Finding = {}

function Finding.new(data)
	return {
		RuleId = data.RuleId,
		RuleName = data.RuleName,

		Instance = data.Instance,
		Path = data.Path,

		MatchedText = data.MatchedText,

		Severity = data.Severity,
		Confidence = data.Confidence,
		Category = data.Category,

		Description = data.Description,

		SourceType = data.SourceType,
	}
end

return Finding