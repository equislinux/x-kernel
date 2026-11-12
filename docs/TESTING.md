# Testing

Static checks are not a boot test.

## Build checks

`scripts/build.sh` signs the packages and runs `verify-package.sh`:

- `pkgname`/`pkgbase` are `linux-x`, `linux-x-headers` or `linux-x-docs`;
- the kernel release ends in `-x`;
- `vmlinuz` and `pkgbase` are present in the module directory;
- the headers package contains `build/Makefile`;
- package signatures verify.

## QEMU

Boot a disposable X/Arch test system with the built package, then check:

- `uname -r` ends in `-x`;
- `mkinitcpio -P` produces `initramfs-linux-x.img`;
- a module loads and `dkms status` shows the kernel;
- the previous Arch kernel entry still boots.

Do not replace the host's kernel or `/boot` entries from an automated test.

## Laptop

1. Live USB with a test ISO carrying `linux-x`; test WiFi, GPU, audio,
   touchpad, suspend/resume and external displays without touching the disk.
2. Only after that, install `linux-x` alongside Arch `linux`, keep the previous
   generation/entry and a live USB available.
3. If NVIDIA/DKMS fails, boot Arch `linux` and remove `linux-x`; do not force
   the new kernel as default.

## Acceptance

A publication is not approved until the QEMU test passes and the user accepts
the live USB result. Real hardware testing remains manual.
