from importers.local_csv_importer import (
    LocalCsvImporter,
)

from security.repository import (
    SecurityRepository,
)


print("==============================")
print("HE-Utilties v0.3")
print("PHASE 2 IMPORT TEST")
print("==============================")


# --------------------------------
# Import local CSV
# --------------------------------

rules, errors = (
    LocalCsvImporter.import_file(
        "data/test_rules.csv"
    )
)


# --------------------------------
# Check errors
# --------------------------------

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


# --------------------------------
# Display imported rules
# --------------------------------

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


# --------------------------------
# Save to database
# --------------------------------

repository = SecurityRepository(
    "data/security.db"
)


for rule in rules:
    repository.save_rule(rule)


# --------------------------------
# Read database back
# --------------------------------

stored_rules = (
    repository.get_active_rules()
)


print()
print(
    "Active rules in database:",
    len(stored_rules)
)


for rule in stored_rules:

    print(
        rule.id,
        "|",
        rule.source,
    )


print()
print("==============================")
print("PHASE 2 LOCAL IMPORT: PASS")
print("==============================")