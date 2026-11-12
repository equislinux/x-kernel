#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Report upstream kernel versions without building or publishing anything.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: watch-upstream.sh [--json]

Checks stable (Arch), testing (Arch testing) and mainline (AUR linux-mainline)
and reports the selected/current versions. It never builds, signs or uploads.
The default output is a Markdown table suitable for a GitHub step summary.
USAGE
}

json=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) json=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

require_tools jq
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
channels=(stable testing mainline)
failed=0
results=()

for channel in "${channels[@]}"; do
    set +e
    "$SCRIPT_DIR/check-upstream.sh" --channel "$channel" --json > "$tmp/$channel.json" 2> "$tmp/$channel.err"
    rc=$?
    set -e
    if (( rc != 0 && rc != 10 )); then
        warn "$channel check failed (exit $rc): $(tr '\n' ' ' < "$tmp/$channel.err")"
        failed=1
        continue
    fi
    results+=("$tmp/$channel.json")
done

if (( ${#results[@]} == 0 )); then
    exit 2
fi

if (( json )); then
    jq -s '.' "${results[@]}"
else
    printf '| channel | selected | current | status |\n'
    printf '|---|---|---|---|\n'
    jq -r '"| \(.channel) | \(.selected) | \(.current // "none") | \(.status) |"' "${results[@]}"
fi

(( failed == 0 )) || exit 2
