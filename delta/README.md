# Delta

`apply.py` is the complete X Kernel downstream delta. It supports two recipe
families:

- `stable` / `testing` (Arch packaging):
  - `pkgbase=linux` → `pkgbase=linux-x`
  - `pkgdesc='Linux'` → `pkgdesc='Linux X'`
- `mainline` (AUR linux-mainline):
  - `pkgbase=linux-mainline` → `pkgbase=linux-x-mainline`
  - `pkgdesc="Linux Mainline"` → `pkgdesc="Linux X Mainline"`

Everything else comes from the upstream recipe: `config.x86_64`, sources,
patches, checksums, localversion logic and split-package functions. The same
`${pkgbase#linux}` mechanism produces `-x` or `-x-mainline`.

The script aborts if:

- the expected upstream `PKGBUILD` lines are missing or ambiguous;
- upstream starts declaring `linux` as a `provides` or `conflicts` entry;
- the `${pkgbase#linux}` localversion mechanism disappears.

This is deliberate: a failed delta is safer than a silently wrong kernel.

The X kernels must remain installable alongside Arch's `linux`; do not add
`provides=('linux')`, `conflicts=('linux')`, or replace the upstream
`config.x86_64` in this phase.
