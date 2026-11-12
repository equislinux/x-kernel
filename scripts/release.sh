#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Orchestrate the x-kernel pipeline: check, prepare, build, optional publish.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: release.sh [options]

Options:
  --channel stable|testing|mainline
                            Upstream channel (default: config CHANNEL)
  --tag TAG                 Exact upstream packaging tag
  --force                   Rebuild even if the selected tag is already built
  --publish                 Publish after a successful build
  --yes                     Confirm publication (required with --publish)
  --dry-run                 Print the plan only
  -h, --help                This help

Without --publish this only builds and signs; SourceForge is not touched.
EOF
}

channel="$CHANNEL"
tag=""
force=0
publish=0
yes=0
dry_run=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) [[ $# -ge 2 ]] || die "--channel needs a value"; channel="$2"; shift 2 ;;
        --stable) channel=stable; shift ;;
        --testing) channel=testing; shift ;;
        --mainline) channel=mainline; shift ;;
        --tag) [[ $# -ge 2 ]] || die "--tag needs a value"; tag="$2"; shift 2 ;;
        --force) force=1; shift ;;
        --publish) publish=1; shift ;;
        --yes) yes=1; shift ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

configure_variant "$channel"
if (( publish )) && [[ "$channel" == testing ]]; then
    die "testing is a local preview; do not publish it"
fi
selected="${tag:-$("$SCRIPT_DIR/check-upstream.sh" --channel "$channel" --print-version)}"
current="$(last_built_tag "$channel")"

log "channel:  $channel"
log "selected: $selected"
log "current:  ${current:-none}"

if [[ "$selected" == "$current" && "$force" -eq 0 ]]; then
    log "already built; use --force to rebuild the same tag"
    exit 0
fi

if (( dry_run )); then
    log "dry-run: would prepare, build and sign $selected${publish:+, then publish only with --yes}"
    exit 0
fi

recipe="$("$SCRIPT_DIR/prepare-recipe.sh" --channel "$channel" --tag "$selected" | tail -n1)"
build_args=(--channel "$channel" --recipe-dir "$recipe")
(( publish )) && build_args+=(--publish)
(( yes )) && build_args+=(--yes)
"$SCRIPT_DIR/build.sh" "${build_args[@]}"
