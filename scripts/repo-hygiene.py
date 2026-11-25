#!/usr/bin/env python3
"""Static repository hygiene check for OpenEgiz v2.0.0+.

Fails if:
  1. Lab hostnames, course paths, private IPv4 addresses, or the retired
     repository slug appear in tracked text.
  2. Unauthorized `opentwins` identifiers appear outside:
     - the fixed Grafana plugin ID (`ertis-opentwins-app`)
     - upstream OpenTwins attribution links (`https://github.com/ertis-research/opentwins`)
     - legal / license / migration / ADR files (`NOTICE`, `LICENSE`, `LICENSES/*`,
       `CONTRIBUTING.md`, `MIGRATION.md`, `docs/adr/*`)
     - the Grafana Plugin Bundle rebranding pipeline (`vendor/grafana-plugins/*`,
       `packaging/grafana-plugins/*`, `docs/notes-rebrand-plugins.md`)

Usage: python3 scripts/repo-hygiene.py [repo-root]
"""

import os
import re
import subprocess
import sys

BINARY_EXTS = {
    ".zip", ".png", ".jpg", ".jpeg", ".gif", ".ico",
    ".wasm", ".data", ".tar", ".gz", ".pdf",
}

BANNED_DEPLOYMENT_PATTERNS = [
    (re.compile(r"\bg[x]10(?:-\d+)?\b", re.IGNORECASE), "lab hostname"),
    (re.compile(r"~[/]course\b"), "course path"),
    (
        re.compile(r"\b(?:10[.]\d{1,3}|172[.](?:1[6-9]|2\d|3[01])|192[.]168)[.]\d{1,3}[.]\d{1,3}\b"),
        "private IPv4 address",
    ),
    (re.compile(r"\bopenegiz[/]openegiz\b", re.IGNORECASE), "retired repository slug"),
]

OPENTWINS_RE = re.compile(r"opentwins", re.IGNORECASE)

# Exact tokens allowed on any line: the fixed Grafana plugin ID and upstream links.
ALLOWED_INLINE_PATTERNS = [
    re.compile(r"ertis-opentwins-app", re.IGNORECASE),
    re.compile(r"\[OpenTwins\]\(https://github\.com/ertis-research/opentwins\)", re.IGNORECASE),
    re.compile(r"https://github\.com/ertis-research/opentwins", re.IGNORECASE),
]

# Files allowed to mention OpenTwins for legal, migration, ADR, or plugin-rebrand reasons.
ALLOWED_OPENTWINS_EXACT = {
    "NOTICE",
    "LICENSE",
    "CONTRIBUTING.md",
    "MIGRATION.md",
    "docs/notes-rebrand-plugins.md",
    "docs/arm64-audit.md",
    "docs/notes-mongodb-arm64.md",
}

ALLOWED_OPENTWINS_PREFIXES = (
    "LICENSES/",
    "docs/adr/",
    "vendor/grafana-plugins/",
    "packaging/grafana-plugins/",
)


def list_files(root: str) -> list[str]:
    try:
        raw = subprocess.check_output(
            ["git", "-C", root, "ls-files", "-z"],
            stderr=subprocess.PIPE,
        )
        return [p.decode("utf-8", errors="surrogateescape") for p in raw.split(b"\0") if p]
    except subprocess.CalledProcessError:
        collected: list[str] = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in filenames:
                rel = os.path.relpath(os.path.join(dirpath, name), root)
                collected.append(rel.replace(os.sep, "/"))
        return collected


def is_binary(path: str) -> bool:
    _, ext = os.path.splitext(path.lower())
    return ext in BINARY_EXTS


def is_opentwins_exempt(path: str) -> bool:
    if path in ALLOWED_OPENTWINS_EXACT:
        return True
    return any(path.startswith(prefix) for prefix in ALLOWED_OPENTWINS_PREFIXES)


def main() -> int:
    default_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    root = sys.argv[1] if len(sys.argv) > 1 else default_root
    files = list_files(root)
    violations: list[str] = []

    for rel in sorted(files):
        if rel == "scripts/repo-hygiene.py":
            continue
        if is_binary(rel):
            continue
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            continue
        try:
            with open(full, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        text = data.decode("utf-8", errors="replace")
        exempt_opentwins = is_opentwins_exempt(rel)

        for lineno, line in enumerate(text.splitlines(), start=1):
            for pat, label in BANNED_DEPLOYMENT_PATTERNS:
                if pat.search(line):
                    violations.append(f"FAIL {rel}:{lineno}: found {label}")

            if not exempt_opentwins and OPENTWINS_RE.search(line):
                scrubbed = line
                for allowed in ALLOWED_INLINE_PATTERNS:
                    scrubbed = allowed.sub("", scrubbed)
                if OPENTWINS_RE.search(scrubbed):
                    violations.append(
                        f"FAIL {rel}:{lineno}: unauthorized 'opentwins' identifier: {line.strip()}"
                    )

    if violations:
        for v in violations:
            print(v)
        print(f"\nrepo-hygiene: {len(violations)} violation(s) found", file=sys.stderr)
        return 1

    print(f"repo-hygiene: ok ({len(files)} tracked files checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
