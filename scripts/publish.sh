#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2153
# Publish a built package set as the signed variant SourceForge repo.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: publish.sh [options]

Options:
  --channel stable|testing|mainline
                  Variant to publish (default: config CHANNEL)
  --from DIR      Directory containing the built packages
                  (default: out/<pkgbase>/<channel>/)
  --dry-run       Show the plan without creating/uploading anything
  --yes           Confirm publication; without it the script only reports
  -h, --help      This help

Publication creates a signed [x-kernel] or [x-kernel-mainline] repo, uploads
packages/DB/signatures to SourceForge, removes old package files and verifies
the public bytes. Stable and mainline repositories are isolated.
EOF
}

channel="$CHANNEL"
from=""
yes=0
dry_run=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) [[ $# -ge 2 ]] || die "--channel needs a value"; channel="$2"; shift 2 ;;
        --stable) channel=stable; shift ;;
        --testing) channel=testing; shift ;;
        --mainline) channel=mainline; shift ;;
        --from) [[ $# -ge 2 ]] || die "--from needs a value"; from="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        --yes) yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

configure_variant "$channel"
[[ "$channel" == testing ]] && die "testing is a local preview and is not published"
from="${from:-$(build_outdir "$channel")}"
from="$(expand_path "$from")"
[[ -d "$from" ]] || die "package directory not found: $from"

mapfile -t packages < <(
    find "$from" -maxdepth 1 -type f -name "$PKGBASE-*.pkg.tar.zst" -printf '%f\n' 2>/dev/null | sort
)
(( ${#packages[@]} > 0 )) || die "no $PKGBASE packages in $from"
has_main=0
has_headers=0
for pkg in "${packages[@]}"; do
    [[ "$pkg" == "$PKGBASE-headers-"* ]] && has_headers=1
    [[ "$pkg" == "$PKGBASE-"* && "$pkg" != "$PKGBASE-headers-"* && "$pkg" != "$PKGBASE-docs-"* ]] && has_main=1
    [[ -f "$from/$pkg.sig" ]] || die "missing signature for $pkg"
done
(( has_main )) || die "main $PKGBASE package is missing"
(( has_headers )) || die "$PKGBASE-headers package is missing"

if (( dry_run )); then
    log "dry-run: would build $REPO_NAME DB from $from and upload to $SF_USER@frs.sourceforge.net:$SF_PATH/$SF_ARCH"
    printf '  %s\n' "${packages[@]}" >&2
    exit 0
fi
if (( ! yes )); then
    log "publication not confirmed; package set:"
    printf '  %s\n' "${packages[@]}" >&2
    log "remote: $SF_USER@frs.sourceforge.net:$SF_PATH/$SF_ARCH"
    log "rerun with --yes to publish"
    exit 0
fi

tag="$(tr -d ' \n\r\t' < "$from/version" 2>/dev/null || true)"
if [[ -z "$tag" ]]; then
    main_pkg="$(printf '%s\n' "${packages[@]}" | grep -E "^${PKGBASE}-[0-9]" | head -1 || true)"
    [[ -n "$main_pkg" ]] || die "cannot determine the package version"
    tag="${main_pkg#"$PKGBASE"-}"
    tag="${tag%-"$ARCH".pkg.tar.zst}"
fi

require_tools rsync sftp gpg repo-add curl sha256sum jq
sf_ensure_key
load_signing_key

REPO_DIR="$REPODIR/$SF_ARCH"
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"
for pkg in "${packages[@]}"; do
    cp -f "$from/$pkg" "$from/$pkg.sig" "$REPO_DIR/"
done

log "generating signed $REPO_NAME database"
(
    cd "$REPO_DIR"
    repo-add -R -s -k "$X_REPO_SIGN_KEY" "$REPO_NAME.db.tar.gz" "${packages[@]}" >/dev/null
)
for ext in db files; do
    rm -f "$REPO_DIR/$REPO_NAME.$ext" "$REPO_DIR/$REPO_NAME.$ext.sig"
    cp -f "$REPO_DIR/$REPO_NAME.$ext.tar.gz" "$REPO_DIR/$REPO_NAME.$ext"
    cp -f "$REPO_DIR/$REPO_NAME.$ext.tar.gz.sig" "$REPO_DIR/$REPO_NAME.$ext.sig"
done

gpg --batch --export "$X_REPO_SIGN_KEY" > "$REPO_DIR/trustedkeys.gpg"
gpg --batch --armor --export "$X_REPO_SIGN_KEY" > "$REPO_DIR/signing.pub"
cat > "$REPO_DIR/README.md" <<EOF
# X Linux [$REPO_NAME]

Client configuration:

\`\`\`ini
[$REPO_NAME]
SigLevel = Required
Server = $SF_BASE_URL
\`\`\`

Install with the Arch kernel kept as fallback:

\`\`\`bash
sudo xpm install --needed $PKGBASE $PKGBASE-headers
\`\`\`
EOF

mapfile -t checksum_files < <(
    find "$REPO_DIR" -maxdepth 1 -type f \
        ! -name 'SHA256SUMS' ! -name 'SHA256SUMS.sig' -printf '%f\n' | sort
)
(
    cd "$REPO_DIR"
    sha256sum "${checksum_files[@]}" > SHA256SUMS
)
rm -f "$REPO_DIR/SHA256SUMS.sig"
sign_file "$REPO_DIR/SHA256SUMS"

# Create the FRS directory if it is missing; existing directories are fine.
printf 'mkdir %s\n' "$SF_PATH" | sftp_remote >/dev/null 2>&1 || true
printf 'mkdir %s/%s\n' "$SF_PATH" "$SF_ARCH" | sftp_remote >/dev/null 2>&1 || true

log "uploading to SourceForge (${#packages[@]} package(s))"
RSH=(ssh -i "$SF_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
rsync -e "${RSH[*]}" -h --partial "$REPO_DIR/" \
    "$SF_USER@frs.sourceforge.net:$SF_PATH/$SF_ARCH/"

log "removing old remote package versions"
mapfile -t local_files < <(find "$REPO_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)
mapfile -t remote_files < <(sf_list_remote)
stale=()
for name in "${remote_files[@]:-}"; do
    [[ -n "$name" ]] || continue
    if [[ "$name" =~ ^${PKGBASE}(-headers|-docs)?-[0-9].*\.pkg\.tar\.zst(\.sig)?$ ]]; then
        if ! printf '%s\n' "${local_files[@]}" | grep -qxF "$name"; then
            stale+=("$name")
        fi
    fi
done
if (( ${#stale[@]} > 0 )); then
    sf_delete_remote "${stale[@]}"
fi

log "verifying public bytes"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for file in "${local_files[@]}"; do
    for attempt in 1 2 3 4 5; do
        if curl -fsSL --max-time 300 -o "$tmp/$file" "$SF_BASE_URL/$file"; then
            break
        fi
        (( attempt == 5 )) && die "public download failed: $SF_BASE_URL/$file"
        sleep 10
    done
    cmp -s "$REPO_DIR/$file" "$tmp/$file" \
        || die "public file differs from local: $file"
done

log "published $PKGBASE $tag"
log "repo: [$REPO_NAME] $SF_BASE_URL"
