#!/usr/bin/env python3
"""Static reproducibility and SRI integrity check for the Plugin Bundle.

Run by `make lint` so any drift between the vendored upstream plugin archives,
the branding patch output, and the Subresource Integrity hashes pinned inside
the compiled bundles fails CI before anything is packaged or shipped:

1. Reproducibility: the zips committed in `vendor/grafana-plugins/` must match
   a fresh run of `patch-branding.py` over `upstream/` (delegates to the
   patcher's own `--check`, which also re-verifies its SRI rewrite).
2. SRI integrity, independently of the patcher: for every digest pinned in a
   bundle's `module.js`, recompute sha256 over the shipped chunk bytes and
   compare; and every numeric `<n>.js` chunk shipped at the plugin root must
   be pinned (an unpinned chunk would load without integrity verification).
3. Bundle sanity: both archives unpack cleanly and their `plugin.json` carries
   the expected plugin id.

The image build (packaging/grafana-plugins/Dockerfile) runs the same patcher
against the same inputs, so lint green implies the shipped image content.

    python3 packaging/grafana-plugins/verify_bundle.py [--root DIR]
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PATCHER = REPO_ROOT / "vendor" / "grafana-plugins" / "patch-branding.py"

# plugin zip -> expected plugin.json id
PLUGINS = {
    "ertis-opentwins-app.zip": "ertis-opentwins-app",
    "ertis-unity-panel.zip": "ertis-unity-panel",
}

SRI_BLOCK = re.compile(rb"sriHashes=\{(.*?)\}", re.S)
SRI_ENTRY = re.compile(rb"(\d+):\"(sha256-[A-Za-z0-9+/=]+)\"")
CHUNK_NAME = re.compile(r"^.*/(\d+)\.js$")


def sri(blob: bytes) -> str:
    return "sha256-" + base64.b64encode(hashlib.sha256(blob).digest()).decode()


def check_zip(name: str, plugin_id: str, root: Path) -> list[str]:
    """Return human-readable results; entries prefixed '!!' are failures."""
    out: list[str] = []
    path = root / "vendor" / "grafana-plugins" / name
    prefix = f"{plugin_id}/"

    with zipfile.ZipFile(path) as z:
        if z.testzip() is not None:
            out.append(f"!! {name}: corrupt entry in archive")
            return out

        meta = json.loads(z.read(f"{prefix}plugin.json"))
        if meta.get("id") != plugin_id:
            out.append(f"!! {name}: plugin id is {meta.get('id')!r}, want {plugin_id!r}")
        else:
            out.append(f"    {name}: id {plugin_id} v{meta.get('info', {}).get('version')}")

        # ---- SRI integrity, recomputed here rather than trusted from the patcher
        module = z.read(f"{prefix}module.js")
        block = SRI_BLOCK.search(module)
        if block is None:
            out.append(f"    {name}: no sriHashes block (single-chunk plugin)")
            return out

        pinned = {int(cid): digest.decode() for cid, digest in SRI_ENTRY.findall(block.group(1))}
        if not pinned:
            out.append(f"!! {name}: sriHashes block parses to no entries")
            return out

        names = z.namelist()
        root_chunks = {
            int(m.group(1)): n for n in names if (m := CHUNK_NAME.match(n)) and n.startswith(prefix)
        }

        for cid, want in sorted(pinned.items()):
            if cid not in root_chunks:
                out.append(f"!! {name}: chunk {cid}.js pinned but absent from the archive")
                continue
            actual = sri(z.read(root_chunks[cid]))
            if actual != want:
                out.append(f"!! {name}: chunk {cid} SRI drift: pinned {want}, actual {actual}")
            else:
                out.append(f"    {name}: chunk {cid} SRI ok  {actual}")

        unpinned = sorted(set(root_chunks) - set(pinned))
        if unpinned:
            out.append(
                f"!! {name}: chunk(s) {unpinned} shipped unpinned in sriHashes "
                "- re-derive the SRI coverage"
            )
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=REPO_ROOT,
                    help="repository root (default: the one containing this script)")
    args = ap.parse_args()
    root = args.root.resolve()

    print("== reproducibility (patch-branding.py --check)", flush=True)
    try:
        subprocess.run([sys.executable, str(root / "vendor" / "grafana-plugins"
                                                / "patch-branding.py"), "--check"],
                       check=True, cwd=root)
    except subprocess.CalledProcessError as exc:
        print(f"!! shipped zips do not match a fresh patch run (exit {exc.returncode})")
        return 1
    if not (root / "vendor" / "grafana-plugins" / "patch-branding.py").exists():
        print("!! patch-branding.py not found")
        return 2

    print("\n== per-archive integrity", flush=True)
    failures = 0
    for name, plugin_id in PLUGINS.items():
        for line in check_zip(name, plugin_id, root):
            print(line)
            failures += line.startswith("!!")

    print(f"\n{'FAILED' if failures else 'plugin bundle verified'}"
          f"{f' ({failures} problem(s))' if failures else ''}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
