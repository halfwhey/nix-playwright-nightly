# shellcheck shell=bash
# Shared helpers sourced by update scripts.
# Callers must set: TOOL, FLAKE_ROOT (absolute path).

set -euo pipefail
# By default bash disables `set -e` inside command substitutions, so a
# `die` deep inside `prefetch_*` would silently leave the caller with an
# empty hash and the update script would happily write a broken pin file.
# inherit_errexit propagates errexit into `$(...)` so those failures abort
# the update script immediately.
shopt -s inherit_errexit

: "${TOOL:?TOOL must be set by caller}"
: "${FLAKE_ROOT:?FLAKE_ROOT must be set by caller}"

PIN_DIR="${FLAKE_ROOT}/pins/${TOOL}"
MANIFEST_FILE="${FLAKE_ROOT}/pins/pin.json"
SUPPORTED_SYSTEMS=(x86_64-linux aarch64-linux aarch64-darwin)

log() { printf '[%s] %s\n' "${TOOL}" "$*" >&2; }
die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

# Re-exec the calling update script inside a `nix shell` that provides
# the prefetch tools we need. We pin nix shell to the exact nixpkgs
# revision from our own flake.lock so the prefetch tools that compute
# hashes are byte-identical to the ones `buildNpmPackage` and friends
# will later consume them with. This keeps the script self-contained:
# no NIX_PATH, no `import <nixpkgs>`, no CI workflow tweaks required.
if [ -z "${UPDATE_SCRIPT_NIX_SHELL_READY:-}" ]; then
  require_cmd nix jq
  _nixpkgs_rev=$(jq -r '.nodes.nixpkgs.locked.rev' "${FLAKE_ROOT}/flake.lock")
  [ -n "$_nixpkgs_rev" ] && [ "$_nixpkgs_rev" != "null" ] ||
    die "could not read nixpkgs rev from ${FLAKE_ROOT}/flake.lock"
  _nixpkgs_ref="github:NixOS/nixpkgs/${_nixpkgs_rev}"
  log "entering nix shell with prefetch tools from ${_nixpkgs_ref}"
  export UPDATE_SCRIPT_NIX_SHELL_READY=1
  exec nix shell \
    "${_nixpkgs_ref}#nix" \
    "${_nixpkgs_ref}#prefetch-npm-deps" \
    "${_nixpkgs_ref}#curl" \
    "${_nixpkgs_ref}#jq" \
    "${_nixpkgs_ref}#unzip" \
    -c "$0" "$@"
fi

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
# registry for x86_64-linux (ubuntu24.04-x64), aarch64-linux
# (ubuntu24.04-arm64), and aarch64-darwin. For Darwin WebKit, upstream's
# registry maps the supported mac26-arm64 host platform to the
# `webkit-mac-15-arm64.zip` artifact for the currently pinned revisions, so we
# intentionally mirror that download path here.
browser_url() {
  local name="$1" revision="$2" browserVersion="$3" system="$4"
  case "$name" in
  chromium)
    case "$system" in
    x86_64-linux) printf 'https://cdn.playwright.dev/builds/cft/%s/linux64/chrome-linux64.zip' "$browserVersion" ;;
    aarch64-linux) printf 'https://cdn.playwright.dev/builds/chromium/%s/chromium-linux-arm64.zip' "$revision" ;;
    aarch64-darwin) printf 'https://cdn.playwright.dev/builds/cft/%s/mac-arm64/chrome-mac-arm64.zip' "$browserVersion" ;;
    esac
    ;;
  chromium-headless-shell)
    case "$system" in
    x86_64-linux) printf 'https://cdn.playwright.dev/builds/cft/%s/linux64/chrome-headless-shell-linux64.zip' "$browserVersion" ;;
    aarch64-linux) printf 'https://cdn.playwright.dev/builds/chromium/%s/chromium-headless-shell-linux-arm64.zip' "$revision" ;;
    aarch64-darwin) printf 'https://cdn.playwright.dev/builds/cft/%s/mac-arm64/chrome-headless-shell-mac-arm64.zip' "$browserVersion" ;;
    esac
    ;;
  firefox)
    case "$system" in
    x86_64-linux) printf 'https://cdn.playwright.dev/builds/firefox/%s/firefox-ubuntu-22.04.zip' "$revision" ;;
    aarch64-linux) printf 'https://cdn.playwright.dev/builds/firefox/%s/firefox-ubuntu-22.04-arm64.zip' "$revision" ;;
    aarch64-darwin) printf 'https://cdn.playwright.dev/builds/firefox/%s/firefox-mac-arm64.zip' "$revision" ;;
    esac
    ;;
  webkit)
    case "$system" in
    x86_64-linux) printf 'https://cdn.playwright.dev/builds/webkit/%s/webkit-ubuntu-22.04.zip' "$revision" ;;
    aarch64-linux) printf 'https://cdn.playwright.dev/builds/webkit/%s/webkit-ubuntu-22.04-arm64.zip' "$revision" ;;
    aarch64-darwin) printf 'https://cdn.playwright.dev/builds/webkit/%s/webkit-mac-15-arm64.zip' "$revision" ;;
    esac
    ;;
  ffmpeg)
    case "$system" in
    x86_64-linux) printf 'https://cdn.playwright.dev/builds/ffmpeg/%s/ffmpeg-linux.zip' "$revision" ;;
    aarch64-linux) printf 'https://cdn.playwright.dev/builds/ffmpeg/%s/ffmpeg-linux-arm64.zip' "$revision" ;;
    aarch64-darwin) printf 'https://cdn.playwright.dev/builds/ffmpeg/%s/ffmpeg-mac-arm64.zip' "$revision" ;;
    esac
    ;;
  *)
    die "browser_url: unknown browser $name"
    ;;
  esac
}

# True (exit 0) if the fetcher for this browser/system pair uses
# `stripRoot = false`. Keep this in sync with lib/browsers/*.nix.
strip_root_false() {
  local name="$1" system="$2"
  case "${name}:${system}" in
  chromium-headless-shell:* | webkit:* | ffmpeg:* | chromium:aarch64-darwin | firefox:aarch64-darwin) return 0 ;;
  *) return 1 ;;
  esac
}

# Compute a fetchzip-equivalent NAR hash for a URL. `strip` selects
# between fetchzip's two modes:
#   "true"  — matches fetchzip { stripRoot = true; } (the default).
#             `nix-prefetch-url --unpack` always strips the single top-
#             level directory from an archive, which is what we want.
#   "false" — matches fetchzip { stripRoot = false; }. We have to
#             download + unzip + hash the directory ourselves, because
#             nix-prefetch-url has no "don't strip" flag.
prefetch_fetchzip_hash() {
  local url="$1" strip="$2"
  case "$strip" in
  true)
    local b32
    b32=$(nix-prefetch-url --unpack "$url" 2>/dev/null) ||
      die "prefetch failed for $url"
    nix hash convert --to sri --hash-algo sha256 "$b32"
    ;;
  false)
    local tmpdir archive extract hash
    tmpdir=$(mktemp -d)
    archive="${tmpdir}/archive.zip"
    extract="${tmpdir}/extract"
    mkdir "$extract"
    if ! curl -fsSL "$url" -o "$archive"; then
      rm -rf "$tmpdir"
      die "fetch failed for $url"
    fi
    if ! unzip -q "$archive" -d "$extract"; then
      rm -rf "$tmpdir"
      die "unzip failed for $url"
    fi
    hash=$(nix hash path --type sha256 --sri "$extract")
    rm -rf "$tmpdir"
    printf '%s' "$hash"
    ;;
  *)
    die "prefetch_fetchzip_hash: strip must be true|false, got '$strip'"
    ;;
  esac
}

# Compute the fetchFromGitHub SRI hash for owner/repo at rev using the
# same GitHub archive tarball + unpack flow as fetchzip/fetchFromGitHub.
# This avoids `nix-prefetch-github`, whose legacy helper chain is brittle
# on GitHub runners.
prefetch_github_hash() {
  local owner="$1" repo="$2" rev="$3"
  local url="https://github.com/${owner}/${repo}/archive/${rev}.tar.gz"
  local out
  out=$(nix store prefetch-file --json --unpack --hash-type sha256 "$url") ||
    die "prefetch failed for github ${owner}/${repo}@${rev}"
  printf '%s' "$out" | jq -r '.hash'
}

# Compute npmDepsHash by fetching the upstream package-lock.json from
# raw.githubusercontent.com and feeding it to nixpkgs' prefetch-npm-deps
# tool. This is the same tool buildNpmPackage runs internally, so the
# hash is guaranteed to match.
prefetch_npm_deps_hash() {
  local owner="$1" repo="$2" rev="$3"
  local lockfile
  lockfile=$(mktemp)
  trap 'rm -f "$lockfile"' RETURN
  curl -fsSL \
    "https://raw.githubusercontent.com/${owner}/${repo}/${rev}/package-lock.json" \
    -o "$lockfile" ||
    die "could not fetch package-lock.json for ${owner}/${repo}@${rev}"
  prefetch-npm-deps "$lockfile" ||
    die "prefetch-npm-deps failed for ${owner}/${repo}@${rev}"
}

# Emit a JSON fragment `{ srcHash, npmDepsHash }` for an npm-based tool.
# Owner is always microsoft; `repo` is the github repo name; `rev` is a
# git commit SHA (we use the npm metadata's `gitHead`, not a version tag,
# because pre-release / alpha versions of @playwright/cli and
# @playwright/mcp are published to npm without ever being tagged in the
# upstream repo).
emit_npm_pkg_hashes() {
  local repo="$1" rev="$2"
  log "prefetching ${repo}@${rev} src hash"
  local src
  src=$(prefetch_github_hash "microsoft" "$repo" "$rev")
  log "prefetching ${repo}@${rev} npmDepsHash"
  local npm
  npm=$(prefetch_npm_deps_hash "microsoft" "$repo" "$rev")
  jq -n --arg src "$src" --arg npm "$npm" \
    '{ srcHash: $src, npmDepsHash: $npm }'
}

# Emit a JSON fragment `{ srcHash, driverHashes: { x86_64-linux, aarch64-linux } }`
# for the python tool. The source tag uses the PyPI package version, while the
# embedded driver may use a different playwright-core version. The driver
# tarball lives at cdn.playwright.dev/builds/driver[/next] and is fetched per
# arch (linux, linux-arm64, mac-arm64).
emit_python_pkg_hashes() {
  local package_version="$1"
  local driver_version="${2:-$package_version}"
  log "prefetching playwright-python v${package_version} src hash"
  local src
  src=$(prefetch_github_hash "microsoft" "playwright-python" "v${package_version}")
  local driver_path=""
  case "$driver_version" in
  *-alpha* | *-beta* | *-next*) driver_path="next/" ;;
  esac
  local driver_obj='{}'
  for sys in "${SUPPORTED_SYSTEMS[@]}"; do
    local zip_name
    case "$sys" in
    x86_64-linux) zip_name="linux" ;;
    aarch64-linux) zip_name="linux-arm64" ;;
    aarch64-darwin) zip_name="mac-arm64" ;;
    *) die "unsupported system $sys" ;;
    esac
    log "prefetching playwright driver tarball for ${sys}"
    local url="https://cdn.playwright.dev/builds/driver/${driver_path}playwright-${driver_version}-${zip_name}.zip"
    # pkgs/playwright-python.nix fetches the driver with stripRoot = false.
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
    local hashes_obj='{}'
    for sys in "${SUPPORTED_SYSTEMS[@]}"; do
      local strip="true"
      strip_root_false "$name" "$sys" && strip="false"
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
  jq . >"$tmp"
  mv "$tmp" "$file"
}

# True (exit 0) when pins/<tool>/<version>.json already exists on disk.
has_pin_for() {
  local version="$1"
  [ -f "${PIN_DIR}/${version}.json" ]
}

# Merge the given version into pins/pin.json under the .${TOOL} key. If
# is_latest=1, also move the `latest` pointer. Creates the file on first call.
# Idempotent: adding a version already present in .versions leaves it untouched.
update_manifest() {
  local version="$1" is_latest="$2"
  local manifest='{}'
  if [ -f "$MANIFEST_FILE" ]; then
    manifest=$(cat "$MANIFEST_FILE")
  fi
  local tmp="${MANIFEST_FILE}.tmp"
  printf '%s' "$manifest" | jq \
    --arg tool "$TOOL" \
    --arg v "$version" \
    --argjson is_latest "$is_latest" \
    '
    . as $m
    | ($m[$tool] // { latest: "", versions: [] }) as $entry
    | ($entry.versions | if any(.[]; . == $v) then . else . + [$v] end) as $new_versions
    | (if $is_latest == 1 then $v else $entry.latest end) as $new_latest
    | $m + { ($tool): { latest: $new_latest, versions: $new_versions } }
    ' >"$tmp"
  mv "$tmp" "$MANIFEST_FILE"
}

# Common tail: stage the new pin file and manifest so the dirty worktree
# exposes them to nix's flake resolver, build the versioned attr, then commit.
# No tagging.
finalize() {
  local package_version="$1"
  # nix CLI parses `.` as attrpath separator, so the flake attribute name
  # replaces dots with underscores (see packages.nix toAttr).
  local attr_version="${package_version//./_}"
  (
    cd "$FLAKE_ROOT"
    # Must stage BEFORE `nix build`: nix's git+file:// flake resolver only
    # sees tracked (or intent-to-add) files in a dirty worktree, so a brand
    # new pins/<tool>/<version>.json would be invisible otherwise.
    git add "pins/${TOOL}/${package_version}.json" "pins/pin.json"
  )
  log "building .#playwright-${TOOL}-${attr_version}"
  (cd "$FLAKE_ROOT" && nix build --no-link ".#playwright-${TOOL}-${attr_version}")
  log "commit"
  (
    cd "$FLAKE_ROOT"
    if git diff --cached --quiet; then
      log "no changes to commit"
      return 0
    fi
    git commit -m "${TOOL}: add ${package_version}"
  )
  log "done. added ${TOOL}-${package_version}"
}
