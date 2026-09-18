from dataclasses import dataclass
from enum import Enum


class RuleType(str, Enum):
    SIGNATURE = "Signature"
    KEYWORD = "Keyword"


class Severity(str, Enum):
    INFO = "Info"
    LOW = "Low"
    MEDIUM = "Medium"
    HIGH = "High"
    CRITICAL = "Critical"


class Confidence(str, Enum):
    LOW = "Low"
    MEDIUM = "Medium"
    HIGH = "High"
    VERY_HIGH = "VeryHigh"


@dataclass(frozen=True)
class SecurityRule:
    id: str
    name: str
    rule_type: RuleType
    pattern: str

    severity: Severity
    confidence: Confidence
    category: str
    description: str

    source: str = "Local"
    enabled: bool = True