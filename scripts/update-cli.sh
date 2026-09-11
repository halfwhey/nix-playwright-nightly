#!/usr/bin/env bash
# Usage: ./scripts/update-cli.sh [version]
#
# Add @playwright/cli@<version> (default: latest on npm) to pins/cli/. Resolves
# the matching playwright-core alpha, fetches its browsers.json, prefetches all
# browser archive hashes for every supported system, writes the per-version pin
# file, updates pins/pin.json (the manifest), builds the versioned attr, and
# commits.

set -euo pipefail

TOOL="cli"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TOOL FLAKE_ROOT
# shellcheck source=scripts/lib.sh
. "${FLAKE_ROOT}/scripts/lib.sh"

require_cmd curl jq nix git

log "resolving upstream latest @playwright/cli from npm"
upstream_latest=$(curl -fsSL "https://registry.npmjs.org/@playwright/cli" |
  jq -r '.["dist-tags"].latest')
if [ -z "$upstream_latest" ] || [ "$upstream_latest" = "null" ]; then
  die "could not resolve upstream latest for @playwright/cli"
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

log "resolving @playwright/cli@${package_version} -> playwright-core version"
cli_meta=$(curl -fsSL "https://registry.npmjs.org/@playwright/cli/${package_version}")
playwright_version=$(printf '%s' "$cli_meta" |
  jq -r '.dependencies.playwright // .dependencies["playwright-core"] // empty')
if [ -z "$playwright_version" ]; then
  die "could not resolve dependencies.playwright for @playwright/cli@${package_version}"
fi
log "playwright-core version: $playwright_version"

package_sha=$(resolve_npm_source_sha "$cli_meta" "playwright-cli")
log "playwright-cli SHA: $package_sha"

log "fetching browsers.json from playwright-core@${playwright_version}"
browsers_json=$(fetch_npm_browsers_json "$playwright_version")

pkg_hashes=$(emit_npm_pkg_hashes "playwright-cli" "$package_sha")
browsers_obj=$(parse_browsers_json "$browsers_json" | emit_browsers_obj)

jq -n \
  --arg package "$package_version" \
  --arg packageSha "$package_sha" \
  --arg playwrightVersion "$playwright_version" \
  --argjson pkg_hashes "$pkg_hashes" \
  --argjson browsers "$browsers_obj" \
  '{ package: $package, packageSha: $packageSha, playwrightVersion: $playwrightVersion }
   + $pkg_hashes
   + { browsers: $browsers }' |
  write_pin_file "$package_version"

update_manifest "$package_version" "$is_latest"

finalize "$package_version"
