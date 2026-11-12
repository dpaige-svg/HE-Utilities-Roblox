from pathlib import Path
import re

text = Path("HE-Utilitiesv0.3.rbxmx").read_text(encoding="utf-8")
wanted = {
    "ObjectScanner",
    "ObjectScannerTest",
    "ScriptScanner",
    "ProjectScanner",
    "MonitorWidget",
}
pattern = re.compile(
    r'<string name="Name">([^<]+)</string>.*?<ProtectedString name="Source"><!\[CDATA\[(.*?)\]\]></ProtectedString>',
    re.S,
)
out = Path("_src")
out.mkdir(exist_ok=True)
for name, source in pattern.findall(text):
    if name in wanted:
        (out / f"{name}.lua").write_text(source, encoding="utf-8")
        print(name, len(source.splitlines()))
