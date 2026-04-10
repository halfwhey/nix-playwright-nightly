#!/usr/bin/env bash
# Usage: ./scripts/push-latest-browsers.sh <cache-name> [keep-revisions]
#
# Build the latest browser link-farm outputs, push their runtime closures to
# Cachix, and pin each latest alias so only the newest revision stays pinned.

set -euo pipefail

CACHE_NAME="${1:?cache name required}"
KEEP_REVISIONS="${2:-1}"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
  printf '%s\n' "$path" | cachix push "$CACHE_NAME"
  log "pinning ${pin_name} -> ${path}"
  cachix pin "$CACHE_NAME" "$pin_name" "$path" --keep-revisions "$KEEP_REVISIONS"
}

push_and_pin "playwright-cli-browsers" ".#playwright-cli-browsers"
push_and_pin "playwright-mcp-browsers" ".#playwright-mcp-browsers"
push_and_pin "playwright-python-browsers" ".#playwright-python-browsers"
