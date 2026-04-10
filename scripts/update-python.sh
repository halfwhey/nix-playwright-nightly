#!/usr/bin/env bash
# Usage: ./scripts/update-python.sh [version]
#
# Add PyPI playwright==<version> (default: latest on PyPI) to pins/python/.
# PyPI's playwright lives in microsoft/playwright-python and hardcodes a
# driver_version in setup.py; we use that to resolve the matching
# microsoft/playwright SHA and then its browsers.json.

set -euo pipefail

TOOL="python"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export TOOL FLAKE_ROOT
# shellcheck source=scripts/lib.sh
. "${FLAKE_ROOT}/scripts/lib.sh"

require_cmd curl jq nix git

log "resolving upstream latest playwright from PyPI"
upstream_latest=$(curl -fsSL "https://pypi.org/pypi/playwright/json" \
  | jq -r '.info.version')
if [ -z "$upstream_latest" ] || [ "$upstream_latest" = "null" ]; then
  die "could not resolve upstream latest for PyPI playwright"
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

log "resolving playwright-python v${package_version} -> driver_version"
# Buffer curl output before awk so awk's early exit doesn't SIGPIPE curl,
# which would trip set -o pipefail.
setup_py=$(curl -fsSL "https://raw.githubusercontent.com/microsoft/playwright-python/v${package_version}/setup.py")
driver_version=$(printf '%s\n' "$setup_py" | awk -F'"' '/^driver_version[[:space:]]*=/ {print $2; exit}')
if [ -z "$driver_version" ]; then
  die "could not parse driver_version from playwright-python v${package_version} setup.py"
fi
log "playwright-core (driver) version: $driver_version"

log "resolving playwright@${driver_version} -> gitHead SHA via npm"
# npm's `playwright` package has the same SHA we need, regardless of whether
# the driver is stable, alpha, beta, or next.
playwright_sha=$(curl -fsSL "https://registry.npmjs.org/playwright/${driver_version}" \
  | jq -r '.gitHead // empty')
if [ -z "$playwright_sha" ]; then
  die "could not resolve gitHead for playwright@${driver_version}"
fi
log "playwright-core SHA: $playwright_sha"

log "fetching browsers.json at ${playwright_sha}"
browsers_json=$(fetch_browsers_json "$playwright_sha")

pkg_hashes=$(emit_python_pkg_hashes "$package_version")
browsers_obj=$(parse_browsers_json "$browsers_json" | emit_browsers_obj)

jq -n \
  --arg package "$package_version" \
  --arg playwrightVersion "$driver_version" \
  --arg playwrightSha "$playwright_sha" \
  --argjson pkg_hashes "$pkg_hashes" \
  --argjson browsers "$browsers_obj" \
  '{ package: $package, playwrightVersion: $playwrightVersion, playwrightSha: $playwrightSha }
   + $pkg_hashes
   + { browsers: $browsers }' \
| write_pin_file "$package_version"

update_manifest "$package_version" "$is_latest"

finalize "$package_version"
