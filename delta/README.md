# Delta

`apply.py` is the complete X Kernel downstream delta.

It changes only:

- `pkgbase=linux` → `pkgbase=linux-x`
- `pkgdesc='Linux'` → `pkgdesc='Linux X'`

Everything else comes from the Arch packaging tag: `config.x86_64`, sources,
patches, checksums, localversion logic and split-package functions.

The script aborts if:

- the upstream `PKGBUILD` structure changes (missing `pkgbase=linux` or
  `pkgdesc='Linux'`);
- Arch starts declaring `linux` as a `provides` or `conflicts` entry;
- the `${pkgbase#linux}` localversion mechanism disappears.

This is deliberate: a failed delta is safer than a silently wrong kernel.

`linux-x` must remain installable alongside Arch's `linux`; do not add
`provides=('linux')`, `conflicts=('linux')`, or replace the upstream
`config.x86_64` in this phase.
