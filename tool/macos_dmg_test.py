#!/usr/bin/env python3
"""Pin the macOS DMG window: background size, icon slots and the release step that builds it."""

from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "macos/packaging"
SETTINGS = (PACKAGING / "dmg_settings.py").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", data[16:24])


# the background leaves empty slots for the two icons; the settings must put the icons there
assert png_size(PACKAGING / "dmg-background.png") == (660, 470)
assert png_size(PACKAGING / "dmg-background@2x.png") == (1320, 940)
assert 'symlinks = {"Applications": "/Applications"}' in SETTINGS
assert 'icon_locations = {appname: (180, 200), "Applications": (480, 200)}' in SETTINGS
assert re.search(r"window_rect = \(\(\d+, \d+\), \(660, 494\)\)", SETTINGS)
assert "icon_size = 128" in SETTINGS

# the release DMG is built from those settings with a pinned dmgbuild, not a bare hdiutil folder
for needle in (
    "dmgbuild==1.6.7",
    "tiffutil -cathidpicheck macos/packaging/dmg-background.png macos/packaging/dmg-background@2x.png",
    "-s macos/packaging/dmg_settings.py",
    "dist/intragram-macos.dmg",
):
    assert needle in WORKFLOW, f"release.yml lacks {needle}"
assert "hdiutil create -volname Intragram -srcfolder" not in WORKFLOW
assert "python3 tool/macos_dmg_test.py" in WORKFLOW

print("macOS DMG: background, icon slots and release step pinned.")
