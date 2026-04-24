#!/usr/bin/env bash
# Usage: ./scripts/update-camoufox.sh [version]
#
# Add Camoufox <version> (default: latest daijro/camoufox GitHub release) to
# pins/camoufox/. Prefetches supported browser archive hashes, writes the pin
# file, updates pins/pin.json, builds the versioned attr, and commits.

set -euo pipefail

TOOL="camoufox"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TOOL FLAKE_ROOT
# shellcheck source=scripts/lib.sh
. "${FLAKE_ROOT}/scripts/lib.sh"

require_cmd curl jq nix git

SUPPORTED_CAMOUFOX_SYSTEMS=(aarch64-linux)

asset_suffix_for_system() {
  case "$1" in
    aarch64-linux) printf 'lin.arm64' ;;
    *) die "unsupported Camoufox system '$1'" ;;
  esac
}

fetch_release_json() {
  local version="${1:-}"
  if [ -z "$version" ]; then
    curl -fsSL "https://api.github.com/repos/daijro/camoufox/releases/latest"
  else
    curl -fsSL "https://api.github.com/repos/daijro/camoufox/releases/tags/v${version}"
  fi
}

log "resolving upstream latest Camoufox release from GitHub"
latest_json=$(fetch_release_json)
upstream_latest=$(printf '%s' "$latest_json" | jq -r '.tag_name | sub("^v"; "")')
if [ -z "$upstream_latest" ] || [ "$upstream_latest" = "null" ]; then
  die "could not resolve upstream latest for Camoufox"
fi
log "upstream latest: $upstream_latest"

package_version="${1:-$upstream_latest}"
package_version="${package_version#v}"
log "target package version: $package_version"

is_latest=0
[ "$package_version" = "$upstream_latest" ] && is_latest=1

if has_pin_for "$package_version"; then
  log "already have pin for $package_version; nothing to do"
  exit 0
fi

release_json="$latest_json"
if [ "$package_version" != "$upstream_latest" ]; then
  release_json=$(fetch_release_json "$package_version")
fi

tag=$(printf '%s' "$release_json" | jq -r '.tag_name // empty')
if [ -z "$tag" ]; then
  die "could not resolve release tag for Camoufox $package_version"
fi

sources_obj='{}'
for sys in "${SUPPORTED_CAMOUFOX_SYSTEMS[@]}"; do
  suffix=$(asset_suffix_for_system "$sys")
  asset_name="camoufox-${package_version}-${suffix}.zip"
  url=$(printf '%s' "$release_json" \
    | jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' \
    | head -n1)
  if [ -z "$url" ]; then
    die "could not find release asset ${asset_name}"
  fi

  log "prefetching Camoufox ${package_version} for ${sys}"
  hash=$(prefetch_fetchzip_hash "$url" "false")
  sources_obj=$(printf '%s' "$sources_obj" \
    | jq --arg sys "$sys" --arg suffix "$suffix" --arg url "$url" --arg hash "$hash" \
      '. + { ($sys): { suffix: $suffix, url: $url, hash: $hash } }')
done

jq -n \
  --arg package "$package_version" \
  --arg tag "$tag" \
  --argjson sources "$sources_obj" \
  '{ package: $package, tag: $tag, sources: $sources }' \
| write_pin_file "$package_version"

update_manifest "$package_version" "$is_latest"

attr_version="${package_version//./_}"
(
  cd "$FLAKE_ROOT"
  git add "pins/${TOOL}/${package_version}.json" "pins/pin.json"
)
log "building .#camoufox-${attr_version}"
(cd "$FLAKE_ROOT" && nix build --no-link ".#camoufox-${attr_version}")
log "commit"
(
  cd "$FLAKE_ROOT"
  if git diff --cached --quiet; then
    log "no changes to commit"
    exit 0
  fi
  git commit -m "camoufox: add ${package_version}"
)
log "done. added camoufox-${package_version}"
