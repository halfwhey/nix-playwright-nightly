#!/usr/bin/env bash
# Usage: ./scripts/update-dotnet.sh [version]
#
# Add Microsoft.Playwright <version> (default: latest stable on NuGet) to
# pins/dotnet/. The published NuGet package already bundles the Playwright JS
# driver payload, so we extract browsers.json directly from the .nupkg.

set -euo pipefail

TOOL="dotnet"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TOOL FLAKE_ROOT
# shellcheck source=scripts/lib.sh
. "${FLAKE_ROOT}/scripts/lib.sh"

require_cmd curl jq nix git unzip

log "resolving upstream latest Microsoft.Playwright from NuGet"
upstream_latest=$(curl -fsSL "https://api.nuget.org/v3-flatcontainer/microsoft.playwright/index.json" \
  | jq -r '.versions | map(select(contains("-") | not)) | last // empty')
if [ -z "$upstream_latest" ]; then
  die "could not resolve upstream latest for Microsoft.Playwright"
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

package_url="https://api.nuget.org/v3-flatcontainer/microsoft.playwright/${package_version}/microsoft.playwright.${package_version}.nupkg"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

log "fetching ${package_url}"
curl -fsSL "$package_url" -o "$tmpdir/package.nupkg"

log "extracting embedded browsers.json"
browsers_json=$(unzip -p "$tmpdir/package.nupkg" .playwright/package/browsers.json)
if [ -z "$browsers_json" ]; then
  die "could not extract .playwright/package/browsers.json from Microsoft.Playwright ${package_version}"
fi

log "prefetching unpacked .nupkg hash"
package_hash=$(prefetch_fetchzip_hash "$package_url" "false")

browsers_obj=$(parse_browsers_json "$browsers_json" | emit_browsers_obj)

jq -n \
  --arg package "$package_version" \
  --arg packageHash "$package_hash" \
  --argjson browsers "$browsers_obj" \
  '{ package: $package, packageHash: $packageHash, browsers: $browsers }' \
| write_pin_file "$package_version"

update_manifest "$package_version" "$is_latest"

finalize "$package_version"
