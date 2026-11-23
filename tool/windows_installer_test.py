#!/usr/bin/env python3
"""Pin the Windows installer settings, artwork and release workflow steps."""

from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "windows/installer"
SCRIPT = (INSTALLER / "intragram.iss").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")


def setting(name: str) -> str:
    match = re.search(rf"^{name}=(.*)$", SCRIPT, re.MULTILINE)
    assert match, f"missing [Setup] {name}"
    return match.group(1).strip()


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", data[16:24])


# AppId identifies installed copies: a new value installs a second copy instead of upgrading
assert setting("AppId") == "{{2EA84494-9B4A-48D2-93CC-3A08EED7E51A}"
# per-user install: no admin rights or UAC prompt, removable from Settings > Apps
assert setting("PrivilegesRequired") == "lowest"
assert setting("DefaultDirName") == r"{autopf}\Intragram"
assert setting("OutputBaseFilename") == "intragram-windows-x64-setup"
assert setting("UninstallDisplayIcon") == r"{app}\intragram.exe"
assert setting("LanguageDetectionMethod") == "uilanguage"
assert setting("DisableWelcomePage") == "no"
assert (
    setting("WizardImageFile")
    == "wizard-welcome.png,wizard-welcome@150.png,wizard-welcome@200.png"
)
assert (
    setting("WizardSmallImageFile")
    == "wizard-small.png,wizard-small@150.png,wizard-small@200.png"
)
assert 'MessagesFile: "compiler:Languages\\Korean.isl"' in SCRIPT
assert re.search(r'^Source: "\{#SourceDir\}\\\*";.*\brecursesubdirs\b', SCRIPT, re.MULTILINE)
assert 'Name: "{autoprograms}\\Intragram"; Filename: "{app}\\intragram.exe"' in SCRIPT

# branded wizard PNGs for Welcome, Tasks header, Installing card and Finish (100/150/200% DPI)
EXPECTED_PNGS = {
    "wizard-welcome.png": (202, 386),
    "wizard-welcome@150.png": (303, 579),
    "wizard-welcome@200.png": (404, 772),
    "wizard-finish.png": (202, 386),
    "wizard-finish@150.png": (303, 579),
    "wizard-finish@200.png": (404, 772),
    "wizard-small.png": (58, 58),
    "wizard-small@150.png": (87, 87),
    "wizard-small@200.png": (116, 116),
    "wizard-installing.png": (516, 168),
    "wizard-installing@150.png": (774, 252),
    "wizard-installing@200.png": (1032, 336),
}
for name, size in EXPECTED_PNGS.items():
    assert png_size(INSTALLER / name) == size, name
for name in (
    "wizard-finish.png",
    "wizard-finish@150.png",
    "wizard-finish@200.png",
    "wizard-installing.png",
    "wizard-installing@150.png",
    "wizard-installing@200.png",
):
    assert f'Source: "{name}"; Flags: dontcopy' in SCRIPT, name

# the release build packs the same Release folder as the portable zip, then installs,
# launches and removes the installer on the runner before uploading it
for needle in (
    "python3 tool/windows_installer_test.py",
    "dist/intragram-windows-x64-portable.zip",
    "windows\\installer\\intragram.iss",
    "dist\\intragram-windows-x64-setup.exe",
    "/VERYSILENT",
    "unins000.exe",
):
    assert needle in WORKFLOW, f"release.yml lacks {needle}"
assert "dist/intragram-windows-x64.zip" not in WORKFLOW

print("Windows installer: settings, artwork and release steps pinned.")
