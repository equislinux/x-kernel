#!/usr/bin/env python3
"""Apply the minimal X Kernel delta to an upstream kernel packaging checkout.

The delta is intentionally tiny and variant-specific:
  * stable:   pkgbase=linux          -> pkgbase=linux-x
              pkgdesc='Linux'        -> pkgdesc='Linux X'
  * mainline: pkgbase=linux-mainline -> pkgbase=linux-x-mainline
              pkgdesc="Linux Mainline" -> pkgdesc="Linux X Mainline"

Everything else (sources, config, patches, localversion logic) stays exactly as
upstream ships it. The script fails loudly if the upstream layout changes, so a
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

VARIANTS = {
    "stable": {
        "pkgbase_old": "linux",
        "pkgdesc_old": "pkgdesc='Linux'",
        "pkgdesc_new": "pkgdesc='Linux X'",
        "label": "Arch",
    },
    "mainline": {
        "pkgbase_old": "linux-mainline",
        "pkgdesc_old": 'pkgdesc="Linux Mainline"',
        "pkgdesc_new": 'pkgdesc="Linux X Mainline"',
        "label": "AUR",
    },
}


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
    parser.add_argument("recipe", type=Path, help="upstream packaging checkout")
    parser.add_argument("--variant", choices=sorted(VARIANTS), default="stable")
    parser.add_argument("--pkgbase", default=None)
    parser.add_argument("--tag", default="")
    args = parser.parse_args()

    variant = VARIANTS[args.variant]
    pkgbase_old = variant["pkgbase_old"]
    pkgdesc_old = variant["pkgdesc_old"]
    pkgbase_new = args.pkgbase or ("linux-x" if args.variant == "stable" else "linux-x-mainline")

    pkgbuild = args.recipe / "PKGBUILD"
    if not pkgbuild.is_file():
        fail(f"missing {pkgbuild}")
    if not re.fullmatch(r"[a-z0-9][a-z0-9._+-]*", pkgbase_new):
        fail(f"invalid pkgbase: {pkgbase_new!r}")
    if pkgbase_new == pkgbase_old:
        fail(f"the downstream pkgbase must differ from {pkgbase_old!r}")

    original = pkgbuild.read_text(encoding="utf-8")
    original_sha = sha256(pkgbuild)

    if original.count(f"pkgbase={pkgbase_old}") != 1:
        fail(f"expected exactly one 'pkgbase={pkgbase_old}' line")
    if original.count(pkgdesc_old) != 1:
        fail(f"expected exactly one {pkgdesc_old!r} line")

    updated = original.replace(f"pkgbase={pkgbase_old}", f"pkgbase={pkgbase_new}", 1)
    updated = updated.replace(pkgdesc_old, variant["pkgdesc_new"], 1)

    # Do not let a future upstream change accidentally make linux-x a
    # replacement for the Arch kernel or its headers.
    for bad in (
        r"^provides=\([^)]*['\"]linux['\"][^)]*\)",
        r"^conflicts=\([^)]*['\"]linux['\"][^)]*\)",
    ):
        if re.search(bad, updated, flags=re.MULTILINE):
            fail("upstream packaging now declares linux as a provider/conflict")

    # localversion.20-pkgname derives from ${pkgbase#linux}; verify the
    # mechanism is still present so the -x / -x-mainline suffix is not lost
    # silently.
    if "localversion.20-pkgname" not in updated or "${pkgbase#linux}" not in updated:
        fail("upstream localversion logic changed; review the delta")

    pkgbuild.write_text(updated, encoding="utf-8")

    provenance = {
        "pkgbase": pkgbase_new,
        "variant": args.variant,
        "upstream_tag": args.tag,
        "upstream_pkgbase": pkgbase_old,
        "pkbuild_sha256_before": original_sha,
        "pkbuild_sha256_after": sha256(pkgbuild),
        "applied_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    (args.recipe / ".x-kernel-delta.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        f"delta: pkgbase={pkgbase_new} variant={args.variant} "
        f"tag={args.tag or 'unknown'} sha256={provenance['pkbuild_sha256_after']}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
