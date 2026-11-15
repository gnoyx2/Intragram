#!/usr/bin/env python3
"""Exercise packaging and failure safety without compiling Flutter again."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


SCRIPT = Path(__file__).with_name("build_web_app.sh")
with tempfile.TemporaryDirectory(prefix="intragram-web-package-") as temporary:
    root = Path(temporary).resolve()
    (root / "tool").mkdir()
    (root / "docs/web").mkdir(parents=True)
    (root / "bin").mkdir()
    shutil.copy2(SCRIPT, root / "tool/build_web_app.sh")
    flutter = root / "bin/flutter"
    flutter.write_text("""#!/usr/bin/env bash
set -eu
printf '%s\\n' "$@" > flutter-args.txt
if [[ "${FAIL_BUILD:-}" == 1 ]]; then exit 2; fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output ]]; then shift; output="$1"; fi
  shift
done
mkdir -p "$output/canvaskit"
printf '%s' '<html>fixture</html>' > "$output/index.html"
if [[ "${INCOMPLETE_BUILD:-}" != 1 ]]; then
  printf '%s' 'fixture' > "$output/main.dart.js"
fi
printf '%s' 'fixture' > "$output/canvaskit/canvaskit.js"
""")
    flutter.chmod(0o755)

    def run(base="/Intragram/web/app/", **variables):
        return subprocess.run(
            ["bash", "tool/build_web_app.sh", base], cwd=root,
            env={**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                 "BUILD_OUTPUT_DIR": "build/custom-web", **variables},
            text=True, capture_output=True,
        )

    destination = root / "docs/web/app"
    for base in ["https://example.test/", "//example.test/", "/web/../app/", "/web/./app/", "/web/app"]:
        assert run(base).returncode != 0, base
        assert not (root / "flutter-args.txt").exists(), base

    destination.mkdir()
    (destination / "keep.txt").write_text("unmanaged")
    assert run().returncode != 0
    assert (destination / "keep.txt").read_text() == "unmanaged"
    assert not (root / "flutter-args.txt").exists()
    (destination / ".intragram-web-build").write_text("previous build")

    assert run(FAIL_BUILD="1").returncode != 0
    assert (destination / "keep.txt").read_text() == "unmanaged"
    assert run(INCOMPLETE_BUILD="1").returncode != 0
    assert (destination / "keep.txt").read_text() == "unmanaged"

    result = run()
    assert result.returncode == 0, result.stderr
    assert (destination / "main.dart.js").read_text() == "fixture"
    assert (destination / "canvaskit/canvaskit.js").exists()
    assert (destination / ".intragram-web-build").exists()
    assert not (destination / "keep.txt").exists()
    assert list((root / "build").glob("web-previous.*/app/keep.txt"))
    arguments = (root / "flutter-args.txt").read_text().splitlines()
    for required in ["--release", "--no-pub", "--no-web-resources-cdn", "--no-source-maps", "lib/main_web.dart", "/Intragram/web/app/"]:
        assert required in arguments, required
    assert arguments[arguments.index("--output") + 1] == str(root / "build/custom-web")

print("web package: shared target, local resources, custom output, safe replacement and failure preservation passed")
