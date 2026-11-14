# X Kernel manual

This is the practical guide for the X-branded kernel packages.

## What it is

X Kernel is a downstream of existing packaging recipes, not a kernel fork:

- `linux-x` follows Arch's `linux` packaging recipe (stable/testing);
- `linux-x-mainline` follows the AUR `linux-mainline` recipe.

The delta only changes the package base and description. The kernel source,
`config.x86_64`, patches, checksums and localversion logic stay upstream.

## Current versions

| channel | package | kernel release | SourceForge repo |
|---|---|---|---|
| stable | `linux-x 7.3.4.arch1-1` | `7.3.4-arch1-1-x` | `[x-kernel]` |
| mainline | `linux-x-mainline 7.4rc1-1` | `7.4.0-rc1-1-x-mainline` | `[x-kernel-mainline]` |

`arch1` is the Arch patch revision and `-x`/`-x-mainline` is the X marker.
Arch's own `linux`, `linux-lts` and `linux-zen` keep their normal releases.

## Installing from the X ISO

1. Boot the ISO and run `xinstall`.
2. Choose the package backend:
   - `xpm` is the native path and does not invoke pacman;
   - `pacman` only when you explicitly select it.
3. Choose `linux-x (X stable)` or `linux-x-mainline (X mainline)`.
4. Complete the install and reboot.
5. Select the X kernel entry in the firmware/GRUB/systemd-boot menu.

The X kernel packages are bundled in the ISO and signed by the project key.
The full profile also brings Arch `linux` from the package manifest, so a
typical full install has both kernels and Arch remains the default entry. The
core profile may contain only the selected X kernel. This is intentional:
X kernels are additional, not replacements.

To confirm which entry booted:

```bash
uname -r
```

Expected X releases end in `-x` or `-x-mainline`. If you see `7.3.4-arch1-1`,
you booted Arch's `linux` entry.

## SourceForge repositories

The binary repositories are published here:

- stable: `/home/frs/project/equislinux/kernel/x86_64`
- mainline: `/home/frs/project/equislinux/kernel-mainline/x86_64`

Public URLs:

```text
https://downloads.sourceforge.net/project/equislinux/kernel/x86_64
https://downloads.sourceforge.net/project/equislinux/kernel-mainline/x86_64
```

Direct pacman sync against SourceForge currently has a DB-signature redirect
caveat (`GPGME error: No data`). The ISO avoids it by installing the bundled
packages locally. The online repositories remain the published binary mirror;
use the ISO or a client that handles the redirect until the DB is mirrored on a
non-redirecting host.

## Updating the recipe

No Arch/AUR merge is performed. For every upstream update:

```bash
./scripts/check-upstream.sh --channel stable
./scripts/check-upstream.sh --channel mainline
./scripts/prepare-recipe.sh --channel stable
./scripts/prepare-recipe.sh --channel mainline
```

`delta/apply.py` stops if the expected upstream `PKGBUILD` lines or the
`${pkgbase#linux}` localversion mechanism changed. Review the drift instead of
forcing the build.

## Building and publishing

```bash
./scripts/build.sh --channel stable
./scripts/publish.sh --channel stable --dry-run
./scripts/publish.sh --channel stable --yes

./scripts/build.sh --channel mainline
./scripts/publish.sh --channel mainline --dry-run
./scripts/publish.sh --channel mainline --yes
```

Or use the orchestrator:

```bash
./scripts/release.sh --channel stable
./scripts/release.sh --channel mainline --publish --yes
```

Builds use `/var/lib/archbuild/x-kernel-x86_64` and write under
`out/<pkgbase>/<channel>/`. They never install or activate the kernel on the
host. Publication requires `--yes`; CI is watcher-only.

The build scripts need sudo for `mkarchroot`/`makechrootpkg`. The narrow sudo
allowlist covers `x-kernel/scripts/build.sh` and `release.sh` with an argument
wildcard; reapply it after workspace changes with:

```bash
sudo /home/x/repos/equislinux/utils/bin/equislinux-sudo --apply
```

## Testing

Static and boot checks are distinct:

```bash
./scripts/verify-package.sh --channel stable out/linux-x/stable/*.pkg.tar.zst
./scripts/verify-package.sh --channel mainline out/linux-x-mainline/mainline/*.pkg.tar.zst
```

The release gate is:

1. clean-chroot build and signature verification;
2. QEMU boot of the installed system;
3. select the X entry and check `uname -r`, `mkinitcpio -P`, modules and DKMS;
4. live USB on real hardware (WiFi, GPU/NVIDIA, audio, suspend);
5. keep Arch's `linux` entry as fallback.

The 2026-11-14 X ISO includes `linux-x` and `linux-x-mainline`; see the X
installer documentation for the current ISO and xpm progress behavior.

## Safety

- The X kernels do not provide or conflict with Arch `linux`.
- Keep Arch `linux`/`linux-lts` installed as fallback.
- Use DKMS with the matching `-headers` package for NVIDIA/ZFS/VirtualBox.
- Never publish automatically; keys and SourceForge credentials stay outside
  this repository.
