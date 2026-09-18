from security.models import (
    Confidence,
    RuleType,
    SecurityRule,
    Severity,
)


def parse_bool(value: str) -> bool:
    return str(value).strip().lower() in {
        "1",
        "true",
        "yes",
        "enabled",
    }


def row_to_security_rule(
    row: dict,
    source: str,
) -> SecurityRule:

    rule_type = RuleType(
        row["rule_type"].strip()
    )

    severity = Severity(
        row["severity"].strip()
    )

    confidence = Confidence(
        row["confidence"].strip()
    )

    return SecurityRule(
        id=row["id"].strip(),
        name=row["name"].strip(),

        rule_type=rule_type,
        pattern=row["pattern"].strip(),

        severity=severity,
        confidence=confidence,

        category=row["category"].strip(),
        description=row.get(
            "description",
            ""
        ).strip(),

        source=source,

        enabled=parse_bool(
            row.get("enabled", "true")
        ),
    )