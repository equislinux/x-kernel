#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Fetch an Arch linux packaging tag and apply the minimal linux-x delta.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: prepare-recipe.sh [options]

Options:
  --channel stable|testing  Arch channel (default: config CHANNEL)
  --tag TAG                 Exact Arch packaging tag (default: selected channel)
  --recipe-dir DIR          Output checkout (default: work/recipe-<tag>)
  --dry-run                 Print what would be done
  -h, --help                This help

The recipe is an Arch packaging checkout with only the linux-x delta applied.
The source tarball is not stored in this repository.
EOF
}

channel="$CHANNEL"
tag=""
recipe=""
dry_run=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) [[ $# -ge 2 ]] || die "--channel needs a value"; channel="$2"; shift 2 ;;
        --stable) channel=stable; shift ;;
        --testing) channel=testing; shift ;;
        --tag) [[ $# -ge 2 ]] || die "--tag needs a value"; tag="$2"; shift 2 ;;
        --recipe-dir) [[ $# -ge 2 ]] || die "--recipe-dir needs a value"; recipe="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_tools git jq python3
if [[ -z "$tag" ]]; then
    tag="$("$SCRIPT_DIR/check-upstream.sh" --channel "$channel" --print-version)"
fi
[[ "$tag" =~ ^[0-9][A-Za-z0-9._+-]*-[0-9]+$ ]] || die "invalid packaging tag: $tag"

recipe="${recipe:-$WORKDIR/recipe-$tag}"
recipe="$(expand_path "$recipe")"
version="${tag%-*}"
pkgrel="${tag##*-}"

log "channel: $channel"
log "tag:     $tag"
log "recipe:  $recipe"

if (( dry_run )); then
    log "dry-run: would clone $UPSTREAM_REPO at $tag and apply $PKGBASE delta"
    exit 0
fi

mkdir -p "$WORKDIR"
rm -rf "$recipe"
git clone --depth 1 --branch "$tag" "$UPSTREAM_REPO" "$recipe" >/dev/null 2>&1 \
    || die "could not clone $UPSTREAM_REPO at tag $tag"

[[ -f "$recipe/PKGBUILD" ]] || die "upstream clone has no PKGBUILD"
grep -qx "pkgver=$version" "$recipe/PKGBUILD" || die "pkgver mismatch: expected $version"
grep -qx "pkgrel=$pkgrel" "$recipe/PKGBUILD" || die "pkgrel mismatch: expected $pkgrel"
[[ -f "$recipe/config.$ARCH" ]] || die "missing upstream config.$ARCH"

python3 "$ROOT/delta/apply.py" "$recipe" --pkgbase "$PKGBASE" --tag "$tag"
grep -qx "pkgbase=$PKGBASE" "$recipe/PKGBUILD" || die "delta did not set pkgbase=$PKGBASE"
grep -q 'localversion.20-pkgname' "$recipe/PKGBUILD" || die "localversion logic missing"
bash -n "$recipe/PKGBUILD" || die "PKGBUILD has invalid shell syntax"

commit="$(git -C "$recipe" rev-parse HEAD)"
config_sha="$(sha256_file "$recipe/config.$ARCH")"
jq -n \
    --arg tag "$tag" \
    --arg commit "$commit" \
    --arg upstream "$UPSTREAM_REPO" \
    --arg pkgbase "$PKGBASE" \
    --arg arch "$ARCH" \
    --arg config_sha "$config_sha" \
    --arg prepared_at "$(utc_now)" \
    '{tag:$tag,upstream_commit:$commit,upstream_repo:$upstream,pkgbase:$pkgbase,arch:$arch,config_sha256:$config_sha,prepared_at:$prepared_at}' \
    > "$recipe/.x-kernel-source.json"

log "prepared $PKGBASE from Arch $tag ($commit)"
printf '%s\n' "$recipe"
