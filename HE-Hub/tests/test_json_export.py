from pathlib import Path

from security.exporter import (
    SecurityLibraryExporter,
)

from security.repository import (
    SecurityRepository,
)


repository = SecurityRepository(
    "data/security.db"
)

json_data = (
    SecurityLibraryExporter.export_json(
        repository,
        version="1.0.0",
    )
)


output_path = Path(
    "data/active_security_library.json"
)

output_path.write_text(
    json_data,
    encoding="utf-8",
)


print("==============================")
print("HE-Utilties v0.3")
print("JSON EXPORT TEST")
print("==============================")

print(
    "Created:",
    output_path
)

print()
print(json_data)

print()
print("==============================")
print("PHASE 3 JSON EXPORT: PASS")
print("==============================")