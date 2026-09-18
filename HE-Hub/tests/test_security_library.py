from security.models import (
    Confidence,
    RuleType,
    SecurityRule,
    Severity,
)

from security.repository import SecurityRepository

from security.validator import SecurityRuleValidator


rules = [
    SecurityRule(
        id="SIG-TEST-001",
        name="Test Suspicious Signature",
        rule_type=RuleType.SIGNATURE,
        pattern="suspicious_marker",
        severity=Severity.HIGH,
        confidence=Confidence.HIGH,
        category="KnownMalware",
        description=(
            "Controlled signature used "
            "for scanner testing."
        ),
    ),

    SecurityRule(
        id="SIG-TEST-002",
        name="Test Backdoor Signature",
        rule_type=RuleType.SIGNATURE,
        pattern="backdoor_test_marker",
        severity=Severity.CRITICAL,
        confidence=Confidence.VERY_HIGH,
        category="Backdoor",
        description=(
            "Controlled backdoor signature "
            "used for scanner testing."
        ),
    ),

    SecurityRule(
        id="KEY-TEST-001",
        name="Test Suspicious Keyword",
        rule_type=RuleType.KEYWORD,
        pattern="suspicious_keyword",
        severity=Severity.MEDIUM,
        confidence=Confidence.LOW,
        category="SuspiciousCode",
        description=(
            "Controlled keyword used "
            "for scanner testing."
        ),
    ),
]


errors = (
    SecurityRuleValidator.validate_library(
        rules
    )
)

if errors:
    print("VALIDATION FAILED")

    for error in errors:
        print(error)

    raise SystemExit(1)


repository = SecurityRepository(
    "data/security.db"
)


for rule in rules:
    repository.save_rule(rule)


loaded_rules = (
    repository.get_active_rules()
)


print("==============================")
print("HE-Utilties v0.3")
print("PYTHON SECURITY TEST")
print("==============================")

print(
    "Rules stored:",
    len(loaded_rules)
)


for rule in loaded_rules:

    print(
        rule.id,
        rule.rule_type.value,
        rule.severity.value,
        rule.confidence.value
    )


repository.increment_detection(
    "SIG-TEST-001"
)

repository.increment_detection(
    "SIG-TEST-001"
)

repository.increment_detection(
    "KEY-TEST-001"
)


print()
print(
    "SIG-TEST-001 detections:",
    repository.get_detection_count(
        "SIG-TEST-001"
    )
)

print(
    "KEY-TEST-001 detections:",
    repository.get_detection_count(
        "KEY-TEST-001"
    )
)

print("==============================")
print("TEST COMPLETE")