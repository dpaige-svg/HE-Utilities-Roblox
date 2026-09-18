import csv

from importers.common import (
    row_to_security_rule,
)

from security.validator import (
    SecurityRuleValidator,
)


class LocalCsvImporter:

    @staticmethod
    def import_file(file_path: str):

        rules = []
        errors = []

        with open(
            file_path,
            "r",
            encoding="utf-8-sig",
            newline="",
        ) as file:

            reader = csv.DictReader(file)

            for row_number, row in enumerate(
                reader,
                start=2,
            ):
                try:
                    rule = row_to_security_rule(
                        row,
                        source="LocalCSV",
                    )

                    rule_errors = (
                        SecurityRuleValidator
                        .validate(rule)
                    )

                    if rule_errors:
                        for error in rule_errors:
                            errors.append(
                                f"Row {row_number}: "
                                f"{error}"
                            )

                        continue

                    rules.append(rule)

                except Exception as error:
                    errors.append(
                        f"Row {row_number}: "
                        f"{error}"
                    )

        library_errors = (
            SecurityRuleValidator
            .validate_library(rules)
        )

        errors.extend(library_errors)

        return rules, errors