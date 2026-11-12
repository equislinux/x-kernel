# Agent instructions — x-kernel

This repository is a **prepared downstream kernel recipe**, not an active X
release component. Read `../environments/x-kernel/README.md` and
`../environments/x-kernel/skills/x-kernel/SKILL.md` first.

## Hard rules

- Work only in this repository. Do not modify `x/`, `x-repo/`, `web/`, `xpm/`,
  `xpm-aur/`, `scripts/` or any other repository.
- Never read, print, copy or commit `keys/`, tokens, SSH keys or signing keys.
  The scripts reference `keys/env.sh` only at signing/publish time.
- Do not add `provides=('linux')` or `conflicts=('linux')` to `linux-x`; keep
  Arch's `linux` installed as the fallback.
- Do not publish to GitHub, SourceForge or any remote without an explicit user
  instruction. `publish.sh` requires `--yes`.
- Do not make `linux-x` the default kernel, do not remove Arch's kernel and do
  not touch the ESP/generations on the host.
- Keep the first-phase delta minimal: `pkgbase=linux-x`, `pkgdesc` branding and
  no config/patch changes. No source-tree fork.
- Treat a QEMU boot as necessary but not sufficient: real laptop hardware,
  DKMS/NVIDIA, WiFi, audio and suspend still need a live USB/internal test.

## Expected commands

```bash
./scripts/check-upstream.sh
./scripts/prepare-recipe.sh --channel stable
./scripts/build.sh
./scripts/publish.sh --dry-run
```

If an upstream Arch packaging change breaks `delta/apply.py`, stop and report
the drift instead of forcing the build.
