#!/usr/bin/env bash
# Usage: ./scripts/push-latest-browsers.sh <cache-name> [keep-revisions] [tool...]
#
# Build selected latest browser link-farm outputs, push their runtime closures
# to Cachix, and pin each latest alias so only the newest revision stays pinned.

set -euo pipefail

CACHE_NAME="${1:?cache name required}"
KEEP_REVISIONS="${2:-1}"
shift 2 || true
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"

log() { printf '[cachix:latest-browsers] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

command -v nix >/dev/null 2>&1 || die "missing required command: nix"
command -v cachix >/dev/null 2>&1 || die "missing required command: cachix"

cd "$FLAKE_ROOT"

push_and_pin() {
  local pin_name="$1" attr="$2" path
  log "building ${attr}"
  path=$(nix build --no-link --print-out-paths "$attr")
  log "pushing runtime closure for ${pin_name}"
  nix path-info -r "$path" | cachix push "$CACHE_NAME"
  log "pinning ${pin_name} -> ${path}"
  cachix pin "$CACHE_NAME" "$pin_name" "$path" --keep-revisions "$KEEP_REVISIONS"
}

resolve_tool() {
  case "$1" in
    cli) printf '%s\n%s\n' "playwright-cli-browsers-${SYSTEM}" ".#playwright-cli-browsers" ;;
    dotnet) printf '%s\n%s\n' "playwright-dotnet-browsers-${SYSTEM}" ".#playwright-dotnet-browsers" ;;
    mcp) printf '%s\n%s\n' "playwright-mcp-browsers-${SYSTEM}" ".#playwright-mcp-browsers" ;;
    node) printf '%s\n%s\n' "playwright-node-browsers-${SYSTEM}" ".#playwright-node-browsers" ;;
    python) printf '%s\n%s\n' "playwright-python-browsers-${SYSTEM}" ".#playwright-python-browsers" ;;
    *) die "unknown tool '$1' (expected cli|dotnet|mcp|node|python)" ;;
  esac
}

if [ "$#" -eq 0 ]; then
  set -- cli dotnet mcp node python
fi

for tool in "$@"; do
  mapfile -t resolved < <(resolve_tool "$tool")
  push_and_pin "${resolved[0]}" "${resolved[1]}"
done
