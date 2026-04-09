# Shared helpers sourced by update-cli.sh / update-mcp.sh / update-python.sh.
# Callers must set: TOOL (cli|mcp|python), FLAKE_ROOT (absolute path).

set -euo pipefail

: "${TOOL:?TOOL must be set by caller}"
: "${FLAKE_ROOT:?FLAKE_ROOT must be set by caller}"

PIN_DIR="${FLAKE_ROOT}/pins/${TOOL}"
MANIFEST_FILE="${FLAKE_ROOT}/pins/${TOOL}.json"
SUPPORTED_SYSTEMS=(x86_64-linux aarch64-linux)
DUMMY_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

log() { printf '[%s] %s\n' "${TOOL}" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

# Fetch browsers.json for a given microsoft/playwright commit SHA.
# Outputs raw JSON on stdout.
fetch_browsers_json() {
  local sha="$1"
  curl -fsSL "https://raw.githubusercontent.com/microsoft/playwright/${sha}/packages/playwright-core/browsers.json"
}

# Filter browsers.json down to the browsers we support. Echoes tab-separated
# rows: name<TAB>revision<TAB>browserVersion (browserVersion may be empty).
# Only emits browsers with installByDefault == true and that we have a fetcher
# for (chromium, chromium-headless-shell, firefox, webkit, ffmpeg).
parse_browsers_json() {
  local json="$1"
  printf '%s' "$json" | jq -r '
    .browsers[]
    | select(.installByDefault == true)
    | select(.name | IN("chromium","chromium-headless-shell","firefox","webkit","ffmpeg"))
    | [.name, .revision, (.browserVersion // "")]
    | @tsv
  '
}

# Compute the CDN URL for a given browser + revision + browserVersion on a
# given system. Mirrors the DOWNLOAD_PATHS table in playwright-core's
# registry for x86_64-linux (ubuntu24.04-x64) and aarch64-linux
# (ubuntu24.04-arm64), using ubuntu-22.04 firefox/webkit archives as the
# fetchers do.
browser_url() {
  local name="$1" revision="$2" browserVersion="$3" system="$4"
  case "$name" in
    chromium)
      case "$system" in
        x86_64-linux)  printf 'https://cdn.playwright.dev/builds/cft/%s/linux64/chrome-linux64.zip' "$browserVersion" ;;
        aarch64-linux) printf 'https://cdn.playwright.dev/builds/chromium/%s/chromium-linux-arm64.zip' "$revision" ;;
      esac
      ;;
    chromium-headless-shell)
      case "$system" in
        x86_64-linux)  printf 'https://cdn.playwright.dev/builds/cft/%s/linux64/chrome-headless-shell-linux64.zip' "$browserVersion" ;;
        aarch64-linux) printf 'https://cdn.playwright.dev/builds/chromium/%s/chromium-headless-shell-linux-arm64.zip' "$revision" ;;
      esac
      ;;
    firefox)
      case "$system" in
        x86_64-linux)  printf 'https://cdn.playwright.dev/builds/firefox/%s/firefox-ubuntu-22.04.zip' "$revision" ;;
        aarch64-linux) printf 'https://cdn.playwright.dev/builds/firefox/%s/firefox-ubuntu-22.04-arm64.zip' "$revision" ;;
      esac
      ;;
    webkit)
      case "$system" in
        x86_64-linux)  printf 'https://cdn.playwright.dev/builds/webkit/%s/webkit-ubuntu-22.04.zip' "$revision" ;;
        aarch64-linux) printf 'https://cdn.playwright.dev/builds/webkit/%s/webkit-ubuntu-22.04-arm64.zip' "$revision" ;;
      esac
      ;;
    ffmpeg)
      case "$system" in
        x86_64-linux)  printf 'https://cdn.playwright.dev/builds/ffmpeg/%s/ffmpeg-linux.zip' "$revision" ;;
        aarch64-linux) printf 'https://cdn.playwright.dev/builds/ffmpeg/%s/ffmpeg-linux-arm64.zip' "$revision" ;;
      esac
      ;;
    *)
      die "browser_url: unknown browser $name"
      ;;
  esac
}

# True if the fetcher for this browser uses stripRoot = false.
strip_root_false() {
  case "$1" in
    chromium-headless-shell|webkit|ffmpeg) return 0 ;;
    *) return 1 ;;
  esac
}

# Parse a "got: sha256-..." line out of a nix-build error log.
_parse_got_hash() {
  awk '/got:[[:space:]]*sha256-/ {print $2; exit}'
}

# Compute a fetchzip hash for a URL using nix-build with a dummy hash and
# parsing the "got:" line from the error output. Works for any fetchzip
# stripRoot setting; pass "true" or "false".
prefetch_fetchzip_hash() {
  local url="$1" strip="$2"
  local log
  log=$(nix-build --no-out-link -E "(import <nixpkgs> {}).fetchzip { url = \"${url}\"; stripRoot = ${strip}; hash = \"${DUMMY_HASH}\"; }" 2>&1 || true)
  local got
  got=$(printf '%s\n' "$log" | _parse_got_hash)
  if [ -z "$got" ]; then
    printf '%s\n' "$log" | tail -10 >&2
    die "prefetch failed for $url"
  fi
  printf '%s' "$got"
}

# Compute the fetchFromGitHub hash for owner/repo at rev.
prefetch_github_hash() {
  local owner="$1" repo="$2" rev="$3"
  local log
  log=$(nix-build --no-out-link -E "(import <nixpkgs> {}).fetchFromGitHub { owner = \"${owner}\"; repo = \"${repo}\"; rev = \"${rev}\"; hash = \"${DUMMY_HASH}\"; }" 2>&1 || true)
  local got
  got=$(printf '%s\n' "$log" | _parse_got_hash)
  if [ -z "$got" ]; then
    printf '%s\n' "$log" | tail -10 >&2
    die "prefetch failed for github ${owner}/${repo}@${rev}"
  fi
  printf '%s' "$got"
}

# Compute npmDepsHash by running buildNpmPackage with a dummy hash. Requires
# the GitHub source hash to already be known so the source can be fetched.
prefetch_npm_deps_hash() {
  local owner="$1" repo="$2" rev="$3" src_hash="$4"
  local log
  log=$(nix-build --no-out-link -E "
    let pkgs = import <nixpkgs> {}; in
    pkgs.buildNpmPackage {
      pname = \"${repo}\";
      version = \"${rev}\";
      src = pkgs.fetchFromGitHub {
        owner = \"${owner}\";
        repo = \"${repo}\";
        rev = \"${rev}\";
        hash = \"${src_hash}\";
      };
      npmDepsHash = \"${DUMMY_HASH}\";
      dontNpmBuild = true;
    }
  " 2>&1 || true)
  local got
  got=$(printf '%s\n' "$log" | _parse_got_hash)
  if [ -z "$got" ]; then
    printf '%s\n' "$log" | tail -15 >&2
    die "prefetch failed for npm deps of ${owner}/${repo}@${rev}"
  fi
  printf '%s' "$got"
}

# Emit a JSON fragment `{ srcHash, npmDepsHash }` for an npm-based tool.
# Owner is always microsoft; repo is the github repo name.
emit_npm_pkg_hashes() {
  local repo="$1" version="$2"
  log "prefetching ${repo}@${version} src hash"
  local src
  src=$(prefetch_github_hash "microsoft" "$repo" "v${version}")
  log "prefetching ${repo}@${version} npmDepsHash"
  local npm
  npm=$(prefetch_npm_deps_hash "microsoft" "$repo" "v${version}" "$src")
  jq -n --arg src "$src" --arg npm "$npm" \
    '{ srcHash: $src, npmDepsHash: $npm }'
}

# Emit a JSON fragment `{ srcHash, driverHashes: { x86_64-linux, aarch64-linux } }`
# for the python tool. The driver tarball lives at cdn.playwright.dev/builds/driver
# and is fetched per arch (linux, linux-arm64).
emit_python_pkg_hashes() {
  local version="$1"
  log "prefetching playwright-python v${version} src hash"
  local src
  src=$(prefetch_github_hash "microsoft" "playwright-python" "v${version}")
  local driver_obj='{}'
  for sys in "${SUPPORTED_SYSTEMS[@]}"; do
    local zip_name
    case "$sys" in
      x86_64-linux)  zip_name="linux" ;;
      aarch64-linux) zip_name="linux-arm64" ;;
      *) die "unsupported system $sys" ;;
    esac
    log "prefetching playwright driver tarball for ${sys}"
    local url="https://cdn.playwright.dev/builds/driver/playwright-${version}-${zip_name}.zip"
    local hash
    hash=$(prefetch_fetchzip_hash "$url" "false")
    driver_obj=$(printf '%s' "$driver_obj" | jq --arg k "$sys" --arg v "$hash" '. + { ($k): $v }')
  done
  jq -n --arg src "$src" --argjson driver "$driver_obj" \
    '{ srcHash: $src, driverHashes: $driver }'
}

# Given rows from parse_browsers_json on stdin, emit a JSON object keyed by
# browser name. Each entry has { revision, [browserVersion], hashes: { <system>: hash } }.
# Writes progress logs to stderr.
emit_browsers_obj() {
  local acc='{}'
  while IFS=$'\t' read -r name revision browserVersion; do
    [ -z "$name" ] && continue
    log "prefetching ${name} ${revision}"
    local strip="true"
    strip_root_false "$name" && strip="false"
    local hashes_obj='{}'
    for sys in "${SUPPORTED_SYSTEMS[@]}"; do
      local url
      url=$(browser_url "$name" "$revision" "$browserVersion" "$sys")
      local hash
      hash=$(prefetch_fetchzip_hash "$url" "$strip")
      hashes_obj=$(printf '%s' "$hashes_obj" | jq --arg k "$sys" --arg v "$hash" '. + { ($k): $v }')
    done
    local entry
    if [ -n "$browserVersion" ]; then
      entry=$(jq -n --arg r "$revision" --arg bv "$browserVersion" --argjson h "$hashes_obj" \
        '{ revision: $r, browserVersion: $bv, hashes: $h }')
    else
      entry=$(jq -n --arg r "$revision" --argjson h "$hashes_obj" \
        '{ revision: $r, hashes: $h }')
    fi
    acc=$(printf '%s' "$acc" | jq --arg name "$name" --argjson entry "$entry" '. + { ($name): $entry }')
  done
  printf '%s' "$acc"
}

# Consume a JSON object on stdin, pretty-print with `jq .`, and atomically
# write to pins/<tool>/<version>.json. Adds a trailing newline.
write_pin_file() {
  local version="$1"
  local file="${PIN_DIR}/${version}.json"
  local tmp="${file}.tmp"
  mkdir -p "$PIN_DIR"
  jq . > "$tmp"
  mv "$tmp" "$file"
}

# True (exit 0) when pins/<tool>/<version>.json already exists on disk.
has_pin_for() {
  local version="$1"
  [ -f "${PIN_DIR}/${version}.json" ]
}

# Merge the given version into pins/<tool>.json. If is_latest=1, also move the
# `latest` pointer. Creates the manifest on first call. Idempotent: adding a
# version already present in .versions leaves the array untouched.
update_manifest() {
  local version="$1" is_latest="$2"
  local existing_latest='""'
  local existing_versions='[]'
  if [ -f "$MANIFEST_FILE" ]; then
    existing_latest=$(jq '.latest // ""' "$MANIFEST_FILE")
    existing_versions=$(jq -c '.versions // []' "$MANIFEST_FILE")
  fi
  local new_latest
  if [ "$is_latest" = "1" ]; then
    new_latest=$(jq -n --arg v "$version" '$v')
  else
    new_latest="$existing_latest"
  fi
  local new_versions
  new_versions=$(printf '%s' "$existing_versions" | jq --arg v "$version" \
    'if any(.[]; . == $v) then . else . + [$v] end')
  local tmp="${MANIFEST_FILE}.tmp"
  jq -n \
    --argjson latest "$new_latest" \
    --argjson versions "$new_versions" \
    '{ latest: $latest, versions: $versions }' > "$tmp"
  mv "$tmp" "$MANIFEST_FILE"
}

# Common tail: build the versioned attr, then stage the new pin file and the
# manifest and commit. No tagging.
finalize() {
  local package_version="$1"
  log "building .#playwright-${TOOL}-${package_version}"
  (cd "$FLAKE_ROOT" && nix build --no-link ".#playwright-${TOOL}-${package_version}")
  log "commit"
  (
    cd "$FLAKE_ROOT"
    git add "pins/${TOOL}/${package_version}.json" "pins/${TOOL}.json"
    if git diff --cached --quiet; then
      log "no changes to commit"
      return 0
    fi
    git commit -m "${TOOL}: add ${package_version}"
  )
  log "done. added ${TOOL}-${package_version}"
}
