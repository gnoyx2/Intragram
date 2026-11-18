#!/usr/bin/env python3
"""Pin the Windows installer settings that upgrades and the release workflow rely on."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "windows/installer/intragram.iss").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")


def setting(name: str) -> str:
    match = re.search(rf"^{name}=(.*)$", SCRIPT, re.MULTILINE)
    assert match, f"missing [Setup] {name}"
    return match.group(1).strip()


# AppId identifies installed copies: a new value installs a second copy instead of upgrading
assert setting("AppId") == "{{2EA84494-9B4A-48D2-93CC-3A08EED7E51A}"
# per-user install: no admin rights or UAC prompt, removable from Settings > Apps
assert setting("PrivilegesRequired") == "lowest"
assert setting("DefaultDirName") == r"{autopf}\Intragram"
assert setting("OutputBaseFilename") == "intragram-windows-x64-setup"
assert setting("UninstallDisplayIcon") == r"{app}\intragram.exe"
assert setting("LanguageDetectionMethod") == "uilanguage"
assert 'MessagesFile: "compiler:Languages\\Korean.isl"' in SCRIPT
assert re.search(r'^Source: "\{#SourceDir\}\\\*";.*\brecursesubdirs\b', SCRIPT, re.MULTILINE)
assert 'Name: "{autoprograms}\\Intragram"; Filename: "{app}\\intragram.exe"' in SCRIPT

# the release build packs the same Release folder as the zip, then installs,
# launches and removes the installer on the runner before uploading it
for needle in (
    "python3 tool/windows_installer_test.py",
    "windows\\installer\\intragram.iss",
    "dist\\intragram-windows-x64-setup.exe",
    "/VERYSILENT",
    "unins000.exe",
):
    assert needle in WORKFLOW, f"release.yml lacks {needle}"

print("Windows installer: settings and release steps pinned.")
