import csv
import io
from urllib.request import urlopen

from importers.common import (
    row_to_security_rule,
)

from security.validator import (
    SecurityRuleValidator,
)


class GoogleSheetsImporter:

    @staticmethod
    def import_csv(url: str):

        with urlopen(
            url,
            timeout=15,
        ) as response:

            content = (
                response
                .read()
                .decode("utf-8-sig")
            )

        reader = csv.DictReader(
            io.StringIO(content)
        )

        rules = []
        errors = []

        for row_number, row in enumerate(
            reader,
            start=2,
        ):
            try:
                rule = row_to_security_rule(
                    row,
                    source="GoogleSheets",
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