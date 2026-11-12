# Publishing to SourceForge

The binary repository is separate from `[x]` because a kernel package is larger
than GitHub Pages' 100 MB per-file limit.

## First-time setup

Create this FRS directory (the publish script also tries to create it):

```text
/home/frs/project/equislinux/kernel/x86_64/
```

## Flow

```bash
./scripts/build.sh
./scripts/publish.sh --dry-run
./scripts/publish.sh --yes
```

`publish.sh`:

1. copies the current package set into `repo/<arch>/`;
2. creates a signed `x-kernel.db`/`x-kernel.files` with `repo-add`;
3. signs `SHA256SUMS`, exports `signing.pub`/`trustedkeys.gpg`;
4. uploads with `rsync` over SSH to `frs.sourceforge.net`;
5. removes old `linux-x*` package files from the remote directory;
6. downloads every public file and compares bytes with the local repo.

## Client

```ini
[x-kernel]
SigLevel = Required
Server = https://downloads.sourceforge.net/project/equislinux/kernel/x86_64
```

The SourceForge direct URL pattern was verified with the existing ISO files
(302 to a mirror). If FRS redirects ever stop working as a pacman repo, keep
SourceForge as the package mirror and move only the small DB to another host.

## Safety

- The SourceForge SSH key and signing key are never stored in this repo.
- Publication requires `--yes`; CI should require a protected environment and
  human approval.
- Never delete `[x]`, ISOs, web metadata or Arch kernels from SourceForge.
