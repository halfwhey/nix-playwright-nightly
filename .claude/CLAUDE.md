# nix-playwright-nightly

A Nix flake that packages `@playwright/cli`, `@playwright/mcp`, and PyPI `playwright` as pure-Nix derivations, each bundled with the exact browser revisions its `playwright-core` requires. Drop it into a flake input and use it: no env vars, no extra setup, no runtime browser downloads, no `npx`/`pip install` at runtime.

Supported systems: `x86_64-linux`, `aarch64-linux`.

## Usage

Pin `main` once and pick the version per tool via the flake attribute name:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    playwright.url = "github:halfwhey/nix-playwright-nightly";
  };

  outputs = { self, nixpkgs, playwright }:
    let system = "x86_64-linux"; in {
      devShells.${system}.default =
        nixpkgs.legacyPackages.${system}.mkShell {
          packages = [
            playwright.packages.${system}.playwright-cli           # latest cli
            playwright.packages.${system}.playwright-mcp-0_0_70    # pinned mcp
            playwright.packages.${system}.playwright-python-1_58_0 # pinned python
          ];
        };
    };
}
```

```sh
$ nix develop
$ playwright-cli --version              # latest cli
$ playwright-mcp --version              # Version 0.0.70
$ playwright --version                  # Version 1.58.0
$ playwright-cli open --browser=chromium https://example.com
# launches chromium without downloading
```

### Versioned outputs, no git tags

Every commit of `main` exposes all known versions side by side as flake attributes:

- `playwright-cli` / `playwright-mcp` / `playwright-python` alias to the current upstream latest (the one `pins/<tool>.json`'s `.latest` pointer names).
- `playwright-cli-<version>` / `playwright-mcp-<version>` / `playwright-python-<version>` are the same packages pinned to the exact version you name. Because the Nix CLI parses `.` as an attrpath separator, the version segment uses underscores: `playwright-cli-0_1_5`, `playwright-mcp-0_0_70`, `playwright-python-1_58_0`.
- `playwright-<tool>-browsers` and `playwright-<tool>-<version>-browsers` are the corresponding browser linkFarms, exposed for library users who embed playwright and set their own `PLAYWRIGHT_BROWSERS_PATH`.

Nix is lazy, so referencing one versioned attribute only evaluates that version's pin JSON. Unused historical versions cost nothing at build time. There are **no git tags** for version selection — any recent commit of `main` has every version you'd want, selected by attribute name.

### Other patterns

- **Latest of everything in one input** — pin `main`: `github:halfwhey/nix-playwright-nightly`. Main's HEAD always has the freshest aliases for every tool.
- **One-off with `nix run`** — `nix run github:halfwhey/nix-playwright-nightly#playwright-cli-0_1_5 -- open https://example.com`.
- **NixOS system package** — `environment.systemPackages = [ inputs.playwright.packages.${pkgs.system}.playwright-cli-0_1_5 ];`.
- **Library use (browsers only)** — `packages.${system}.playwright-<tool>-browsers` (latest) or `packages.${system}."playwright-<tool>-<version>-browsers"` (pinned) is exposed as a passthrough linkFarm. Point your own wrapper at it via `PLAYWRIGHT_BROWSERS_PATH`.

### What the consumer does NOT have to do

- Set `PLAYWRIGHT_BROWSERS_PATH` or `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` — already wrapped.
- Run `playwright install` / `bunx playwright install` — browsers are baked in.
- Have `bun`, `npm`, `pip`, or `uv` installed — every package is a pure-Nix derivation with no runtime network access.
- Pick a matching browser flake separately.
- Care that cli / mcp / python disagree on browser revisions.

## Outputs

Each commit of `main` exposes a latest alias per tool plus one attribute per pinned version, and the same split for the browser passthroughs:

| Package | Wraps | Release feed |
|---|---|---|
| `packages.${system}.playwright-cli` | `@playwright/cli` (latest) | `registry.npmjs.org/@playwright/cli` |
| `packages.${system}."playwright-cli-<v>"` | `@playwright/cli` (pinned) | per-version pin |
| `packages.${system}.playwright-mcp` | `@playwright/mcp` (latest) | `registry.npmjs.org/@playwright/mcp` |
| `packages.${system}."playwright-mcp-<v>"` | `@playwright/mcp` (pinned) | per-version pin |
| `packages.${system}.playwright-python` | PyPI `playwright` (latest) | `pypi.org/pypi/playwright/json` |
| `packages.${system}."playwright-python-<v>"` | PyPI `playwright` (pinned) | per-version pin |
| `packages.${system}.playwright-<tool>-browsers` | linkFarm of latest's browsers | passthrough |
| `packages.${system}."playwright-<tool>-<v>-browsers"` | linkFarm of pinned browsers | passthrough |

## The core problem this flake solves

Playwright's browser resolver (`playwright-core/src/server/registry/index.ts`) reads `PLAYWRIGHT_BROWSERS_PATH` and looks for an exact `${name.replace(/-/g, '_')}-${revision}` subdirectory. The revision is hardcoded per-browser in that playwright version's `browsers.json`. If the directory was built from a different playwright revision, playwright treats the browser as missing and tries to download it at runtime.

`@playwright/cli`, `@playwright/mcp`, and PyPI `playwright` each release on independent cadences and regularly pin different `playwright-core` versions at the same moment. nixpkgs's `playwright-driver.browsers` almost never matches any of them. This flake builds a separate browser set per consumer and bakes the right one into each wrapper.

### This divergence is real, not hypothetical

Traced on 2026-04-06:

| Consumer | Latest version | `playwright-core` it pins | chromium | webkit | firefox | ffmpeg |
|---|---|---|---|---|---|---|
| `@playwright/cli` | 0.1.5 | 1.60.0-alpha-1775237291000 | 1219 | 2276 | 1511 | 1011 |
| `@playwright/mcp` | 0.0.70 | 1.60.0-alpha-1774999321000 | 1217 | 2272 | 1511 | 1011 |
| pypi `playwright` | 1.58.0 | stable 1.58.0 (separate repo) | (v1.58.0) | (v1.58.0) | (v1.58.0) | (v1.58.0) |

cli and mcp diverged on chromium (1219 vs 1217) and webkit (2276 vs 2272) even though both were `latest` at the same moment. Firefox and ffmpeg coincidentally matched — the Nix store dedupes those derivations across consumers for free.

## Repository layout

Single long-lived branch (`main`). Pin data lives in `pins/` (machine-managed): one manifest JSON per tool plus a directory of per-version pin files. Package wiring lives in `packages.nix`. `flake.nix` is thin boilerplate.

```
flake.nix                           # thin: inputs, outputs, system loop, imports ./packages.nix
packages.nix                        # reads each manifest, exposes versioned + latest attrs
flake.lock
pins/
  cli.json                          # MANIFEST: { latest, versions } for cli
  mcp.json                          # MANIFEST for mcp
  python.json                       # MANIFEST for python
  cli/
    <version>.json                  # per-version cli pin data (managed by update-cli.sh)
  mcp/
    <version>.json                  # per-version mcp pin data
  python/
    <version>.json                  # per-version python pin data
  README.md
lib/
  mkBrowsers.nix                    # { chromium, firefox, webkit, ... } -> linkFarm of ${name}-${revision}
  browsers/                         # per-browser CDN fetchers (adapted from upstream, see Reference)
    chromium.nix
    chromium-headless-shell.nix
    firefox.nix
    webkit.nix
    ffmpeg.nix
pkgs/
  playwright-cli.nix                # buildNpmPackage wrapper for @playwright/cli
  playwright-mcp.nix                # buildNpmPackage wrapper for @playwright/mcp
  playwright-python.nix             # buildPythonPackage wrapper for PyPI playwright
scripts/
  lib.sh                            # shared shell helpers (hash prefetch, JSON pin emitters)
  backfill.sh                       # enumerate missing versions and drive the update scripts
update-cli.sh                       # ./update-cli.sh [version]     default: latest on npm
update-mcp.sh                       # ./update-mcp.sh [version]     default: latest on npm
update-python.sh                    # ./update-python.sh [version]  default: latest on PyPI
.github/workflows/
  sync.yml                          # scheduled: backfill every missing version since last run
  ci.yml                            # PR/push: nix flake check + smoke builds
README.md
CLAUDE.md                           # this file
```

This is a fresh project, not a fork. The per-browser fetchers under `lib/browsers/` are adapted from `pietdevries94/playwright-web-flake`'s `playwright-driver/` (keep their license headers). Everything else (the `pkgs/` derivations, the multi-pin JSON model, the update scripts, and the backfill CI) is designed from scratch for this repo's per-package nightly tracking model.

## Pin file shape

### Manifest (`pins/<tool>.json`)

The manifest is authoritative for what versions exist and which one is latest. `packages.nix` reads it with `builtins.fromJSON (builtins.readFile ./pins/<tool>.json)` and maps over `.versions` to build the versioned flake attributes; `.latest` picks which version backs the unversioned `playwright-<tool>` alias.

```json
{
  "latest": "0.1.5",
  "versions": [
    "0.1.5",
    "0.1.4"
  ]
}
```

`versions` is appended to in publish-time order (backfill runs the update script per missing version in chronological order). `latest` moves only when the version being added matches the upstream `dist-tags.latest` / `info.version`.

### Per-version pin (`pins/<tool>/<version>.json`)

Each file holds the data needed to build one version of one tool:

```json
{
  "package": "0.1.5",
  "playwrightVersion": "1.60.0-alpha-1775237291000",
  "playwrightSha": "87b2074de5cccbde1c0c7b2be67d021d6acdedfe",
  "srcHash": "sha256-...",
  "npmDepsHash": "sha256-...",
  "browsers": {
    "chromium": {
      "revision": "1219",
      "browserVersion": "147.0.7727.49",
      "hashes": {
        "x86_64-linux": "sha256-...",
        "aarch64-linux": "sha256-..."
      }
    }
  }
}
```

`chromium-headless-shell`, `firefox`, `webkit`, and `ffmpeg` entries share the same shape (`ffmpeg` has no `browserVersion`). `pins/mcp/<v>.json` is structurally identical. `pins/python/<v>.json` replaces `npmDepsHash` with `driverHashes: { "x86_64-linux": "…", "aarch64-linux": "…" }` for the embedded JS driver tarball; everything else is the same.

### `packages.nix`

```nix
{ pkgs }:
let
  mkBrowsers = pkgs.callPackage ./lib/mkBrowsers.nix { };
  readJSON = path: builtins.fromJSON (builtins.readFile path);

  mkCli = pin: pkgs.callPackage ./pkgs/playwright-cli.nix { } {
    version = pin.package;
    inherit (pin) srcHash npmDepsHash;
    browsers = mkBrowsers pin.browsers;
  };
  # ... mkMcp / mkPython analogous ...

  # Dots in the version segment would be parsed as attrpath separators
  # by the nix CLI (`.#playwright-cli-0.1.5` → three nested attrs), so we
  # replace them with underscores for the attribute name. The pin file on
  # disk still uses the dotted version.
  toAttr = v: builtins.replaceStrings [ "." ] [ "_" ] v;

  buildTool = { prefix, manifestPath, pinDir, mk }:
    let
      manifest = readJSON manifestPath;
      pinFor   = v: readJSON (pinDir + "/${v}.json");
      versionedPkgs     = map (v: { name = "${prefix}-${toAttr v}";          value = mk (pinFor v); }) manifest.versions;
      versionedBrowsers = map (v: { name = "${prefix}-${toAttr v}-browsers"; value = mkBrowsers (pinFor v).browsers; }) manifest.versions;
      latestPin = pinFor manifest.latest;
    in
    builtins.listToAttrs (versionedPkgs ++ versionedBrowsers) // {
      "${prefix}"          = mk latestPin;
      "${prefix}-browsers" = mkBrowsers latestPin.browsers;
    };

  cliOutputs    = buildTool { prefix = "playwright-cli";    manifestPath = ./pins/cli.json;    pinDir = ./pins/cli;    mk = mkCli; };
  mcpOutputs    = buildTool { prefix = "playwright-mcp";    manifestPath = ./pins/mcp.json;    pinDir = ./pins/mcp;    mk = mkMcp; };
  pythonOutputs = buildTool { prefix = "playwright-python"; manifestPath = ./pins/python.json; pinDir = ./pins/python; mk = mkPython; };
in
cliOutputs // mcpOutputs // pythonOutputs // {
  default = cliOutputs."playwright-cli";
}
```

`flake.nix` itself is the thinnest possible wrapper: inputs, outputs, the x86_64-linux / aarch64-linux system loop, and `packages = import ./packages.nix { inherit pkgs; };`.

### Package derivations

All three live in `pkgs/` and are `callPackage`-d with a pin-derived argument set. None of them fetch anything at runtime.

- **`pkgs/playwright-cli.nix`** — `buildNpmPackage` from `microsoft/playwright-cli` at `v<version>`. `dontNpmBuild = true`. `postFixup` calls `wrapProgram $out/bin/playwright-cli --set PLAYWRIGHT_BROWSERS_PATH ${browsers} --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1`.
- **`pkgs/playwright-mcp.nix`** — `buildNpmPackage` from `microsoft/playwright-mcp`. mcp's repo is an npm workspace (`playwright-mcp-internal`) so the wrapped bin is not auto-exposed — a `postInstall` symlinks `$out/lib/node_modules/playwright-mcp-internal/packages/playwright-mcp/cli.js` to `$out/bin/playwright-mcp` before `wrapProgram`.
- **`pkgs/playwright-python.nix`** — `buildPythonPackage` (`pyproject = true`) from `microsoft/playwright-python` at `v<version>`. A nested `driver` derivation fetches the `playwright-${driverVersion}-<arch>.zip` JS-driver tarball from `cdn.playwright.dev/builds/driver` and runs it through `autoPatchelfHook`. `postPatch` strips `auditwheel`/`setuptools-scm` from `pyproject.toml` and removes the upstream `setup.py` (we provide the driver ourselves). `postInstall` copies the driver into `site-packages/playwright/driver/`. `postFixup` wraps the `playwright` binary with `PLAYWRIGHT_BROWSERS_PATH`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`, and **`PLAYWRIGHT_NODEJS_PATH = ${lib.getExe nodejs}`** — see NixOS notes.

Each wrapper sets `PLAYWRIGHT_BROWSERS_PATH` via `wrapProgram`, not via `shellHook`: multiple tools with different browser sets must coexist in one shell without clobbering each other's env.

## Version resolution chains

### cli and mcp (npm)

```
npm:@playwright/<tool>@<v>  .dependencies.playwright        →  playwright alpha version
npm:playwright@<alpha>       .gitHead                         →  microsoft/playwright SHA
raw.githubusercontent.com/microsoft/playwright/<sha>/packages/playwright-core/browsers.json
                                                             →  per-browser revisions
```

Traced 2026-04-06 examples:

```
@playwright/cli@0.1.5  →  playwright@1.60.0-alpha-1775237291000  →  87b2074de5cccbde1c0c7b2be67d021d6acdedfe
@playwright/mcp@0.0.70 →  playwright@1.60.0-alpha-1774999321000  →  cec7b21afa00c0f48e46859c683680a2c6e9e029
```

### python (PyPI)

Python's `playwright` package lives in `microsoft/playwright-python` (not `microsoft/playwright`) and hardcodes a `driver_version` in `setup.py`.

```
pypi.org/pypi/playwright/json                                →  PyPI version (e.g. 1.58.0)
raw.../microsoft/playwright-python/v<pypi>/setup.py          →  driver_version = "1.58.0"
npm:playwright@<driver> .gitHead                              →  microsoft/playwright SHA
raw.../microsoft/playwright/<sha>/packages/playwright-core/browsers.json
```

The Python codepath in `update-python.sh` stays structurally separate from the npm codepath — it has no `dependencies.playwright` to read. Note: beta drivers (e.g. `1.57.0-beta-...`) are not tagged in `microsoft/playwright`, so we resolve the SHA via npm `playwright@<driver>.gitHead` rather than `git ls-remote refs/tags/v<driver>`.

## Update scripts (`update-cli.sh`, `update-mcp.sh`, `update-python.sh`)

All three share the same shape. Differences are only in steps 1–3 (resolving the package → playwright SHA chain) and in which hash emitter they call (`emit_npm_pkg_hashes` for cli/mcp, `emit_python_pkg_hashes` for python). Shared helpers live in `scripts/lib.sh`.

```sh
./update-cli.sh            # bump to latest on npm
./update-cli.sh 0.1.4      # bump to specific version
```

Steps:

1. Resolve `upstream_latest` (npm `dist-tags.latest` or PyPI `info.version`). Pick `package_version` from the CLI arg, or default to `upstream_latest`. Set `is_latest=1` when they match.
2. If `pins/<tool>/<package_version>.json` already exists on disk, exit immediately (idempotent).
3. Resolve `playwright_version` (npm `dependencies.playwright`, or PyPI → setup.py `driver_version`).
4. Resolve `playwright_sha` (npm `gitHead` for both npm tools and python's driver resolution).
5. Prefetch hashes by running dummy-hash `nix-build` invocations and parsing the `got:` line from the resulting error:
   - `fetchFromGitHub microsoft/<repo> v<version>` → `srcHash`
   - For npm tools: `buildNpmPackage` with `dontNpmBuild = true` → `npmDepsHash`
   - For python: `fetchzip` of the driver tarball per supported system → `driverHashes`
   - For each supported system, `fetchzip` of each per-browser CDN archive → `browsers.<name>.hashes.<system>`
6. Fetch `browsers.json` from `raw.githubusercontent.com/microsoft/playwright/<sha>/packages/playwright-core/browsers.json`. Filter to `installByDefault: true` and the browsers we have fetchers for.
7. Assemble the new pin JSON object with a single `jq -n ...` call (top-level fields + hash fragment + `browsers` object) and pipe into `write_pin_file "$package_version"`, which pretty-prints via `jq .` and atomically writes `pins/<tool>/<version>.json`.
8. Call `update_manifest "$package_version" "$is_latest"` to append the version to `pins/<tool>.json`'s `.versions` array and (when `is_latest=1`) move the `.latest` pointer.
9. `nix build .#playwright-<tool>-<version>` to verify the specific pin.
10. Commit: `git commit -m "<tool>: add <version>"`. No tag.

The update scripts are idempotent: if `pins/<tool>/<version>.json` already exists, they exit without making a commit.

## CI: scheduled backfill

`.github/workflows/sync.yml` runs on a schedule (once a day) and backfills every version that has been published since the last sync. It pushes commits **directly to `main`**, no PR.

The per-tool enumeration + update loop lives in `scripts/backfill.sh`:

1. `curl https://registry.npmjs.org/@playwright/<tool>` (or PyPI equivalent) → full list of published versions with publish times.
2. Read `pins/<tool>.json`'s `.versions` array as the set of already-processed versions.
3. Compute `missing = all_versions \ already_processed`. Include **every** version — `latest`, `next`, alpha, beta. Do not filter by dist-tag.
4. The registry JSON is already sorted by publish time; `jq` preserves that order.
5. For each missing version, in order, run `./update-<tool>.sh <version>`. The update script builds and commits.
6. On any failure: **fail the workflow immediately**, do not continue to later versions. A human investigates before more versions pile up.

The workflow runs `scripts/backfill.sh cli`, then `mcp`, then `python`, then `git push origin HEAD:main`. Permissions: `contents: write`. It uses the default `GITHUB_TOKEN`; push-protection rules on `main` must allow that identity.

**Initial seeding is not done by the workflow.** The repo's first commit is manually prepared at the current `latest` version of each tool so the first scheduled run has no history to recreate. The workflow only backfills versions published *after* that initial set.

## Maintenance

Everyday operation is CI-driven. Manual bumps are also supported: run `./update-<tool>.sh [version]` locally, verify, commit, push.

To retrigger a failed sync for a specific version: delete the half-written `pins/<tool>/<version>.json` (if any) and re-run the workflow, or run `./update-<tool>.sh <version>` manually.

## NixOS notes

- `--browser=chrome` (branded Chrome) is out of scope: the resolver hardcodes `/opt/google/chrome/chrome` with no env override. Use `--browser=chromium`.
- Newer webkit revisions (2276+) link against `libhyphen.so.0`, so `lib/browsers/webkit.nix` adds `hyphen` to its `buildInputs`. Older pins that don't need it still build fine.
- **aarch64 only**: the `node` binary bundled inside the PyPI driver tarball segfaults on NixOS aarch64 even after `autoPatchelfHook`. `pkgs/playwright-python.nix` works around this by setting `PLAYWRIGHT_NODEJS_PATH` to the nixpkgs `nodejs` executable in `postFixup`, which makes playwright-python's `_driver.py` use system node instead of the bundled one.
- Never run `make nix` or any NixOS rebuild from within this repo. Build with `nix build` only.

## Reference

- **`pietdevries94/playwright-web-flake`** — the prior-art flake whose per-browser fetchers in `playwright-driver/` (`chromium.nix`, `firefox.nix`, `webkit.nix`, `ffmpeg.nix`, `chromium-headless-shell.nix`) we adapt into `lib/browsers/` with their license headers intact. Their flake tracks stable releases and builds `playwright-core` from source; we track per-package nightly pins from npm/PyPI and build each tool's own source with `buildNpmPackage` / `buildPythonPackage`.
- **`playwright-core/src/server/registry/index.ts`** — the `${name.replace(/-/g, '_')}-${revision}` join is the constraint this whole flake works around.
- **npm registry JSON API** (`registry.npmjs.org`) — for `dependencies.playwright`, `gitHead`, and full version lists with publish times.
- **PyPI JSON API** (`pypi.org/pypi/<pkg>/json`) — for Python `playwright` version metadata.
