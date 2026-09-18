from security.exporter import (
    SecurityLibraryExporter,
)

from security.repository import (
    SecurityRepository,
)


repository = SecurityRepository(
    "data/security.db"
)


library = (
    SecurityLibraryExporter.export(
        repository,
        version="1.0.0",
    )
)


print("==============================")
print("HE-Utilties v0.3")
print("PHASE 3 EXPORT TEST")
print("==============================")


print(
    "Version:",
    library["Version"]
)

print(
    "Signatures:",
    len(library["Signatures"])
)

print(
    "Keywords:",
    len(library["Keywords"])
)


print()
print("SIGNATURES")

for rule in library["Signatures"]:

    print(
        rule["Id"],
        "|",
        rule["Pattern"],
    )


print()
print("KEYWORDS")

for rule in library["Keywords"]:

    print(
        rule["Id"],
        "|",
        rule["Keyword"],
    )


print()
print("==============================")
print("PHASE 3 EXPORT: PASS")
print("==============================")