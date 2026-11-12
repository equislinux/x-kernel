#!/usr/bin/env python3
"""Apply the minimal X Kernel delta to an Arch linux packaging checkout.

The delta is intentionally tiny:
  * pkgbase=linux      -> pkgbase=linux-x
  * pkgdesc='Linux'    -> pkgdesc='Linux X'

Everything else (sources, config, patches, localversion logic) stays exactly as
Arch ships it. The script fails loudly if the upstream layout changes, so a
silent recipe drift is impossible.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

PKGBASE_OLD = "linux"
PKGDESC_OLD = "pkgdesc='Linux'"


def fail(message: str) -> "NoReturn":
    print(f"delta: error: {message}", file=sys.stderr)
    raise SystemExit(2)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe", type=Path, help="Arch packaging checkout")
    parser.add_argument("--pkgbase", default="linux-x")
    parser.add_argument("--tag", default="")
    args = parser.parse_args()

    pkgbuild = args.recipe / "PKGBUILD"
    if not pkgbuild.is_file():
        fail(f"missing {pkgbuild}")
    if not re.fullmatch(r"[a-z0-9][a-z0-9._+-]*", args.pkgbase):
        fail(f"invalid pkgbase: {args.pkgbase!r}")
    if args.pkgbase == PKGBASE_OLD:
        fail("the downstream pkgbase must differ from 'linux'")

    original = pkgbuild.read_text(encoding="utf-8")
    original_sha = sha256(pkgbuild)

    if original.count(f"pkgbase={PKGBASE_OLD}") != 1:
        fail("expected exactly one 'pkgbase=linux' line")
    if original.count(PKGDESC_OLD) != 1:
        fail("expected exactly one pkgdesc='Linux' line")

    updated = original.replace(f"pkgbase={PKGBASE_OLD}", f"pkgbase={args.pkgbase}", 1)
    updated = updated.replace(PKGDESC_OLD, "pkgdesc='Linux X'", 1)

    # Do not let a future upstream change accidentally make linux-x a
    # replacement for the Arch kernel or its headers.
    for bad in (
        r"^provides=\([^)]*['\"]linux['\"][^)]*\)",
        r"^conflicts=\([^)]*['\"]linux['\"][^)]*\)",
    ):
        if re.search(bad, updated, flags=re.MULTILINE):
            fail("upstream packaging now declares linux as a provider/conflict")

    # localversion.20-pkgname derives from ${pkgbase#linux}; verify the
    # mechanism is still present so the -x suffix is not lost silently.
    if "localversion.20-pkgname" not in updated or "${pkgbase#linux}" not in updated:
        fail("Arch localversion logic changed; review the delta")

    pkgbuild.write_text(updated, encoding="utf-8")

    provenance = {
        "pkgbase": args.pkgbase,
        "upstream_tag": args.tag,
        "arch_pkgbase": PKGBASE_OLD,
        "pkbuild_sha256_before": original_sha,
        "pkbuild_sha256_after": sha256(pkgbuild),
        "applied_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    (args.recipe / ".x-kernel-delta.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        f"delta: pkgbase={args.pkgbase} tag={args.tag or 'unknown'} "
        f"sha256={provenance['pkbuild_sha256_after']}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
