#!/usr/bin/env bash
# Offline regression tests for npm releases published without gitHead.
set -euo pipefail
export TOOL=test
FLAKE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export FLAKE_ROOT UPDATE_SCRIPT_NIX_SHELL_READY=1
# shellcheck source=../lib.sh
. "${FLAKE_ROOT}/scripts/lib.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
sha=1111111111111111111111111111111111111111
tag_sha=2222222222222222222222222222222222222222
meta='{"name":"@playwright/cli","version":"0.1.19","dependencies":{"playwright":"1.63.0-alpha-2026-08-31"}}'
mock_source_meta="$meta"
mock_refs="$(printf '%s\trefs/tags/v0.1.19' "$sha")"

# Stub external boundaries; run the actual resolver and validation logic.
git() { printf '%s\n' "$mock_refs"; }
curl() {
  case "${*: -1}" in
  https://raw.githubusercontent.com/*) printf '%s' "$mock_source_meta" ;;
  https://registry.npmjs.org/playwright-core/*)
    printf '{"dist":{"tarball":"https://registry.npmjs.org/core.tgz"}}'
    ;;
  *) return 1 ;;
  esac
}
nix() { jq -n --arg path "$test_tmp" '{storePath: $path}'; }

expect_failure() {
  if ("$@") >"$test_tmp/output" 2>&1; then
    printf 'Expected failure: %s\n' "$*" >&2
    exit 1
  fi
}

# Existing untagged releases still use gitHead without querying tags.
mock_refs=''
with_head=$(printf '%s' "$meta" | jq --arg sha "$sha" '. + {gitHead: $sha}')
[ "$(resolve_npm_source_sha "$with_head" playwright-cli)" = "$sha" ]
# Missing gitHead falls back to a lightweight tag.
mock_refs="$(printf '%s\trefs/tags/v0.1.19' "$sha")"
[ "$(resolve_npm_source_sha "$meta" playwright-cli)" = "$sha" ]
# Annotated tags must pin the peeled commit, not the tag object.
mock_refs="$(printf '%s\trefs/tags/v0.1.19\n%s\trefs/tags/v0.1.19^{}' "$tag_sha" "$sha")"
[ "$(resolve_npm_source_sha "$meta" playwright-cli)" = "$sha" ]
mock_refs=''
expect_failure resolve_npm_source_sha "$meta" playwright-cli
expect_failure resolve_npm_source_sha "$(printf '%s' "$meta" | jq '.gitHead = "bad"')" playwright-cli
mock_source_meta=$(printf '%s' "$meta" | jq '.version = "0.1.18"')
expect_failure resolve_npm_source_sha "$with_head" playwright-cli
mock_source_meta=$(printf '%s' "$meta" | jq '.dependencies.playwright = "1.62.0"')
expect_failure resolve_npm_source_sha "$with_head" playwright-cli

# An alpha needs neither gitHead nor a tag to supply its browser manifest.
version=1.63.0-alpha-2026-08-31
jq -n --arg version "$version" '{name: "playwright-core", version: $version}' >"$test_tmp/package.json"
printf '{"browsers":[{"name":"chromium","revision":"1243"}]}' >"$test_tmp/browsers.json"
[ "$(fetch_npm_browsers_json "$version" | jq -r '.browsers[0].revision')" = 1243 ]
expect_failure fetch_npm_browsers_json 1.62.0
printf '{"browsers":[]}' >"$test_tmp/browsers.json"
expect_failure fetch_npm_browsers_json "$version"
printf 'invalid json' >"$test_tmp/browsers.json"
expect_failure fetch_npm_browsers_json "$version"
printf 'npm resolution regression tests passed\n'
