from importers.google_sheets_importer import (
    GoogleSheetsImporter,
)

from security.repository import (
    SecurityRepository,
)


SHEET_URL = (
    "https://docs.google.com/spreadsheets/d/e/"
    "2PACX-1vTAA1RGYxRUDNlQ74Olr0UtPv3tNSfjFSDixvI0A4aVs-"
    "B5Z9nOZ92jW1KGh8hROliqXAwSftCWoqQO/pub?output=csv"
)


print("==============================")
print("HE-Utilties v0.3")
print("GOOGLE SHEETS IMPORT TEST")
print("==============================")


rules, errors = (
    GoogleSheetsImporter.import_csv(
        SHEET_URL
    )
)


if errors:

    print()
    print("IMPORT FAILED")

    for error in errors:
        print("ERROR:", error)

    raise SystemExit(1)


print()
print(
    "Valid rules imported:",
    len(rules)
)


for rule in rules:

    print(
        rule.id,
        "|",
        rule.rule_type.value,
        "|",
        rule.severity.value,
        "|",
        rule.confidence.value,
        "|",
        rule.source,
    )


repository = SecurityRepository(
    "data/security.db"
)


for rule in rules:
    repository.save_rule(rule)


stored_rules = (
    repository.get_active_rules()
)


print()
print(
    "Active rules in database:",
    len(stored_rules)
)


print()
print("==============================")
print("GOOGLE SHEETS IMPORT: PASS")
print("==============================")