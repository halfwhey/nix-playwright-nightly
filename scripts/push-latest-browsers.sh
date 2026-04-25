#!/usr/bin/env bash
# Usage: ./scripts/push-latest-browsers.sh <cache-name> [keep-revisions] [tool...]
#        ./scripts/push-latest-browsers.sh <cache-name> [tool...]
#
# Build selected latest browser outputs, push their runtime closures
# to Cachix, and pin each latest alias so only the newest revision stays pinned.

set -euo pipefail

CACHE_NAME="${1:?cache name required}"
shift
KEEP_REVISIONS=1
if [ "$#" -gt 0 ]; then
  case "$1" in
    ''|*[!0-9]*)
      ;;
    *)
      KEEP_REVISIONS="$1"
      shift
      ;;
  esac
fi
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
    cli)
      RESOLVED_PIN_NAME="playwright-cli-browsers-${SYSTEM}"
      RESOLVED_ATTR=".#playwright-cli-browsers"
      ;;
    dotnet)
      RESOLVED_PIN_NAME="playwright-dotnet-browsers-${SYSTEM}"
      RESOLVED_ATTR=".#playwright-dotnet-browsers"
      ;;
    mcp)
      RESOLVED_PIN_NAME="playwright-mcp-browsers-${SYSTEM}"
      RESOLVED_ATTR=".#playwright-mcp-browsers"
      ;;
    node)
      RESOLVED_PIN_NAME="playwright-node-browsers-${SYSTEM}"
      RESOLVED_ATTR=".#playwright-node-browsers"
      ;;
    python)
      RESOLVED_PIN_NAME="playwright-python-browsers-${SYSTEM}"
      RESOLVED_ATTR=".#playwright-python-browsers"
      ;;
    camoufox)
      RESOLVED_PIN_NAME="camoufox-browsers-${SYSTEM}"
      RESOLVED_ATTR=".#camoufox-browsers"
      ;;
    *) die "unknown tool '$1' (expected cli|dotnet|mcp|node|python|camoufox)" ;;
  esac
}

if [ "$#" -eq 0 ]; then
  set -- cli dotnet mcp node python
fi

for tool in "$@"; do
  resolve_tool "$tool"
  push_and_pin "$RESOLVED_PIN_NAME" "$RESOLVED_ATTR"
done
