#!/usr/bin/env bash
# Usage: ./scripts/backfill.sh <cli|mcp|node|python>
#
# Enumerate every version published for <tool>, diff against pins/pin.json
# (the .versions array under the tool's key), and run scripts/update-<tool>.sh for each
# missing version in chronological (publish-time) order. The update script
# itself handles commit. On any failure, exit non-zero immediately so CI
# fails loudly and a human investigates before more versions pile up.

set -euo pipefail

TOOL="${1:?tool argument required: cli|mcp|node|python}"
FLAKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FLAKE_ROOT"

log() { printf '[backfill:%s] %s\n' "$TOOL" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

case "$TOOL" in
  cli|mcp)
    pkg_name="@playwright/${TOOL}"
    log "fetching npm registry metadata for ${pkg_name}"
    meta=$(curl -fsSL "https://registry.npmjs.org/${pkg_name}")
    # jq: pair each version with its publish time, drop dist-tag aliases,
    # sort by time ascending. Emits <version><TAB><time> per line.
    all_versions=$(printf '%s' "$meta" | jq -r '
      .versions as $v
      | .time
      | to_entries
      | map(select(.key as $k | $v | has($k)))
      | sort_by(.value)
      | .[] | "\(.key)\t\(.value)"
    ')
    ;;
  node)
    pkg_name="playwright"
    log "fetching npm registry metadata for ${pkg_name}"
    meta=$(curl -fsSL "https://registry.npmjs.org/${pkg_name}")
    all_versions=$(printf '%s' "$meta" | jq -r '
      .versions as $v
      | .time
      | to_entries
      | map(select(.key as $k | $v | has($k)))
      | sort_by(.value)
      | .[] | "\(.key)\t\(.value)"
    ')
    ;;
  python)
    log "fetching PyPI metadata for playwright"
    meta=$(curl -fsSL "https://pypi.org/pypi/playwright/json")
    all_versions=$(printf '%s' "$meta" | jq -r '
      .releases
      | to_entries
      | map(select(.value | length > 0))
      | map({version: .key, time: .value[0].upload_time})
      | sort_by(.time)
      | .[] | "\(.version)\t\(.time)"
    ')
    ;;
  *)
    die "unknown tool: $TOOL (expected cli|mcp|node|python)"
    ;;
esac

if [ -z "$all_versions" ]; then
  die "no versions returned from registry"
fi

log "reading existing versions from pins/pin.json"
manifest_file="${FLAKE_ROOT}/pins/pin.json"
existing=""
if [ -f "$manifest_file" ]; then
  existing=$(jq -r --arg tool "$TOOL" '.[$tool].versions[]? // empty' "$manifest_file")
fi

if [ -z "$existing" ]; then
  die "no existing ${TOOL} pins in pins/pin.json — refusing to backfill from scratch. Seed the repo manually with at least one version before running the sync workflow."
fi

# Find the publish time of the newest version we already have (the
# watermark). Only consider registry versions published strictly AFTER
# the watermark as missing — we never reach backward to pick up older
# versions that were published before our initial seed.
watermark=$(printf '%s\n' "$all_versions" | awk -F'\t' -v ex="$existing" '
  BEGIN {
    n = split(ex, a, "\n")
    for (i = 1; i <= n; i++) seen[a[i]] = 1
  }
  { if (seen[$1] && $2 > max) max = $2 }
  END { print max }
')

if [ -z "$watermark" ]; then
  die "could not find any of the existing ${TOOL} pins in the registry (registry lost our versions?)"
fi
log "watermark: newest existing ${TOOL} pin was published at ${watermark}"

# Compute missing = versions published after the watermark and not
# already in `existing`. Preserve chronological order from `all_versions`.
missing=$(printf '%s\n' "$all_versions" | awk -F'\t' -v ex="$existing" -v wm="$watermark" '
  BEGIN {
    n = split(ex, a, "\n")
    for (i = 1; i <= n; i++) seen[a[i]] = 1
  }
  { if ($2 > wm && !seen[$1]) print $1 }
')

if [ -z "$missing" ]; then
  log "no missing versions, up to date"
  exit 0
fi

missing_count=$(printf '%s\n' "$missing" | grep -c . || true)
log "$missing_count missing version(s) to backfill"
printf '%s\n' "$missing" | sed 's/^/  - /' >&2

while IFS= read -r version; do
  [ -z "$version" ] && continue
  log "running scripts/update-${TOOL}.sh $version"
  "${FLAKE_ROOT}/scripts/update-${TOOL}.sh" "$version"
done <<< "$missing"

log "backfill complete for ${TOOL}"
