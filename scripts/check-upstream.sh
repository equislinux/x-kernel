#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Compare the Arch kernel version with the last locally built linux-x tag.
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
  --channel stable|testing  Arch channel to query (default: config CHANNEL)
  --print-version           Print only the selected Arch tag and exit
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
        --print-version) print_version=1; shift ;;
        --json) json=1; shift ;;
        --quiet) quiet=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_tools curl jq
selected="$(arch_version "$channel")"
current="$(last_built_tag)"

if (( print_version )); then
    printf '%s\n' "$selected"
    exit 0
fi

if (( json )); then
    jq -n \
        --arg channel "$channel" \
        --arg selected "$selected" \
        --arg current "$current" \
        --arg status "$([[ "$selected" == "$current" ]] && echo current || echo update)" \
        '{channel:$channel,selected:$selected,current:$current,status:$status}'
else
    (( quiet )) || printf 'channel:  %s\nselected: %s\ncurrent:  %s\n' \
        "$channel" "$selected" "${current:-none}"
fi

if [[ "$selected" == "$current" ]]; then
    exit 0
fi
exit 10
