# x-kernel (prepared)

Downstream X-branded Arch kernel built from Arch's **packaging recipe**, not
from a fork of the Linux source tree.

Status: **prepared, not active.** No GitHub/SourceForge remote is configured
here, nothing has been published, and no other X repository is touched by these
scripts. `linux`/`linux-lts`/`linux-zen` from Arch remain the supported kernels.

## What it does

- Fetches `archlinux/packaging/packages/linux` at a tag (for example
  `7.2.15.arch1-1`).
- Applies a tiny delta: `pkgbase=linux-x` and `pkgdesc='Linux X'`.
  The source, `config.x86_64`, patches, checksums and localversion mechanism
  stay as Arch provides them. The kernel release ends in `-x`.
- Builds `linux-x`, `linux-x-headers` and `linux-x-docs` in a clean
  `makechrootpkg` chroot.
- Signs packages and the `[x-kernel]` database with the project key.
- Publishes the binary repo to SourceForge FRS under
  `kernel/x86_64` (packages are too large for GitHub Pages' 100 MB/file limit).
- Can be driven by a local/self-hosted CI runner; **publication is manual**.

## Layout

```text
delta/apply.py              minimal recipe delta (fails on upstream drift)
scripts/check-upstream.sh   Arch stable/testing vs last local build
scripts/prepare-recipe.sh   clone Arch tag + apply delta
scripts/build.sh            clean chroot build + signing + static checks
scripts/publish.sh          signed [x-kernel] DB + SourceForge upload/verify
scripts/release.sh          check -> prepare -> build [-> publish]
scripts/verify-package.sh   package content/signature checks
config.env.example          local paths and SourceForge settings
```

## Prerequisites

Arch host with `devtools` (`makechrootpkg`, `mkarchroot`), `git`, `gpg`,
`rsync`, `sftp`, `curl`, `jq`, `python3`, `bsdtar`, and a normal user with
sudo access for the chroot steps.

Secrets stay outside the repository:

- signing keyring and `X_REPO_SIGN_KEY`: `keys/env.sh`
- SourceForge upload key: `~/.ssh/id_ed25519_sourceforge` (default)

## Usage

```bash
cp config.env.example config.env   # optional; edit paths/URLs
./scripts/check-upstream.sh        # exit 10 when Arch moved
./scripts/prepare-recipe.sh --channel stable
./scripts/build.sh                 # sudo for mkarchroot/makechrootpkg
./scripts/publish.sh --dry-run
./scripts/publish.sh --yes         # explicit publication
```

Or the orchestrator:

```bash
./scripts/release.sh --channel stable
./scripts/release.sh --channel stable --publish --yes
```

`build.sh` only signs and writes to `out/`; it never installs the kernel.
`release.sh` without `--publish` never touches SourceForge.

## SourceForge setup (first time)

Create the FRS directory once (the script tries to create it too):

```text
/home/frs/project/equislinux/kernel/x86_64/
```

Client configuration:

```ini
[x-kernel]
SigLevel = Required
Server = https://downloads.sourceforge.net/project/equislinux/kernel/x86_64
```

Install explicitly, keeping Arch's kernel as fallback:

```bash
sudo xpm install --needed linux-x linux-x-headers
```

## Safety

- `linux-x` does not replace or provide Arch `linux`; install it alongside.
- NVIDIA/ZFS/VirtualBox must use DKMS and `linux-x-headers`; Arch's prebuilt
  NVIDIA packages target `linux` and are not compatible.
- Watch `/boot`: X stores kernel/initramfs copies under `/boot/x/kernels`; the
  ESP is 1 GiB. Test with a minimal initramfs if needed.
- Test in QEMU, then a live USB on the laptop, then the internal install.
  Keep the Arch kernel entry and a live USB available.
- Never publish automatically: scripts require `--yes`; CI should use a
  protected environment/human approval.
- Do not modify `x/`, `x-repo/`, `web/`, `xpm/`, `xpm-aur/`, `scripts/` or the
  ISO while this remains a prepared project.

## License

The scripts are GPL-3.0-or-later (see `LICENSE`). The kernel recipe follows
Arch's packaging and upstream Linux licenses.
