from security.models import SecurityRule


class SecurityRuleValidator:

    @staticmethod
    def validate(rule: SecurityRule) -> list[str]:
        errors: list[str] = []

        if not rule.id.strip():
            errors.append("Rule ID cannot be empty.")

        if not rule.name.strip():
            errors.append(
                f"{rule.id or 'Unknown rule'} has no name."
            )

        if not rule.pattern.strip():
            errors.append(
                f"{rule.id or 'Unknown rule'} has no pattern."
            )

        if not rule.category.strip():
            errors.append(
                f"{rule.id or 'Unknown rule'} has no category."
            )

        return errors

    @staticmethod
    def validate_library(
        rules: list[SecurityRule]
    ) -> list[str]:

        errors: list[str] = []
        known_ids: set[str] = set()

        for rule in rules:

            if rule.id in known_ids:
                errors.append(
                    f"Duplicate rule ID: {rule.id}"
                )
            else:
                known_ids.add(rule.id)

            errors.extend(
                SecurityRuleValidator.validate(rule)
            )

        return errors