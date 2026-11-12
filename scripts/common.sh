#!/usr/bin/env bash
# shellcheck disable=SC2088
# Shared helpers for the x-kernel build/release scripts.
#
# This file is sourced by the other scripts. It never prints or copies secret
# material; keys are read from keys/env.sh only when a signing operation runs.
set -Eeuo pipefail
IFS=$'\n\t'

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$COMMON_DIR/.." && pwd)"

CONFIG_FILE="${X_KERNEL_CONFIG:-$ROOT/config.env}"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

: "${ARCH:=x86_64}"
: "${CHANNEL:=stable}"
: "${UPSTREAM_REPO:=https://gitlab.archlinux.org/archlinux/packaging/packages/linux.git}"
: "${AUR_MAINLINE_REPO:=https://aur.archlinux.org/linux-mainline.git}"
: "${CHROOT:=/var/lib/archbuild/x-kernel-$ARCH}"
: "${WORKDIR:=$ROOT/work}"
: "${OUTDIR:=$ROOT/out}"
: "${REPODIR:=$ROOT/repo}"
: "${KEYS_ENV:=$ROOT/../keys/env.sh}"
: "${SF_USER:=xscriptor}"
: "${SF_KEY:=$HOME/.ssh/id_ed25519_sourceforge}"
: "${SF_ARCH:=$ARCH}"

# Remember whether the config explicitly supplied variant-dependent values.
# This lets configure_variant change them later without clobbering overrides.
XK_PKGBASE_EXPLICIT="${PKGBASE+1}"
XK_REPO_NAME_EXPLICIT="${REPO_NAME+1}"
XK_SF_PATH_EXPLICIT="${SF_PATH+1}"
XK_SF_BASE_URL_EXPLICIT="${SF_BASE_URL+1}"

# Expand a leading ~ and resolve relative repo paths.
expand_path() {
    local value="$1"
    if [[ "$value" == "~/"* ]]; then
        value="$HOME/${value#\~/}"
    fi
    if [[ "$value" != /* ]]; then
        value="$ROOT/$value"
    fi
    printf '%s\n' "$value"
}

WORKDIR="$(expand_path "$WORKDIR")"
OUTDIR="$(expand_path "$OUTDIR")"
REPODIR="$(expand_path "$REPODIR")"
KEYS_ENV="$(expand_path "$KEYS_ENV")"
SF_KEY="$(expand_path "$SF_KEY")"
SRCDEST="$(expand_path "${SRCDEST:-$WORKDIR/sources}")"
LOGDEST="$(expand_path "${LOGDEST:-$OUTDIR/logs}")"

log() { printf '[x-kernel] %s\n' "$*" >&2; }
warn() { printf '[x-kernel] warning: %s\n' "$*" >&2; }
die() { printf '[x-kernel] error: %s\n' "$*" >&2; exit 2; }

# stable/testing share the linux-x package and the [x-kernel] repo. mainline is
# a separate package family and repo so neither can delete the other's files.
variant_defaults() {
    local channel="${1:-$CHANNEL}"
    local default_pkgbase default_repo default_sf_path

    case "$channel" in
        stable|testing)
            default_pkgbase=linux-x
            default_repo=x-kernel
            default_sf_path=/home/frs/project/equislinux/kernel
            ;;
        mainline)
            default_pkgbase=linux-x-mainline
            default_repo=x-kernel-mainline
            default_sf_path=/home/frs/project/equislinux/kernel-mainline
            ;;
        *)
            die "unknown channel '$channel' (expected stable, testing or mainline)"
            ;;
    esac

    [[ -n "$XK_PKGBASE_EXPLICIT" ]] || PKGBASE="$default_pkgbase"
    [[ -n "$XK_REPO_NAME_EXPLICIT" ]] || REPO_NAME="$default_repo"
    [[ -n "$XK_SF_PATH_EXPLICIT" ]] || SF_PATH="$default_sf_path"
    if [[ -z "$XK_SF_BASE_URL_EXPLICIT" ]]; then
        SF_BASE_URL="https://downloads.sourceforge.net/project/equislinux/$(basename "$SF_PATH")/$SF_ARCH"
    fi
}

configure_variant() {
    local channel="${1:-$CHANNEL}"
    variant_defaults "$channel"
    REPO_DIR="$REPODIR/$SF_ARCH"
}

# Build artifacts are kept per package family and channel so a testing or
# mainline build cannot overwrite the stable linux-x output.
build_outdir() {
    local channel="${1:-$CHANNEL}"
    printf '%s/%s/%s\n' "$OUTDIR" "$PKGBASE" "$channel"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

require_tools() {
    local tool
    for tool in "$@"; do
        command_exists "$tool" || die "missing required tool: $tool"
    done
}

arch_json_url() {
    local channel="${1:-$CHANNEL}"
    case "$channel" in
        stable)  printf 'https://archlinux.org/packages/core/x86_64/linux/json/\n' ;;
        testing) printf 'https://archlinux.org/packages/core-testing/x86_64/linux/json/\n' ;;
        *) die "unknown Arch channel '$channel' (expected stable or testing)" ;;
    esac
}

arch_version() {
    local channel="${1:-$CHANNEL}" url json
    url="$(arch_json_url "$channel")"
    json="$(curl -fsSL --max-time 30 "$url")" || die "could not query $url"
    printf '%s-%s\n' \
        "$(jq -r '.pkgver' <<<"$json")" \
        "$(jq -r '.pkgrel' <<<"$json")"
}

aur_mainline_version() {
    local url='https://aur.archlinux.org/rpc/v5/info?arg[]=linux-mainline' json version
    json="$(curl -gfsSL --max-time 30 "$url")" || die "could not query AUR linux-mainline"
    version="$(jq -r '.results[0].Version // empty' <<<"$json")"
    [[ -n "$version" ]] || die "AUR linux-mainline returned no version"
    printf '%s\n' "$version"
}

last_built_tag() {
    local channel="${1:-$CHANNEL}" dir file tag
    dir="$(build_outdir "$channel")"
    if [[ -f "$dir/version" ]]; then
        tr -d ' \n\r\t' < "$dir/version"
        return 0
    fi
    if [[ -d "$dir" ]]; then
        file="$(find "$dir" -maxdepth 1 -type f -name "$PKGBASE-*.pkg.tar.zst" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)"
    fi
    # Testing is a preview channel; do not use the published stable repo as its
    # current build marker.
    if [[ -z "${file:-}" && "$channel" != "testing" && -d "$REPO_DIR" ]]; then
        file="$(find "$REPO_DIR" -maxdepth 1 -type f -name "$PKGBASE-*.pkg.tar.zst" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)"
    fi
    [[ -n "${file:-}" ]] || return 0
    tag="$(basename "$file")"
    tag="${tag#"$PKGBASE"-}"
    tag="${tag%-"$ARCH".pkg.tar.zst}"
    printf '%s\n' "$tag"
}

load_signing_key() {
    [[ -f "$KEYS_ENV" ]] || die "signing environment not found: $KEYS_ENV"
    # shellcheck disable=SC1090
    source "$KEYS_ENV"
    [[ -n "${X_REPO_SIGN_KEY:-}" ]] || die "X_REPO_SIGN_KEY is unset after sourcing $KEYS_ENV"
    gpg --batch --list-secret-keys "$X_REPO_SIGN_KEY" >/dev/null 2>&1 \
        || die "the configured signing key is not available in this keyring"
}

sign_file() {
    local file="$1"
    [[ -f "$file" ]] || die "cannot sign missing file: $file"
    rm -f "$file.sig"
    gpg --batch --yes --detach-sign --local-user "$X_REPO_SIGN_KEY" "$file" >/dev/null 2>&1 \
        || die "could not sign $file"
    verify_signature "$file"
}

verify_signature() {
    local file="$1" sig="$1.sig"
    [[ -f "$sig" ]] || die "missing signature: $sig"
    gpg --batch --verify "$sig" "$file" >/dev/null 2>&1 \
        || die "signature verification failed: $sig"
}

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

chown_outputs() {
    if [[ "$(id -u)" -eq 0 && -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
        chown -R "$SUDO_UID:$SUDO_GID" "$OUTDIR" "$WORKDIR" 2>/dev/null || true
    fi
}

sftp_remote() {
    timeout 120 sftp -b - -i "$SF_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "$SF_USER@frs.sourceforge.net"
}

sf_list_remote() {
    sftp_remote 2>/dev/null <<EOF | awk -v p="$SF_PATH/$SF_ARCH/" '
        index($0, p) == 1 { n = substr($0, length(p) + 1); if (n != "") print n }
    ' | tr -d '\r'
ls -1 $SF_PATH/$SF_ARCH/
EOF
}

sf_delete_remote() {
    local name
    for name in "$@"; do
        [[ "$name" =~ ^[A-Za-z0-9._+~-]+$ ]] || die "refusing unsafe remote filename: $name"
    done
    {
        for name in "$@"; do
            printf 'rm %s/%s/%s\n' "$SF_PATH" "$SF_ARCH" "$name"
        done
    } | sftp_remote >/dev/null 2>&1 || die "could not delete old remote files"
}

sf_ensure_key() {
    [[ -f "$SF_KEY" ]] || die "SourceForge SSH key not found: $SF_KEY"
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "this step needs root; run it with sudo"
}

configure_variant "$CHANNEL"
