#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Fetch the selected upstream recipe and apply the minimal X Kernel delta.
#
# stable/testing use Arch's linux packaging. mainline uses the AUR
# linux-mainline recipe at its current HEAD.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: prepare-recipe.sh [options]

Options:
  --channel stable|testing|mainline
                            Upstream channel (default: config CHANNEL)
  --tag TAG                 Exact Arch packaging tag, or AUR version
                            (default: selected channel)
  --recipe-dir DIR          Output checkout (default: work/recipe-<channel>-<tag>)
  --dry-run                 Print what would be done
  -h, --help                This help

The recipe is an upstream checkout with only the X Kernel delta applied. For
mainline, the AUR HEAD version wins if it moved after the version check. The
kernel source is not stored in this repository.
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
        --mainline) channel=mainline; shift ;;
        --tag) [[ $# -ge 2 ]] || die "--tag needs a value"; tag="$2"; shift 2 ;;
        --recipe-dir) [[ $# -ge 2 ]] || die "--recipe-dir needs a value"; recipe="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_tools git jq python3
configure_variant "$channel"
if [[ -z "$tag" ]]; then
    tag="$("$SCRIPT_DIR/check-upstream.sh" --channel "$channel" --print-version)"
fi
[[ "$tag" =~ ^[0-9][A-Za-z0-9._+-]*-[0-9]+$ ]] || die "invalid packaging tag: $tag"

if [[ "$channel" == mainline ]]; then
    upstream="$AUR_MAINLINE_REPO"
    source_kind=aur
else
    upstream="$UPSTREAM_REPO"
    source_kind=arch
fi
recipe="${recipe:-$WORKDIR/recipe-$channel-$tag}"
recipe="$(expand_path "$recipe")"

log "channel: $channel"
log "tag:     $tag"
log "recipe:  $recipe"

if (( dry_run )); then
    log "dry-run: would clone $upstream and apply $PKGBASE delta"
    exit 0
fi

mkdir -p "$WORKDIR"
rm -rf "$recipe"
if [[ "$channel" == mainline ]]; then
    git clone --depth 1 "$upstream" "$recipe" >/dev/null 2>&1 \
        || die "could not clone $upstream"
    [[ -f "$recipe/PKGBUILD" ]] || die "upstream clone has no PKGBUILD"
    actual_version="$(awk -F= '$1 == "pkgver" { print $2; exit }' "$recipe/PKGBUILD")"
    actual_pkgrel="$(awk -F= '$1 == "pkgrel" { print $2; exit }' "$recipe/PKGBUILD")"
    [[ -n "$actual_version" && -n "$actual_pkgrel" ]] \
        || die "could not read pkgver/pkgrel from the AUR PKGBUILD"
    actual_tag="$actual_version-$actual_pkgrel"
    if [[ "$actual_tag" != "$tag" ]]; then
        warn "AUR HEAD is $actual_tag, not the selected $tag; using $actual_tag"
        tag="$actual_tag"
    fi
else
    git clone --depth 1 --branch "$tag" "$upstream" "$recipe" >/dev/null 2>&1 \
        || die "could not clone $upstream at tag $tag"
fi

[[ -f "$recipe/PKGBUILD" ]] || die "upstream clone has no PKGBUILD"
version="${tag%-*}"
pkgrel="${tag##*-}"
grep -qx "pkgver=$version" "$recipe/PKGBUILD" || die "pkgver mismatch: expected $version"
grep -qx "pkgrel=$pkgrel" "$recipe/PKGBUILD" || die "pkgrel mismatch: expected $pkgrel"
[[ -f "$recipe/config.$ARCH" ]] || die "missing upstream config.$ARCH"

delta_variant=stable
[[ "$channel" == mainline ]] && delta_variant=mainline
python3 "$ROOT/delta/apply.py" "$recipe" --variant "$delta_variant" --pkgbase "$PKGBASE" --tag "$tag"
grep -qx "pkgbase=$PKGBASE" "$recipe/PKGBUILD" || die "delta did not set pkgbase=$PKGBASE"
grep -q 'localversion.20-pkgname' "$recipe/PKGBUILD" || die "localversion logic missing"
bash -n "$recipe/PKGBUILD" || die "PKGBUILD has invalid shell syntax"

commit="$(git -C "$recipe" rev-parse HEAD)"
config_sha="$(sha256_file "$recipe/config.$ARCH")"
jq -n \
    --arg tag "$tag" \
    --arg commit "$commit" \
    --arg upstream "$upstream" \
    --arg source "$source_kind" \
    --arg variant "$delta_variant" \
    --arg pkgbase "$PKGBASE" \
    --arg arch "$ARCH" \
    --arg config_sha "$config_sha" \
    --arg prepared_at "$(utc_now)" \
    '{tag:$tag,upstream_commit:$commit,upstream_repo:$upstream,source:$source,variant:$variant,pkgbase:$pkgbase,arch:$arch,config_sha256:$config_sha,prepared_at:$prepared_at}' \
    > "$recipe/.x-kernel-source.json"

log "prepared $PKGBASE from $source_kind $tag ($commit)"
printf '%s\n' "$recipe"
