#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Build linux-x or linux-x-mainline in a clean chroot, sign the packages and
# run static checks.
#
# The script runs as the normal user. Only mkarchroot/makechrootpkg are invoked
# through sudo. Signing and publication use the caller's keyring and SSH key.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: build.sh [options]

Options:
  --channel stable|testing|mainline
                            Upstream channel (default: config CHANNEL)
  --tag TAG                 Exact upstream packaging tag
  --recipe-dir DIR          Reuse an already prepared recipe
  --no-clean                Do not recreate the chroot working copy
  --no-sign                 Build without signing (testing only)
  --dry-run                 Print the plan without building
  --publish                 Publish after a successful build (requires --yes)
  --yes                     Confirm publication
  -h, --help                This help

Builds are performed with makechrootpkg against
/var/lib/archbuild/x-kernel-<arch>. Arch's linux remains installed; the X
kernel package is never installed or activated by this script. Output is kept
under out/<pkgbase>/<channel>/.
EOF
}

channel="$CHANNEL"
tag=""
recipe=""
clean=1
sign=1
dry_run=0
publish=0
yes=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) [[ $# -ge 2 ]] || die "--channel needs a value"; channel="$2"; shift 2 ;;
        --stable) channel=stable; shift ;;
        --testing) channel=testing; shift ;;
        --mainline) channel=mainline; shift ;;
        --tag) [[ $# -ge 2 ]] || die "--tag needs a value"; tag="$2"; shift 2 ;;
        --recipe-dir) [[ $# -ge 2 ]] || die "--recipe-dir needs a value"; recipe="$2"; shift 2 ;;
        --no-clean) clean=0; shift ;;
        --no-sign) sign=0; shift ;;
        --dry-run) dry_run=1; shift ;;
        --publish) publish=1; shift ;;
        --yes) yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

configure_variant "$channel"
if (( publish )) && [[ "$channel" == testing ]]; then
    die "testing is a local preview; build without --publish"
fi

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo -- "$@"
    fi
}

outdir="$(build_outdir "$channel")"
if (( dry_run )); then
    recipe="${recipe:-$WORKDIR/recipe-$channel-${tag:-<selected>}}"
    log "dry-run: channel=$channel pkgbase=$PKGBASE tag=${tag:-selected-by-check}"
    log "dry-run: recipe=$recipe out=$outdir"
    log "dry-run: chroot=$CHROOT clean=$clean sign=$sign publish=$publish"
    log "dry-run: would run mkarchroot (if missing) and makechrootpkg"
    exit 0
fi

require_tools git jq gpg python3 bsdtar curl sha256sum makechrootpkg mkarchroot
if [[ "$(id -u)" -ne 0 ]]; then
    require_tools sudo
fi

if [[ -z "$recipe" ]]; then
    recipe="$("$SCRIPT_DIR/prepare-recipe.sh" --channel "$channel" ${tag:+--tag "$tag"} | tail -n1)"
else
    recipe="$(expand_path "$recipe")"
fi
[[ -f "$recipe/PKGBUILD" ]] || die "recipe has no PKGBUILD: $recipe"
grep -qx "pkgbase=$PKGBASE" "$recipe/PKGBUILD" || die "recipe is not a $PKGBASE checkout"
tag="$(jq -r '.tag // empty' "$recipe/.x-kernel-source.json" 2>/dev/null || true)"
[[ -n "$tag" ]] || die "missing .x-kernel-source.json in $recipe"

chroot_root="$CHROOT/root"
if [[ ! -d "$chroot_root" ]]; then
    log "creating clean chroot $chroot_root (first run only)"
    # mkarchroot uses readlink -f on the full working dir; its parent must
    # already exist or it reports "Please specify a working directory".
    run_privileged mkdir -p "$(dirname "$chroot_root")"
    run_privileged mkarchroot -C /etc/pacman.conf -M /etc/makepkg.conf "$chroot_root" base-devel
fi

LOGDEST="$outdir/logs"
mkdir -p "$outdir" "$SRCDEST" "$LOGDEST"
# When this script is invoked through sudo (the NOPASSWD rule), makechrootpkg
# runs makepkg as SUDO_USER. The recipe and bind-mounted directories must be
# writable by that user, not only by root.
if [[ "$(id -u)" -eq 0 && -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$WORKDIR" 2>/dev/null || true
    chown -R "$SUDO_UID:$SUDO_GID" "$recipe" "$outdir" "$SRCDEST" 2>/dev/null || true
fi
# Keep the output directory limited to the current variant build. Published
# artifacts remain in the repo/SourceForge and are not affected by this cleanup.
find "$outdir" -maxdepth 1 -type f \
    \( -name "$PKGBASE-*.pkg.tar.zst" -o -name "$PKGBASE-*.pkg.tar.zst.sig" \) \
    -delete
log "building $PKGBASE from $channel $tag"
log "chroot: $CHROOT"
log "output: $outdir"

# makepkg verifies the kernel tarball signature with the signing user's GPG
# keyring. Build a disposable keyring from Arch's public keyring plus the
# kernel.org key that signs the tarballs, then pass it only to makechrootpkg.
makepkg_gnupg="$WORKDIR/gnupg-source"
if [[ ! -f "$makepkg_gnupg/.x-kernel-ready" ]]; then
    log "preparing source-verification keyring: $makepkg_gnupg"
    rm -rf "$makepkg_gnupg"
    mkdir -p "$makepkg_gnupg"
    chmod 700 "$makepkg_gnupg"
    gpg --batch --homedir "$makepkg_gnupg" --import /usr/share/pacman/keyrings/archlinux.gpg >/dev/null 2>&1 || true
    if ! gpg --batch --homedir "$makepkg_gnupg" --list-keys 647F28654894E3BD457199BE38DBBDC86092693E >/dev/null 2>&1; then
        gpg --batch --homedir "$makepkg_gnupg" --keyserver hkps://keyserver.ubuntu.com \
            --recv-keys 647F28654894E3BD457199BE38DBBDC86092693E >/dev/null 2>&1 || true
    fi
    if gpg --batch --homedir "$makepkg_gnupg" --list-keys 647F28654894E3BD457199BE38DBBDC86092693E >/dev/null 2>&1; then
        touch "$makepkg_gnupg/.x-kernel-ready"
    else
        warn "could not import the kernel.org signing key; source verification may fail"
    fi
    if [[ "$(id -u)" -eq 0 && -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
        chown -R "$SUDO_UID:$SUDO_GID" "$makepkg_gnupg" 2>/dev/null || true
    fi
fi

chroot_args=(-r "$CHROOT")
(( clean )) && chroot_args+=(-c)
chroot_args+=(-- --nocheck)

: "${NPROC:=$(nproc)}"
: "${MAKEFLAGS:=-j$NPROC}"

(
    cd "$recipe"
    run_privileged env \
        PKGDEST="$outdir" \
        SRCDEST="$SRCDEST" \
        LOGDEST="$LOGDEST" \
        GNUPGHOME="$makepkg_gnupg" \
        NPROC="$NPROC" \
        MAKEFLAGS="$MAKEFLAGS" \
        makechrootpkg "${chroot_args[@]}"
)

mapfile -t packages < <(
    find "$outdir" -maxdepth 1 -type f -name "$PKGBASE-*.pkg.tar.zst" -printf '%f\n' 2>/dev/null | sort
)
(( ${#packages[@]} > 0 )) || die "makechrootpkg produced no $PKGBASE packages"

has_main=0
has_headers=0
for pkg in "${packages[@]}"; do
    [[ "$pkg" == "$PKGBASE-headers-"* ]] && has_headers=1
    [[ "$pkg" == "$PKGBASE-"* && "$pkg" != "$PKGBASE-headers-"* && "$pkg" != "$PKGBASE-docs-"* ]] && has_main=1
done
(( has_main )) || die "main $PKGBASE package was not produced"
(( has_headers )) || die "$PKGBASE-headers package was not produced"

for pkg in "${packages[@]}"; do
    if (( sign )); then
        load_signing_key
        sign_file "$outdir/$pkg"
    fi
    "$SCRIPT_DIR/verify-package.sh" --channel "$channel" "$outdir/$pkg"
done

printf '%s\n' "$tag" > "$outdir/version"
mapfile -t pkg_json < <(
    for pkg in "${packages[@]}"; do
        jq -n \
            --arg name "$pkg" \
            --arg sha256 "$(sha256_file "$outdir/$pkg")" \
            '{name:$name,sha256:$sha256}'
    done
)
printf '%s\n' "${pkg_json[@]}" | jq -s \
    --arg tag "$tag" \
    --arg recipe "$recipe" \
    --arg arch "$ARCH" \
    --arg built_at "$(utc_now)" \
    '{tag:$tag,arch:$arch,recipe:$recipe,built_at:$built_at,packages:.}' \
    > "$outdir/build.json"

chown_outputs
log "build OK: $tag"
printf '%s\n' "${packages[@]}"

if (( publish )); then
    if (( ! yes )); then
        log "publication requested but not confirmed; rerun with --publish --yes"
        exit 0
    fi
    "$SCRIPT_DIR/publish.sh" --yes --channel "$channel" --from "$outdir"
fi
