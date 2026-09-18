import json

from security.models import RuleType
from security.repository import SecurityRepository


class SecurityLibraryExporter:

    @staticmethod
    def export(
        repository: SecurityRepository,
        version: str = "1.0.0",
    ) -> dict:

        rules = repository.get_active_rules()

        signatures = []
        keywords = []

        for rule in rules:

            item = {
                "Id": rule.id,
                "Name": rule.name,
                "Severity": rule.severity.value,
                "Confidence": rule.confidence.value,
                "Category": rule.category,
                "Description": rule.description,
            }

            if rule.rule_type == RuleType.SIGNATURE:

                item["Pattern"] = rule.pattern
                signatures.append(item)

            elif rule.rule_type == RuleType.KEYWORD:

                item["Keyword"] = rule.pattern
                keywords.append(item)

        return {
            "Version": version,
            "Signatures": signatures,
            "Keywords": keywords,
        }

    @staticmethod
    def export_json(
        repository: SecurityRepository,
        version: str = "1.0.0",
    ) -> str:

        library = (
            SecurityLibraryExporter.export(
                repository,
                version,
            )
        )

        return json.dumps(
            library,
            indent=2,
        )