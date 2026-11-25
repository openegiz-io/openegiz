#!/usr/bin/env python3
"""Exercise the public Offline Bundle round-trip against a published release."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CLI = [sys.executable, str(ROOT / "scripts/offline-bundle.py")]


def run(*command, **kwargs):
    return subprocess.run(command, check=True, text=True, cwd=ROOT, **kwargs).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--platform", choices=("linux/amd64", "linux/arm64"), action="append", required=True)
    parser.add_argument("--chart", type=Path)
    parser.add_argument("--chart-checksums", type=Path)
    args = parser.parse_args()
    if bool(args.chart) != bool(args.chart_checksums):
        parser.error("--chart and --chart-checksums must be supplied together")
    chart = ["--chart", args.chart, "--chart-checksums", args.chart_checksums] if args.chart else []

    with tempfile.TemporaryDirectory(prefix="openegiz-bundle-test-") as directory:
        work = Path(directory)
        run(*CLI, "export", "--tag", args.tag, "--output", work,
            *(arg for platform in args.platform for arg in ("--platform", platform)), *chart)
        bundle, = work.glob("openegiz-*.tar")
        run(*CLI, "verify", bundle)

        checkout = work / "checkout"
        run(*CLI, "restore", bundle, "--checkout", checkout)
        assert run("git", "-C", checkout, "describe", "--exact-match", capture_output=True).strip() == args.tag
        source_commit = run("git", "rev-parse", f"{args.tag}^{{commit}}", capture_output=True).strip()
        assert run("git", "-C", checkout, "rev-parse", "HEAD", capture_output=True).strip() == source_commit
        refs = run("git", "-C", checkout, "for-each-ref", "--format=%(refname)", capture_output=True).splitlines()
        assert refs == [f"refs/tags/{args.tag}"]
        assert not run("git", "-C", checkout, "remote", capture_output=True).strip()
        assert list((checkout / ".offline").glob("openegiz-*.tgz"))
        assert list((checkout / ".offline").glob("paho_mqtt-*.whl"))
        with tarfile.open(bundle, "r:") as archive:
            manifest = json.load(archive.extractfile("manifest.json"))
            platforms = sorted(set(args.platform))
            assert manifest["platforms"] == platforms
            assert all(sorted(entry["platforms"]) == platforms
                       for entry in manifest["images"].values())
            image_path = next(iter(manifest["images"].values()))["platforms"][args.platform[0]]["archive"]
            offset = archive.getmember(image_path).offset_data

        # Corrupt an artifact without changing tar metadata. Restore must verify
        # before creating a checkout or attempting a runtime import.
        with bundle.open("r+b") as stream:
            stream.seek(offset)
            byte = stream.read(1)
            stream.seek(offset)
            stream.write(bytes([byte[0] ^ 0xFF]))
        rejected = work / "rejected"
        result = subprocess.run([*CLI, "restore", bundle, "--checkout", rejected],
                                text=True, capture_output=True, cwd=ROOT)
        assert result.returncode != 0 and "checksum mismatch" in result.stderr.lower(), result.stderr
        assert not rejected.exists()

    print("Offline Bundle round-trip passed.")


if __name__ == "__main__":
    main()
