#!/usr/bin/env bash
# Usage: ./scripts/update-camoufox.sh [version]
#
# Add PyPI camoufox <version> (default: latest PyPI release) to
# pins/camoufox/. Prefetches the sdist hash, writes the pin file,
# updates pins/pin.json, builds the versioned camoufox attr, and commits.

set -euo pipefail

TOOL="camoufox"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TOOL FLAKE_ROOT
# shellcheck source=scripts/lib.sh
. "${FLAKE_ROOT}/scripts/lib.sh"

require_cmd curl jq nix git

PYPI_NAME="camoufox"

fetch_pypi_json() {
  local version="${1:-}"
  if [ -z "$version" ]; then
    curl -fsSL "https://pypi.org/pypi/${PYPI_NAME}/json"
  else
    curl -fsSL "https://pypi.org/pypi/${PYPI_NAME}/${version}/json"
  fi
}

prefetch_file_hash() {
  local url="$1"
  local out
  out=$(nix store prefetch-file --json --hash-type sha256 "$url") ||
    die "prefetch failed for $url"
  printf '%s' "$out" | jq -r '.hash'
}

log "resolving upstream latest ${PYPI_NAME} release from PyPI"
latest_json=$(fetch_pypi_json)
upstream_latest=$(printf '%s' "$latest_json" | jq -r '.info.version')
if [ -z "$upstream_latest" ] || [ "$upstream_latest" = "null" ]; then
  die "could not resolve upstream latest for ${PYPI_NAME}"
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

package_json="$latest_json"
if [ "$package_version" != "$upstream_latest" ]; then
  package_json=$(fetch_pypi_json "$package_version")
fi

sdist_url=$(printf '%s' "$package_json" |
  jq -r '.urls[] | select(.packagetype == "sdist") | .url' |
  head -n1)
if [ -z "$sdist_url" ]; then
  die "could not find sdist for ${PYPI_NAME} ${package_version}"
fi

log "prefetching ${PYPI_NAME} ${package_version} sdist"
hash=$(prefetch_file_hash "$sdist_url")

jq -n \
  --arg package "$package_version" \
  --arg pypi "$PYPI_NAME" \
  --arg url "$sdist_url" \
  --arg hash "$hash" \
  '{ package: $package, pypi: $pypi, url: $url, hash: $hash }' |
  write_pin_file "$package_version"

update_manifest "$package_version" "$is_latest"

attr_version="${package_version//./_}"
(
  cd "$FLAKE_ROOT"
  git add "pins/${TOOL}/${package_version}.json" "pins/pin.json"
)
current_system=$(nix eval --raw --impure --expr builtins.currentSystem)
if [ "$current_system" = "aarch64-linux" ]; then
  log "building .#camoufox-${attr_version}"
  (cd "$FLAKE_ROOT" && nix build --no-link ".#camoufox-${attr_version}")
else
  log "skipping local build on unsupported system ${current_system}; aarch64-linux cache job will build it"
fi
log "commit"
(
  cd "$FLAKE_ROOT"
  if git diff --cached --quiet; then
    log "no changes to commit"
    exit 0
  fi
  git commit -m "camoufox: add python ${package_version}"
)
log "done. added camoufox-${package_version}"
