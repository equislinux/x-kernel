#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Static checks for a built linux-x package. Does not boot it.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: verify-package.sh PACKAGE...

Checks names, signatures, kernel release suffix, vmlinuz/pkgbase and headers.
EOF
}

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    [[ $# -gt 0 ]] && exit 0
    exit 2
fi

require_tools bsdtar
fail=0

for package in "$@"; do
    [[ -f "$package" ]] || { warn "missing package: $package"; fail=1; continue; }
    [[ "$package" == *.pkg.tar.zst ]] || { warn "not a zstd package: $package"; fail=1; continue; }

    if [[ -f "$package.sig" ]]; then
        if gpg --batch --verify "$package.sig" "$package" >/dev/null 2>&1; then
            log "signature OK: $(basename "$package")"
        else
            warn "signature FAILED: $(basename "$package")"
            fail=1
        fi
    else
        warn "unsigned package: $(basename "$package")"
    fi

    info="$(bsdtar -xOf "$package" .PKGINFO 2>/dev/null)" || {
        warn "cannot read .PKGINFO: $package"
        fail=1
        continue
    }
    pkgname="$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<<"$info")"
    pkgbase="$(awk -F ' = ' '$1 == "pkgbase" { print $2; exit }' <<<"$info")"
    pkgver="$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<<"$info")"
    [[ "$pkgname" == "$PKGBASE" || "$pkgname" == "$PKGBASE-headers" || "$pkgname" == "$PKGBASE-docs" ]] \
        || { warn "unexpected pkgname '$pkgname'"; fail=1; }
    [[ -z "$pkgbase" || "$pkgbase" == "$PKGBASE" ]] \
        || { warn "unexpected pkgbase '$pkgbase'"; fail=1; }
    [[ "$pkgname" != "linux" && "$pkgname" != "linux-headers" ]] \
        || { warn "package collides with Arch kernel: $pkgname"; fail=1; }

    listing="$(bsdtar -tf "$package" 2>/dev/null)" || {
        warn "cannot list package: $package"
        fail=1
        continue
    }

    if [[ "$pkgname" == "$PKGBASE" ]]; then
        krel="$(sed -n 's#^usr/lib/modules/\([^/]*\)/.*#\1#p' <<<"$listing" | sort -u | head -1)"
        [[ -n "$krel" ]] || { warn "no kernel module directory in $pkgname"; fail=1; continue; }
        [[ "$krel" == *-x ]] || { warn "kernel release does not end in -x: $krel"; fail=1; }
        grep -qx "usr/lib/modules/$krel/vmlinuz" <<<"$listing" \
            || { warn "missing vmlinuz in $pkgname ($krel)"; fail=1; }
        installed_base="$(bsdtar -xOf "$package" "usr/lib/modules/$krel/pkgbase" 2>/dev/null || true)"
        [[ "$installed_base" == "$PKGBASE" ]] \
            || { warn "modules pkgbase is '$installed_base', expected $PKGBASE"; fail=1; }
        log "main: $pkgname $pkgver ($krel)"
    elif [[ "$pkgname" == "$PKGBASE-headers" ]]; then
        krel="$(sed -n 's#^usr/lib/modules/\([^/]*\)/.*#\1#p' <<<"$listing" | sort -u | head -1)"
        [[ -n "$krel" ]] || { warn "no module build dir in $pkgname"; fail=1; continue; }
        grep -qx "usr/lib/modules/$krel/build/Makefile" <<<"$listing" \
            || { warn "headers package has no build/Makefile"; fail=1; }
        log "headers: $pkgname $pkgver ($krel)"
    else
        log "docs: $pkgname $pkgver"
    fi
done

if (( fail )); then
    die "package verification failed"
fi
log "package verification OK"
