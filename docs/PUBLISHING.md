# Publishing to SourceForge

The binary repositories are separate from `[x]` because a kernel package is
larger than GitHub Pages' 100 MB per-file limit.

## Repositories

| channel | package | repo | FRS directory |
|---|---|---|---|
| stable | `linux-x` | `[x-kernel]` | `kernel/x86_64/` |
| testing | `linux-x` | not published | — |
| mainline | `linux-x-mainline` | `[x-kernel-mainline]` | `kernel-mainline/x86_64/` |

Stable and mainline are isolated: publishing one cannot remove the other's
packages, database or README. Testing is a local preview and is never
published by the scripts.

## First-time setup

Create both FRS directories (the publish script also tries to create them):

```text
/home/frs/project/equislinux/kernel/x86_64/
/home/frs/project/equislinux/kernel-mainline/x86_64/
```

## Flow

```bash
./scripts/build.sh --channel stable
./scripts/publish.sh --channel stable --dry-run
./scripts/publish.sh --channel stable --yes

./scripts/build.sh --channel mainline
./scripts/publish.sh --channel mainline --dry-run
./scripts/publish.sh --channel mainline --yes
```

`publish.sh`:

1. copies the current package set into `repo/<arch>/`;
2. creates a signed `<repo>.db`/`<repo>.files` with `repo-add`;
3. signs `SHA256SUMS`, exports `signing.pub`/`trustedkeys.gpg`;
4. uploads with `rsync` over SSH to `frs.sourceforge.net`;
5. removes old package files for the same package family from the remote
   directory;
6. downloads every public file and compares bytes with the local repo.

## Client

```ini
[x-kernel]
SigLevel = Required
Server = https://downloads.sourceforge.net/project/equislinux/kernel/x86_64

[x-kernel-mainline]
SigLevel = Required
Server = https://downloads.sourceforge.net/project/equislinux/kernel-mainline/x86_64
```

The SourceForge direct URL pattern was verified with the existing ISO files
(302 to a mirror). A direct pacman sync currently fails because pacman appends
`.sig` to the redirected URL query string (`GPGME error: No data` /
`missing required signature`). The ISO installer bundles the signed packages
and uses `pacman -U`; the online client stanzas above are the intended
configuration once the small DB is mirrored on a non-redirecting host.

Published on 2026-11-13:

- stable `linux-x 7.3.4.arch1-1` and mainline `linux-x-mainline 7.4rc1-1`;
- packages, headers, docs, signatures, DB/files, `SHA256SUMS` and public key;
- publish verification retried SourceForge downloads until the public bytes
  matched.

## Safety

- The SourceForge SSH key and signing key are never stored in this repo.
- Publication requires `--yes`; never run it from CI.
- CI is watcher-only. Monthly builds and publication are manual.
- Never delete `[x]`, ISOs, web metadata or Arch kernels from SourceForge.
