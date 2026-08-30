#!/usr/bin/env bash
# Usage: ./scripts/push-latest-browsers.sh [--dry-run] <cache-name> [keep-revisions] [tool...]
#
# Reconcile selected latest browser outputs with their Cachix pins. Outputs
# already pinned to the current store path are skipped; missing, stale, or
# unknown pins are built, pushed, and pinned. Set FORCE=1 to bypass comparison.

set -euo pipefail

log() { printf '[cachix:latest-browsers] %s\n' "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/push-latest-browsers.sh [--dry-run] <cache-name> [keep-revisions] [tool...]

Tools default to: cli dotnet mcp node python
Set FORCE=1 to push every selected tool without comparing Cachix pins.
Set CACHIX_API_URL to override the public pin-list endpoint.
EOF
}

DRY_RUN=0
POSITIONAL=()
while [ "$#" -gt 0 ]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    POSITIONAL+=("$@")
    break
    ;;
  -*)
    die "unknown option '$1'"
    ;;
  *)
    POSITIONAL+=("$1")
    ;;
  esac
  shift
done
set -- "${POSITIONAL[@]}"

if [ "$#" -eq 0 ]; then
  usage
  die "cache name required"
fi

CACHE_NAME="$1"
shift
KEEP_REVISIONS=1
if [ "$#" -gt 0 ]; then
  case "$1" in
  '' | *[!0-9]*)
    ;;
  *)
    KEEP_REVISIONS="$1"
    shift
    ;;
  esac
fi

FORCE="${FORCE:-0}"
case "$FORCE" in
0 | 1) ;;
*) die "FORCE must be 0 or 1, got '$FORCE'" ;;
esac

command -v nix >/dev/null 2>&1 || die "missing required command: nix"
command -v curl >/dev/null 2>&1 || die "missing required command: curl"
command -v jq >/dev/null 2>&1 || die "missing required command: jq"
if [ "$DRY_RUN" -eq 0 ]; then
  command -v cachix >/dev/null 2>&1 || die "missing required command: cachix"
fi

FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"
CACHIX_API_URL="${CACHIX_API_URL:-https://app.cachix.org/api/v1/cache/${CACHE_NAME}/pin}"
PIN_API_STATE="unknown"
PIN_API_REASON="comparison bypassed"
PIN_API_RESPONSE=""

cd "$FLAKE_ROOT"

load_pin_state() {
  log "fetching Cachix pins from ${CACHIX_API_URL}"
  if ! PIN_API_RESPONSE=$(curl --silent --show-error --location --fail-with-body "$CACHIX_API_URL"); then
    PIN_API_REASON="request failed for ${CACHIX_API_URL}"
    log "Cachix pin state is unknown: ${PIN_API_REASON}"
    return
  fi

  if ! printf '%s' "$PIN_API_RESPONSE" | jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and (.name | type == "string")
      and (.lastRevision | type == "object")
      and (.lastRevision.storePath | type == "string")
    )
    and (([.[].name] | length) == ([.[].name] | unique | length))
  ' >/dev/null; then
    PIN_API_REASON="malformed response from ${CACHIX_API_URL}"
    log "Cachix pin state is unknown: ${PIN_API_REASON}"
    return
  fi

  PIN_API_STATE="known"
  PIN_API_REASON=""
}

push_and_pin() {
  local pin_name="$1" attr="$2" expected_path="$3" path
  log "building ${attr}"
  path=$(nix build --no-link --print-out-paths "$attr")
  if [ "$path" != "$expected_path" ]; then
    die "${attr} evaluated to ${expected_path} but built as ${path}"
  fi
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

reconcile_tool() {
  local pin_name="$1" attr="$2" current_path pinned_path=""
  log "evaluating ${attr}.outPath"
  current_path=$(nix eval --raw "${attr}.outPath")

  if [ "$FORCE" -eq 1 ]; then
    log "${pin_name}: force enabled -> push (${current_path})"
  elif [ "$PIN_API_STATE" != "known" ]; then
    log "${pin_name}: cache state unknown (${PIN_API_REASON}) -> push"
  else
    pinned_path=$(printf '%s' "$PIN_API_RESPONSE" | jq -r --arg name "$pin_name" '
      [.[] | select(.name == $name) | .lastRevision.storePath]
      | if length == 0 then "" else .[0] end
    ')
    if [ -z "$pinned_path" ]; then
      log "${pin_name}: pin missing -> push (${current_path})"
    elif [ "$pinned_path" = "$current_path" ]; then
      log "${pin_name}: already pinned, skipping (${current_path})"
      return
    else
      log "${pin_name}: stale (${pinned_path} != ${current_path}) -> push"
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "${pin_name}: dry-run, no build/push/pin performed"
    return
  fi
  push_and_pin "$pin_name" "$attr" "$current_path"
}

if [ "$#" -eq 0 ]; then
  set -- cli dotnet mcp node python
fi

if [ "$FORCE" -eq 0 ]; then
  load_pin_state
else
  log "FORCE=1; bypassing Cachix pin comparison"
fi

for tool in "$@"; do
  resolve_tool "$tool"
  reconcile_tool "$RESOLVED_PIN_NAME" "$RESOLVED_ATTR"
done
