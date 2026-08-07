#!/usr/bin/env bash
# Usage: ./scripts/update-node.sh [version]
#
# Add playwright@<version> (default: latest on npm) to pins/node/. Resolves the
# matching microsoft/playwright commit SHA, fetches browsers.json from that same
# commit, prefetches all browser archive hashes for every supported system,
# writes the per-version pin file, updates pins/pin.json, builds the versioned
# attr, and commits.

set -euo pipefail

TOOL="node"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TOOL FLAKE_ROOT
# shellcheck source=scripts/lib.sh
. "${FLAKE_ROOT}/scripts/lib.sh"

require_cmd curl jq nix git

log "resolving upstream latest playwright from npm"
upstream_latest=$(curl -fsSL "https://registry.npmjs.org/playwright" |
  jq -r '.["dist-tags"].latest')
if [ -z "$upstream_latest" ] || [ "$upstream_latest" = "null" ]; then
  die "could not resolve upstream latest for playwright"
fi
log "upstream latest: $upstream_latest"

package_version="${1:-$upstream_latest}"
log "target package version: $package_version"

is_latest=0
[ "$package_version" = "$upstream_latest" ] && is_latest=1

if has_pin_for "$package_version"; then
  log "already have pin for $package_version; nothing to do"
  exit 0
fi

log "resolving playwright@${package_version} -> playwright-core version + gitHead"
node_meta=$(curl -fsSL "https://registry.npmjs.org/playwright/${package_version}")
playwright_version=$(printf '%s' "$node_meta" |
  jq -r '.dependencies["playwright-core"] // empty')
if [ -z "$playwright_version" ]; then
  die "could not resolve dependencies.playwright-core for playwright@${package_version}"
fi
log "playwright-core version: $playwright_version"

package_sha=$(printf '%s' "$node_meta" | jq -r '.gitHead // empty')
if [ -z "$package_sha" ]; then
  die "could not resolve gitHead for playwright@${package_version}"
fi
log "playwright SHA: $package_sha"

package_tarball=$(printf '%s' "$node_meta" | jq -r '.dist.tarball // empty')
if [ -z "$package_tarball" ]; then
  die "could not resolve dist.tarball for playwright@${package_version}"
fi
log "prefetching playwright@${package_version} tarball hash"
package_hash=$(prefetch_fetchzip_hash "$package_tarball" "true")

core_meta=$(curl -fsSL "https://registry.npmjs.org/playwright-core/${playwright_version}")
playwright_sha=$(printf '%s' "$core_meta" | jq -r '.gitHead // empty')
if [ -z "$playwright_sha" ]; then
  die "could not resolve gitHead for playwright-core@${playwright_version}"
fi
core_tarball=$(printf '%s' "$core_meta" | jq -r '.dist.tarball // empty')
if [ -z "$core_tarball" ]; then
  die "could not resolve dist.tarball for playwright-core@${playwright_version}"
fi
log "prefetching playwright-core@${playwright_version} tarball hash"
core_hash=$(prefetch_fetchzip_hash "$core_tarball" "true")

log "fetching browsers.json at ${playwright_sha}"
browsers_json=$(fetch_browsers_json "$playwright_sha")

browsers_obj=$(parse_browsers_json "$browsers_json" | emit_browsers_obj)

jq -n \
  --arg package "$package_version" \
  --arg packageSha "$package_sha" \
  --arg playwrightVersion "$playwright_version" \
  --arg playwrightSha "$playwright_sha" \
  --arg packageHash "$package_hash" \
  --arg coreHash "$core_hash" \
  --argjson browsers "$browsers_obj" \
  '{
     package: $package,
     packageSha: $packageSha,
     playwrightVersion: $playwrightVersion,
     playwrightSha: $playwrightSha,
     packageHash: $packageHash,
     coreHash: $coreHash,
     browsers: $browsers
   }' |
  write_pin_file "$package_version"

update_manifest "$package_version" "$is_latest"

finalize "$package_version"
