# Design

`linux-x` and `linux-x-mainline` are downstream packages, not kernel forks.

## Channels and deltas

### stable/testing (Arch packaging)

- `pkgbase=linux` → `pkgbase=linux-x`.
- `pkgdesc='Linux'` → `pkgdesc='Linux X'`.
- Nothing else: same `config.x86_64`, sources, patches, checksums and split
  package functions as the Arch packaging tag.

The Arch PKGBUILD uses `${pkgbase#linux}` for
`localversion.20-pkgname`, so `linux-x` produces a kernel release ending in
`-x` (for example `7.2.15-arch1-1-x`). `stable` and `testing` share this
package name and `[x-kernel]` repo; only stable is published.

### mainline (AUR linux-mainline)

- `pkgbase=linux-mainline` → `pkgbase=linux-x-mainline`.
- `pkgdesc="Linux Mainline"` → `pkgdesc="Linux X Mainline"`.
- Nothing else: same mainline git source, `config.x86_64` and split package
  functions as the AUR recipe.

The same `${pkgbase#linux}` logic produces a release ending in `-x-mainline`.
Mainline uses a separate package family and `[x-kernel-mainline]` repo so a
stable publish cannot delete mainline files.

## Package names

- stable/testing: `linux-x`, `linux-x-headers`, `linux-x-docs`.
- mainline: `linux-x-mainline`, `linux-x-mainline-headers`,
  `linux-x-mainline-docs`.

Neither provides or conflicts with Arch's `linux`. They can coexist; the Arch
kernel remains the fallback.

## initramfs and boot

The `mkinitcpio` package generates
`/etc/mkinitcpio.d/<pkgbase>.preset` and `/boot/vmlinuz-<pkgbase>`,
`/boot/initramfs-<pkgbase>.img` from `usr/lib/modules/<release>/pkgbase`.
Neither kernel package ships a custom preset.

## Drivers

In-tree drivers and firmware follow `config.x86_64` and are identical to Arch.
Out-of-tree modules need DKMS and the matching `-headers` package; prebuilt
Arch NVIDIA packages target `linux` and do not match either X kernel.

## Build

`makechrootpkg` against `/var/lib/archbuild/x-kernel-x86_64`, with
`PKGDEST`/`SRCDEST`/`LOGDEST` under this repository. Output is isolated per
package and channel: `out/<pkgbase>/<channel>/`. `pkgctl build --repo` is not
used because a custom repo has no devtools buildtool.

## Updates

No Arch/AUR merge is performed. The new upstream recipe is fetched and the
tiny delta is reapplied; `delta/apply.py` aborts if the expected lines or
localversion mechanism changed.
