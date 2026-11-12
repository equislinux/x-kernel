#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Compare the selected upstream kernel version with the last local build.
#
# stable/testing track Arch's packaged kernel; mainline tracks the AUR
# linux-mainline recipe (which follows kernel.org mainline).
#
# Exit codes:
#   0  current
#  10  update available
#   2  error
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: check-upstream.sh [options]

Options:
  --channel stable|testing|mainline
                            Upstream channel (default: config CHANNEL)
  --print-version           Print only the selected tag and exit
  --json                    Machine-readable output
  --quiet                   Only the exit code
  -h, --help                This help

Exit 0 when current, 10 when a rebuild is needed, 2 on error.
EOF
}

channel="$CHANNEL"
print_version=0
json=0
quiet=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) [[ $# -ge 2 ]] || die "--channel needs a value"; channel="$2"; shift 2 ;;
        --stable) channel=stable; shift ;;
        --testing) channel=testing; shift ;;
        --mainline) channel=mainline; shift ;;
        --print-version) print_version=1; shift ;;
        --json) json=1; shift ;;
        --quiet) quiet=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_tools curl jq
configure_variant "$channel"
if [[ "$channel" == mainline ]]; then
    selected="$(aur_mainline_version)"
else
    selected="$(arch_version "$channel")"
fi
current="$(last_built_tag "$channel")"

if (( print_version )); then
    printf '%s\n' "$selected"
    exit 0
fi

if (( json )); then
    jq -n \
        --arg channel "$channel" \
        --arg pkgbase "$PKGBASE" \
        --arg selected "$selected" \
        --arg current "${current:-none}" \
        --arg status "$([[ "$selected" == "$current" ]] && echo current || echo update)" \
        '{channel:$channel,pkgbase:$pkgbase,selected:$selected,current:$current,status:$status}'
else
    (( quiet )) || printf 'channel:  %s\nselected: %s\ncurrent:  %s\n' \
        "$channel" "$selected" "${current:-none}"
fi

if [[ "$selected" == "$current" ]]; then
    exit 0
fi
exit 10
