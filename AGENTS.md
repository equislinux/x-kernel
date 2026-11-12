# Agent instructions — x-kernel

This repository is a **prepared downstream kernel recipe**, not an active X
release component. Read `../environments/x-kernel/README.md` and
`../environments/x-kernel/skills/x-kernel/SKILL.md` first.

## Hard rules

- Work only in this repository. Do not modify `x/`, `x-repo/`, `web/`, `xpm/`,
  `xpm-aur/`, `scripts/` or any other repository.
- Never read, print, copy or commit `keys/`, tokens, SSH keys or signing keys.
  The scripts reference `keys/env.sh` only at signing/publish time.
- Do not add `provides=('linux')` or `conflicts=('linux')` to any X kernel
  package; keep Arch's `linux` installed as the fallback.
- Do not publish to GitHub, SourceForge or any remote without an explicit user
  instruction. `publish.sh` requires `--yes`.
- Do not make an X kernel the default, do not remove Arch's kernel and do not
  touch the ESP/generations on the host.
- Keep the delta minimal. stable/testing use Arch's recipe; mainline uses the
  AUR `linux-mainline` recipe. No source-tree fork, no config/patch changes.
- Treat a QEMU boot as necessary but not sufficient: real laptop hardware,
  DKMS/NVIDIA, WiFi, audio and suspend still need a live USB/internal test.

## Channels

- `stable` — Arch `core/linux`, package `linux-x`, repo `[x-kernel]`.
- `testing` — Arch `core-testing/linux`, local preview output only.
- `mainline` — AUR `linux-mainline`, package `linux-x-mainline`, repo
  `[x-kernel-mainline]`.

## Expected commands

```bash
./scripts/check-upstream.sh --channel stable
./scripts/check-upstream.sh --channel mainline
./scripts/prepare-recipe.sh --channel stable
./scripts/build.sh --channel stable
./scripts/publish.sh --channel stable --dry-run
./scripts/watch-upstream.sh
```

If an upstream Arch/AUR packaging change breaks `delta/apply.py`, stop and
report the drift instead of forcing the build. CI is watcher-only; never add
automatic build/publish jobs without an explicit user request.
