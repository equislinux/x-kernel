# Design

`linux-x` is a downstream package, not a kernel fork.

## Delta

- `pkgbase=linux` → `pkgbase=linux-x`.
- `pkgdesc='Linux'` → `pkgdesc='Linux X'`.
- Nothing else: same `config.x86_64`, sources, patches, checksums and split
  package functions as the Arch packaging tag.

The Arch PKGBUILD uses `${pkgbase#linux}` for
`localversion.20-pkgname`, so `linux-x` naturally produces a kernel release
ending in `-x` (for example `7.2.15-arch1-1-x`).

## Package names

- `linux-x`
- `linux-x-headers`
- `linux-x-docs`

`linux-x` does **not** provide or conflict with Arch's `linux`. The two can
coexist; the Arch kernel remains the fallback.

## initramfs and boot

The `mkinitcpio` package generates
`/etc/mkinitcpio.d/linux-x.preset` and `/boot/vmlinuz-linux-x`,
`/boot/initramfs-linux-x.img` from `usr/lib/modules/<release>/pkgbase`. No
custom preset is shipped by the kernel package.

## Drivers

In-tree drivers and firmware follow `config.x86_64` and are identical to Arch.
Out-of-tree modules need DKMS and `linux-x-headers`; prebuilt Arch NVIDIA
packages target `linux` and do not match `linux-x`.

## Build

`makechrootpkg` against `/var/lib/archbuild/x-kernel-x86_64`, with
`PKGDEST`/`SRCDEST`/`LOGDEST` under this repository. `pkgctl build --repo` is
not used because a custom repo has no devtools buildtool.
