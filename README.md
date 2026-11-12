# x-kernel (prepared)

Downstream X-branded Arch kernels: `linux-x` builds from Arch's **packaging
recipe** for the stable/testing channels, and `linux-x-mainline` builds from
the AUR `linux-mainline` recipe for the mainline channel. Neither is a fork of
the Linux source tree.

Status: **prepared, not active.** The source repo is public at
<https://github.com/equislinux/x-kernel> and the watcher workflow is active,
but neither binary repo has been published and no other X repository is touched
by these scripts. Arch's `linux`/`linux-lts`/`linux-zen` remain the supported
kernels.

## Channels

| channel | upstream | X package | repo | current upstream |
|---|---|---|---|---|
| `stable` | Arch `core/linux` | `linux-x` | `[x-kernel]` | 7.2.15.arch1-1 |
| `testing` | Arch `core-testing/linux` | `linux-x` | not published | 7.3.4.arch1-1 |
| `mainline` | AUR `linux-mainline` | `linux-x-mainline` | `[x-kernel-mainline]` | 7.4rc1-1 |

`stable` follows whatever Arch ships as stable. Arch stable is still 7.2.x, so
X stable is 7.2.x today; when Arch promotes 7.3.4 the same command produces
7.3.x. `testing` is a local preview of that promotion. `mainline` is the 7.4
line; the AUR recipe currently says 7.4rc1, not rc2.

## What it does

- Fetches `archlinux/packaging/packages/linux` at a tag for stable/testing, or
  the current AUR `linux-mainline` HEAD for mainline.
- Applies a tiny variant delta:
  - stable/testing: `pkgbase=linux-x`, `pkgdesc='Linux X'`;
  - mainline: `pkgbase=linux-x-mainline`, `pkgdesc="Linux X Mainline"`.
  Sources, `config.x86_64`, patches, checksums and localversion logic stay as
  upstream provides them. The kernel release ends in `-x` or `-x-mainline`.
- Builds the main, headers and docs packages in a clean `makechrootpkg` chroot.
- Signs packages and the variant database with the project key.
- Publishes binaries to SourceForge FRS because they exceed GitHub Pages'
  100 MB/file limit. Stable and mainline have separate repos and directories.
- CI is only a watcher (`.github/workflows/kernel-watch.yml`). **Builds and
  publication are manual.**
- Repo: <https://github.com/equislinux/x-kernel>.

## Layout

```text
delta/apply.py              minimal stable/mainline recipe delta (fails on drift)
scripts/check-upstream.sh   Arch stable/testing or AUR mainline vs last build
scripts/prepare-recipe.sh   clone upstream + apply variant delta
scripts/build.sh            clean chroot build + signing + static checks
scripts/publish.sh          signed variant DB + SourceForge upload/verify
scripts/release.sh          check -> prepare -> build [-> publish]
scripts/watch-upstream.sh   report all channels; never builds or publishes
scripts/verify-package.sh   package content/signature checks
.github/workflows/kernel-watch.yml  CI watcher (no build/publish)
config.env.example          local paths and SourceForge settings
```

Outputs are isolated: `out/linux-x/stable/`, `out/linux-x/testing/` and
`out/linux-x-mainline/mainline/`.

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
./scripts/check-upstream.sh --channel stable
./scripts/check-upstream.sh --channel mainline
./scripts/prepare-recipe.sh --channel mainline
./scripts/build.sh --channel mainline       # sudo for mkarchroot/makechrootpkg
./scripts/publish.sh --channel mainline --dry-run
./scripts/publish.sh --channel mainline --yes
```

Or the orchestrator:

```bash
./scripts/release.sh --channel stable
./scripts/release.sh --channel mainline --publish --yes
```

`build.sh` only signs and writes under `out/`; it never installs the kernel.
`release.sh` without `--publish` never touches SourceForge.

## Updating from Arch/AUR

There is no merge step. Fetch the new upstream tag (stable/testing) or AUR HEAD
(mainline) and reapply the tiny delta; `delta/apply.py` aborts if the upstream
layout changed and needs review. Then rebuild and publish manually:

```bash
./scripts/release.sh --channel stable --publish --yes
```

Monthly manual cadence is enough. The GitHub Actions watcher only checks the
three upstream versions and writes a step summary.

## SourceForge setup (first time)

Create both FRS directories once (the publish script also tries):

```text
/home/frs/project/equislinux/kernel/x86_64/
/home/frs/project/equislinux/kernel-mainline/x86_64/
```

Client configurations:

```ini
[x-kernel]
SigLevel = Required
Server = https://downloads.sourceforge.net/project/equislinux/kernel/x86_64

[x-kernel-mainline]
SigLevel = Required
Server = https://downloads.sourceforge.net/project/equislinux/kernel-mainline/x86_64
```

Install explicitly, keeping Arch's kernel as fallback:

```bash
sudo xpm install --needed linux-x linux-x-headers
sudo xpm install --needed linux-x-mainline linux-x-mainline-headers
```

## Safety

- `linux-x`/`linux-x-mainline` do not replace or provide Arch `linux`; install
  them alongside.
- NVIDIA/ZFS/VirtualBox must use DKMS and the matching `-headers` package;
  Arch's prebuilt NVIDIA packages target `linux` and are not compatible.
- Watch `/boot`: X stores kernel/initramfs copies under `/boot/x/kernels`; the
  ESP is 1 GiB. Test with a minimal initramfs if needed.
- Test in QEMU, then a live USB on the laptop, then the internal install.
  Keep the Arch kernel entry and a live USB available.
- Never publish automatically: scripts require `--yes`; CI is watcher-only.
- Do not modify `x/`, `x-repo/`, `web/`, `xpm/`, `xpm-aur/`, `scripts/` or the
  ISO while this remains a prepared project.

## License

The scripts are GPL-3.0-or-later (see `LICENSE`). The kernel recipes follow
Arch/AUR packaging and upstream Linux licenses.
