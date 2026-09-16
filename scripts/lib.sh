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

# Resolve source builds to an immutable commit. npm no longer always publishes
# gitHead; release tags are a fallback, while older untagged alphas keep working.
resolve_npm_source_sha() {
  local meta="$1" repo="$2" version sha refs source_meta
  version=$(printf '%s' "$meta" | jq -er '.version | strings | select(length > 0)')
  sha=$(printf '%s' "$meta" | jq -r '.gitHead // empty')
  if [ -z "$sha" ]; then
    log "gitHead missing; resolving ${repo} tag v${version}"
    refs=$(git ls-remote --tags "https://github.com/microsoft/${repo}.git" \
      "refs/tags/v${version}" "refs/tags/v${version}^{}") ||
      die "could not query ${repo} tag v${version}"
    # Prefer the peeled commit for annotated tags.
    sha=$(printf '%s\n' "$refs" | awk '
      $2 ~ /\^\{\}$/ { peeled = $1 }
      $2 !~ /\^\{\}$/ { direct = $1 }
      END { print (peeled != "" ? peeled : direct) }
    ')
  fi
  [[ $sha =~ ^[0-9a-f]{40}$ ]] ||
    die "could not resolve an immutable source commit for ${repo}@${version}"
  source_meta=$(curl -fsSL "https://raw.githubusercontent.com/microsoft/${repo}/${sha}/package.json") ||
    die "could not fetch source metadata for ${repo}@${sha}"
  printf '%s' "$source_meta" | jq -e --argjson published "$meta" '
    .name == $published.name and .version == $published.version
    and .dependencies == $published.dependencies
  ' >/dev/null || die "source metadata does not match published ${repo}@${version}"
  printf '%s' "$sha"
}

# Read the browser manifest shipped in the exact core release. This also works
# for alphas with neither gitHead nor a Git tag. Nix unpacks into the store;
# no archive paths are extracted into the working tree.
fetch_npm_browsers_json() {
  local version="$1" meta url archive_path
  meta=$(curl -fsSL "https://registry.npmjs.org/playwright-core/${version}")
  url=$(printf '%s' "$meta" | jq -er '.dist.tarball | strings | select(startswith("https://"))')
  archive_path=$(nix store prefetch-file --json --unpack "$url" | jq -er '.storePath')
  jq -e --arg version "$version" '
    .name == "playwright-core" and .version == $version
  ' "$archive_path/package.json" >/dev/null ||
    die "core tarball does not match playwright-core@${version}"
  jq -e '
    .browsers | type == "array" and length > 0
    and all(.[]; (.name | type == "string") and (.revision | type == "string"))
  ' "$archive_path/browsers.json" >/dev/null ||
    die "invalid browsers.json in playwright-core@${version}"
  read_browsers_json "$archive_path"
}

# Read the executable layout from the published driver, since the ARM CFT
# migration did not coincide with a browser revision bump. Old pins omit this
# flag and retain their original URLs and store paths.
read_browsers_json() {
  local package_dir="$1" registry arm64_cft
  if [ -f "$package_dir/lib/coreBundle.js" ]; then
    registry="$package_dir/lib/coreBundle.js"
  else
    registry="$package_dir/lib/server/registry/index.js"
  fi
  [ -f "$registry" ] || die "missing browser registry in $package_dir"
  if grep -Eq "['\"]linux-arm64['\"]: *\\[['\"]chrome-linux-arm64['\"]" "$registry"; then
    arm64_cft=true
  elif grep -Eq "['\"]linux-arm64['\"]: *\\[['\"]chrome-linux['\"]" "$registry"; then
    arm64_cft=false
  else
    die "unrecognized ARM Linux Chromium layout in $registry"
  fi
  jq --argjson cft "$arm64_cft" '
    if $cft then
      .browsers |= map(if .name == "chromium" or .name == "chromium-headless-shell"
                      then . + {arm64Cft: true} else . end)
    else . end
  ' "$package_dir/browsers.json"
}

# Filter browsers.json down to the browsers we support. Echoes tab-separated
# rows: name<TAB>revision<TAB>arm64Cft<TAB>browserVersion (browserVersion may be empty).
# Only emits browsers with installByDefault == true and that we have a fetcher
# for (chromium, chromium-headless-shell, firefox, webkit, ffmpeg).
parse_browsers_json() {
  local json="$1"
  printf '%s' "$json" | jq -r '
    .browsers[]
    | select(.installByDefault == true)
    | select(.name | IN("chromium","chromium-headless-shell","firefox","webkit","ffmpeg"))
    | [.name, .revision, (.arm64Cft // false), (.browserVersion // "")]
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
  local name="$1" revision="$2" browserVersion="$3" system="$4" arm64_cft="${5:-false}"
  case "$name" in
  chromium)
    case "$system" in
    x86_64-linux) printf 'https://cdn.playwright.dev/builds/cft/%s/linux64/chrome-linux64.zip' "$browserVersion" ;;
    aarch64-linux)
      if [ "$arm64_cft" = true ]; then
        printf 'https://cdn.playwright.dev/builds/cft/%s/linux-arm64/chrome-linux-arm64.zip' "$browserVersion"
      else
        printf 'https://cdn.playwright.dev/builds/chromium/%s/chromium-linux-arm64.zip' "$revision"
      fi
      ;;
    aarch64-darwin) printf 'https://cdn.playwright.dev/builds/cft/%s/mac-arm64/chrome-mac-arm64.zip' "$browserVersion" ;;
    esac
    ;;
  chromium-headless-shell)
    case "$system" in
    x86_64-linux) printf 'https://cdn.playwright.dev/builds/cft/%s/linux64/chrome-headless-shell-linux64.zip' "$browserVersion" ;;
    aarch64-linux)
      if [ "$arm64_cft" = true ]; then
        printf 'https://cdn.playwright.dev/builds/cft/%s/linux-arm64/chrome-headless-shell-linux-arm64.zip' "$browserVersion"
      else
        printf 'https://cdn.playwright.dev/builds/chromium/%s/chromium-headless-shell-linux-arm64.zip' "$revision"
      fi
      ;;
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
    b32=$(nix-prefetch-url --unpack "$url") ||
      die "prefetch failed for $url"
    nix hash convert --to sri --hash-algo sha256 "$b32"
    ;;
  false)
    local tmpdir archive extract hash
    tmpdir=$(mktemp -d)
    archive="${tmpdir}/archive.zip"
    extract="${tmpdir}/extract"
    mkdir "$extract"
    if ! curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL "$url" -o "$archive"; then
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
# git commit SHA resolved from npm metadata or a release tag.
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

# Emit a JSON fragment `{ srcHash, driverUrls, driverHashes }` for the Python
# tool. Modern playwright-python releases assemble the driver while building
# their platform wheels instead of publishing standalone driver archives, so
# use the immutable wheel URLs from PyPI and extract the bundled driver later.
emit_python_pkg_hashes() {
  local package_version="$1"
  log "prefetching playwright-python v${package_version} src hash"
  local src
  src=$(prefetch_github_hash "microsoft" "playwright-python" "v${package_version}")
  local release
  release=$(curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL \
    "https://pypi.org/pypi/playwright/${package_version}/json") ||
    die "could not fetch PyPI release metadata for playwright ${package_version}"
  local urls_obj='{}'
  local driver_obj='{}'
  for sys in "${SUPPORTED_SYSTEMS[@]}"; do
    local wheel_pattern
    case "$sys" in
    x86_64-linux) wheel_pattern='manylinux.*x86_64[.]whl$' ;;
    aarch64-linux) wheel_pattern='manylinux.*aarch64[.]whl$' ;;
    aarch64-darwin) wheel_pattern='macosx.*arm64[.]whl$' ;;
    *) die "unsupported system $sys" ;;
    esac
    local url
    url=$(printf '%s' "$release" | jq -er --arg pattern "$wheel_pattern" '
      [
        .urls[]
        | select(.packagetype == "bdist_wheel")
        | select(.filename | test($pattern))
        | .url
      ]
      | if length == 1 then .[0] else error("expected exactly one matching wheel") end
    ') || die "could not resolve a unique playwright ${package_version} wheel for ${sys}"
    log "prefetching playwright wheel driver for ${sys}"
    local hash
    hash=$(prefetch_fetchzip_hash "$url" "false")
    urls_obj=$(printf '%s' "$urls_obj" | jq --arg k "$sys" --arg v "$url" '. + { ($k): $v }')
    driver_obj=$(printf '%s' "$driver_obj" | jq --arg k "$sys" --arg v "$hash" '. + { ($k): $v }')
  done
  jq -n --arg src "$src" --argjson urls "$urls_obj" --argjson driver "$driver_obj" \
    '{ srcHash: $src, driverUrls: $urls, driverHashes: $driver }'
}

# Given rows from parse_browsers_json on stdin, emit a JSON object keyed by
# browser name. Each entry has { revision, [browserVersion], hashes: { <system>: hash } }.
# Writes progress logs to stderr.
emit_browsers_obj() {
  local acc='{}'
  while IFS=$'\t' read -r name revision arm64_cft browserVersion; do
    [ -z "$name" ] && continue
    log "prefetching ${name} ${revision}"
    local hashes_obj='{}'
    for sys in "${SUPPORTED_SYSTEMS[@]}"; do
      local strip="true"
      strip_root_false "$name" "$sys" && strip="false"
      local url
      url=$(browser_url "$name" "$revision" "$browserVersion" "$sys" "$arm64_cft")
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
    if [ "$arm64_cft" = true ]; then
      entry=$(printf '%s' "$entry" | jq '. + {arm64Cft: true}')
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
