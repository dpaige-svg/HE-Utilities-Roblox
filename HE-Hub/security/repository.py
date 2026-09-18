import sqlite3
from pathlib import Path

from security.models import (
    Confidence,
    RuleType,
    SecurityRule,
    Severity,
)


class SecurityRepository:

    def __init__(self, database_path: str):
        self.database_path = database_path

        Path(database_path).parent.mkdir(
            parents=True,
            exist_ok=True
        )

        self._create_tables()

    def _connect(self):
        return sqlite3.connect(
            self.database_path
        )

    def _create_tables(self):

        with self._connect() as connection:

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS security_rules
                (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    rule_type TEXT NOT NULL,
                    pattern TEXT NOT NULL,

                    severity TEXT NOT NULL,
                    confidence TEXT NOT NULL,

                    category TEXT NOT NULL,
                    description TEXT NOT NULL,

                    source TEXT NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 1,

                    detection_count INTEGER
                        NOT NULL DEFAULT 0
                )
                """
            )

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS library_metadata
                (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """
            )

    def save_rule(
        self,
        rule: SecurityRule
    ) -> None:

        with self._connect() as connection:

            connection.execute(
                """
                INSERT INTO security_rules
                (
                    id,
                    name,
                    rule_type,
                    pattern,
                    severity,
                    confidence,
                    category,
                    description,
                    source,
                    enabled
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)

                ON CONFLICT(id) DO UPDATE SET

                    name = excluded.name,
                    rule_type = excluded.rule_type,
                    pattern = excluded.pattern,

                    severity = excluded.severity,
                    confidence = excluded.confidence,

                    category = excluded.category,
                    description = excluded.description,

                    source = excluded.source,
                    enabled = excluded.enabled
                """,
                (
                    rule.id,
                    rule.name,
                    rule.rule_type.value,
                    rule.pattern,

                    rule.severity.value,
                    rule.confidence.value,

                    rule.category,
                    rule.description,

                    rule.source,
                    1 if rule.enabled else 0,
                )
            )

    def get_active_rules(
        self
    ) -> list[SecurityRule]:

        with self._connect() as connection:

            rows = connection.execute(
                """
                SELECT
                    id,
                    name,
                    rule_type,
                    pattern,
                    severity,
                    confidence,
                    category,
                    description,
                    source,
                    enabled

                FROM security_rules

                WHERE enabled = 1

                ORDER BY id
                """
            ).fetchall()

        return [
            SecurityRule(
                id=row[0],
                name=row[1],
                rule_type=RuleType(row[2]),
                pattern=row[3],

                severity=Severity(row[4]),
                confidence=Confidence(row[5]),

                category=row[6],
                description=row[7],

                source=row[8],
                enabled=bool(row[9]),
            )
            for row in rows
        ]

    def increment_detection(
        self,
        rule_id: str,
        amount: int = 1
    ) -> bool:

        if amount <= 0:
            return False

        with self._connect() as connection:

            cursor = connection.execute(
                """
                UPDATE security_rules

                SET detection_count =
                    detection_count + ?

                WHERE id = ?
                """,
                (
                    amount,
                    rule_id
                )
            )

            return cursor.rowcount > 0

    def get_detection_count(
        self,
        rule_id: str
    ) -> int:

        with self._connect() as connection:

            row = connection.execute(
                """
                SELECT detection_count

                FROM security_rules

                WHERE id = ?
                """,
                (rule_id,)
            ).fetchone()

        if row is None:
            return 0

        return int(row[0])