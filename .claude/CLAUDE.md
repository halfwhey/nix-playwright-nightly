# nix-playwright-nightly

A Nix flake that packages `@playwright/cli`, `@playwright/mcp`, Node.js `playwright`, .NET `Microsoft.Playwright`, and PyPI `playwright` as pure-Nix derivations, each bundled with the exact browser revisions its `playwright-core` requires. Drop it into a flake input and use it: no env vars, no extra setup, no runtime browser downloads, no `npx`/`pip install` at runtime.

Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.

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
            playwright.packages.${system}.playwright-node          # latest node
            playwright.packages.${system}.playwright-dotnet        # latest dotnet
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
$ playwright-node --version             # latest node
$ playwright-dotnet --version           # latest dotnet
$ playwright --version                  # Version 1.58.0 (pypi)
$ playwright-cli open --browser=chromium https://example.com
# launches chromium without downloading
```

### Versioned outputs, no git tags

Every commit of `main` exposes all known versions side by side as flake attributes:

- `playwright-cli` / `playwright-mcp` / `playwright-node` / `playwright-dotnet` / `playwright-python` alias to the current upstream latest (the one `pins/pin.json`'s `.<tool>.latest` pointer names).
- `playwright-<tool>-<version>` is the same package pinned to the exact version you name. Because the Nix CLI parses `.` as an attrpath separator, the version segment uses underscores: `playwright-cli-0_1_5`, `playwright-mcp-0_0_70`, `playwright-node-1_59_1`, `playwright-dotnet-1_59_0`, `playwright-python-1_58_0`.
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
- Have `bun`, `npm`, `pip`, `uv`, or `dotnet` installed — every package is a pure-Nix derivation with no runtime network access.
- Pick a matching browser flake separately.
- Care that cli / mcp / node / dotnet / python disagree on browser revisions.

## Outputs

Each commit of `main` exposes a latest alias per tool plus one attribute per pinned version, and the same split for the browser passthroughs:

| Package | Wraps | Release feed |
|---|---|---|
| `packages.${system}.playwright-cli` | `@playwright/cli` (latest) | `registry.npmjs.org/@playwright/cli` |
| `packages.${system}."playwright-cli-<v>"` | `@playwright/cli` (pinned) | per-version pin |
| `packages.${system}.playwright-mcp` | `@playwright/mcp` (latest) | `registry.npmjs.org/@playwright/mcp` |
| `packages.${system}."playwright-mcp-<v>"` | `@playwright/mcp` (pinned) | per-version pin |
| `packages.${system}.playwright-node` | `playwright` (latest, npm) | `registry.npmjs.org/playwright` |
| `packages.${system}."playwright-node-<v>"` | `playwright` (pinned, npm) | per-version pin |
| `packages.${system}.playwright-dotnet` | `Microsoft.Playwright` (latest, NuGet) | `api.nuget.org/v3-flatcontainer/microsoft.playwright` |
| `packages.${system}."playwright-dotnet-<v>"` | `Microsoft.Playwright` (pinned, NuGet) | per-version pin |
| `packages.${system}.playwright-python` | PyPI `playwright` (latest) | `pypi.org/pypi/playwright/json` |
| `packages.${system}."playwright-python-<v>"` | PyPI `playwright` (pinned) | per-version pin |
| `packages.${system}.playwright-<tool>-browsers` | linkFarm of latest's browsers | passthrough |
| `packages.${system}."playwright-<tool>-<v>-browsers"` | linkFarm of pinned browsers | passthrough |

## The core problem this flake solves

Playwright's browser resolver (`playwright-core/src/server/registry/index.ts`) reads `PLAYWRIGHT_BROWSERS_PATH` and looks for an exact `${name.replace(/-/g, '_')}-${revision}` subdirectory. The revision is hardcoded per-browser in that playwright version's `browsers.json`. If the directory was built from a different playwright revision, playwright treats the browser as missing and tries to download it at runtime.

Each of the five upstream consumers releases on an independent cadence and regularly pins different `playwright-core` versions at the same moment. nixpkgs's `playwright-driver.browsers` almost never matches any of them. This flake builds a separate browser set per consumer and bakes the right one into each wrapper.

### This divergence is real, not hypothetical

Traced on 2026-04-06:

| Consumer | Latest version | `playwright-core` it pins | chromium | webkit | firefox | ffmpeg |
|---|---|---|---|---|---|---|
| `@playwright/cli` | 0.1.5 | 1.60.0-alpha-1775237291000 | 1219 | 2276 | 1511 | 1011 |
| `@playwright/mcp` | 0.0.70 | 1.60.0-alpha-1774999321000 | 1217 | 2272 | 1511 | 1011 |
| pypi `playwright` | 1.58.0 | stable 1.58.0 (separate repo) | (v1.58.0) | (v1.58.0) | (v1.58.0) | (v1.58.0) |

cli and mcp diverged on chromium (1219 vs 1217) and webkit (2276 vs 2272) even though both were `latest` at the same moment. Firefox and ffmpeg coincidentally matched — the Nix store dedupes those derivations across consumers for free. Node and dotnet were added later and exhibit the same divergence pattern against whichever stable/alpha `playwright-core` their latest release happened to pin.

## Repository layout

Single long-lived branch (`main`). Pin data lives in `pins/` (machine-managed): one manifest JSON for all tools plus a directory of per-version pin files per tool. Package wiring lives in `packages.nix`. `flake.nix` is thin boilerplate.

```
flake.nix                           # thin: inputs, outputs, system loop, imports ./packages.nix
packages.nix                        # reads the manifest, exposes versioned + latest attrs per tool
flake.lock
pins/
  pin.json                          # MANIFEST: { cli, mcp, node, dotnet, python } each: { latest, versions }
  cli/<version>.json                # per-version cli pin data (managed by scripts/update-cli.sh)
  mcp/<version>.json                # per-version mcp pin data
  node/<version>.json               # per-version node pin data
  dotnet/<version>.json             # per-version dotnet pin data
  python/<version>.json             # per-version python pin data
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
  playwright-node.nix               # stdenvNoCC wrapper over npm tarballs for `playwright` + `playwright-core`
  playwright-dotnet.nix             # stdenvNoCC wrapper over the NuGet .nupkg for Microsoft.Playwright
  playwright-python.nix             # buildPythonPackage wrapper for PyPI playwright
scripts/
  lib.sh                            # shared shell helpers (hash prefetch, JSON pin emitters)
  backfill.sh                       # enumerate missing versions and drive the update scripts (manual only)
  update-cli.sh                     # ./scripts/update-cli.sh [version]     default: latest on npm
  update-mcp.sh                     # ./scripts/update-mcp.sh [version]     default: latest on npm
  update-node.sh                    # ./scripts/update-node.sh [version]    default: latest on npm
  update-dotnet.sh                  # ./scripts/update-dotnet.sh [version]  default: latest on NuGet
  update-python.sh                  # ./scripts/update-python.sh [version]  default: latest on PyPI
  push-latest-browsers.sh           # build, push, and cachix-pin latest browser linkFarms per tool
.github/workflows/
  sync.yml                          # scheduled daily: update each tool's latest, push browser closures to cachix
  ci.yml                            # PR/push: nix flake check + smoke builds
README.md
CLAUDE.md                           # this file
```

This is a fresh project, not a fork. The per-browser fetchers under `lib/browsers/` are adapted from `pietdevries94/playwright-web-flake`'s `playwright-driver/` (keep their license headers). Everything else (the `pkgs/` derivations, the multi-pin JSON model, the update scripts, and the sync CI) is designed from scratch for this repo's per-package nightly tracking model.

## Pin file shape

### Manifest (`pins/pin.json`)

The manifest is authoritative for what versions exist and which one is latest. `packages.nix` reads it once with `builtins.fromJSON (builtins.readFile ./pins/pin.json)` and accesses each tool's sub-object (`pins.cli`, `pins.mcp`, `pins.node`, `pins.dotnet`, `pins.python`). `.versions` maps to versioned flake attributes; `.latest` picks which version backs the unversioned `playwright-<tool>` alias.

```json
{
  "cli":    { "latest": "0.1.7",  "versions": ["0.1.5", "0.1.6", "0.1.7"] },
  "mcp":    { "latest": "0.0.70", "versions": ["0.0.70"] },
  "node":   { "latest": "1.59.1", "versions": ["1.59.1"] },
  "dotnet": { "latest": "1.59.0", "versions": ["1.59.0"] },
  "python": { "latest": "1.58.0", "versions": ["1.58.0"] }
}
```

`versions` for each tool is appended to in publish-time order. `latest` moves only when the version being added matches the upstream `dist-tags.latest` / `info.version` / NuGet flatcontainer top entry.

### Per-version pin (`pins/<tool>/<version>.json`)

Each file holds the data needed to build one version of one tool. The `browsers` object is the same shape everywhere; the top-level fields differ per tool:

| Tool | Source | Top-level fields (besides `package`) |
|---|---|---|
| cli | `fetchFromGitHub microsoft/playwright-cli` + `buildNpmPackage` | `packageSha`, `playwrightVersion`, `playwrightSha`, `srcHash`, `npmDepsHash` |
| mcp | `fetchFromGitHub microsoft/playwright-mcp` + `buildNpmPackage` | `packageSha`, `playwrightVersion`, `playwrightSha`, `srcHash`, `npmDepsHash` |
| node | npm tarballs for `playwright` and `playwright-core` via `fetchzip` | `packageSha`, `playwrightVersion`, `playwrightSha`, `packageHash`, `coreHash` |
| dotnet | NuGet `.nupkg` via `fetchzip` | `packageHash` |
| python | `fetchFromGitHub microsoft/playwright-python` + bundled JS driver from `cdn.playwright.dev/builds/driver` | `playwrightVersion`, `playwrightSha`, `srcHash`, `driverHashes.{x86_64-linux,aarch64-linux,aarch64-darwin}` |

Shared fields:
- `packageSha` is the npm `gitHead` commit SHA for the tool's own repo; `fetchFromGitHub` uses it as `rev` instead of a version tag because pre-release alphas are published without tags.
- `playwrightSha` is the `microsoft/playwright` commit whose `browsers.json` defines the revisions baked into this pin.
- `browsers` is a map `{ chromium, chromium-headless-shell, firefox, webkit, ffmpeg }` → `{ revision, browserVersion, hashes: { <system>: "sha256-..." } }`. `ffmpeg` has no `browserVersion`.

Example (`pins/cli/0.1.7.json`):

```json
{
  "package": "0.1.7",
  "packageSha": "1a3b1f30ba72087a6cd8e102f39358ec888d210d",
  "playwrightVersion": "1.60.0-alpha-1775951570000",
  "playwrightSha": "c209a554903396eb1cb3fd6ddbd2150fdd464793",
  "srcHash": "sha256-...",
  "npmDepsHash": "sha256-...",
  "browsers": {
    "chromium": {
      "revision": "1219",
      "browserVersion": "147.0.7727.49",
      "hashes": {
        "x86_64-linux":   "sha256-...",
        "aarch64-linux":  "sha256-...",
        "aarch64-darwin": "sha256-..."
      }
    }
  }
}
```

### `packages.nix`

Each tool gets a small `mk<Tool>` constructor that extracts the fields it needs from the pin and calls its derivation. A shared `buildTool` helper expands the manifest into the `{versioned, versioned-browsers, latest, latest-browsers}` quadruple per tool.

```nix
{ pkgs }:
let
  mkBrowsers = pkgs.callPackage ./lib/mkBrowsers.nix { };
  readJSON = path: builtins.fromJSON (builtins.readFile path);

  mkCli    = pin: pkgs.callPackage ./pkgs/playwright-cli.nix    { } { version = pin.package; inherit (pin) packageSha srcHash npmDepsHash;  browsers = mkBrowsers pin.browsers; };
  mkMcp    = pin: pkgs.callPackage ./pkgs/playwright-mcp.nix    { } { version = pin.package; inherit (pin) packageSha srcHash npmDepsHash;  browsers = mkBrowsers pin.browsers; };
  mkNode   = pin: pkgs.callPackage ./pkgs/playwright-node.nix   { } { version = pin.package; inherit (pin) packageHash coreHash;           browsers = mkBrowsers pin.browsers; };
  mkDotnet = pin: pkgs.callPackage ./pkgs/playwright-dotnet.nix { } { version = pin.package; inherit (pin) packageHash;                    browsers = mkBrowsers pin.browsers; };
  mkPython = pin: pkgs.callPackage ./pkgs/playwright-python.nix { } { version = pin.package; inherit (pin) srcHash driverHashes;           browsers = mkBrowsers pin.browsers; };

  # Dots in the version segment would be parsed as attrpath separators by the
  # nix CLI (`.#playwright-cli-0.1.5` → three nested attrs), so we replace
  # them with underscores for the attribute name. The pin file on disk still
  # uses the dotted version.
  toAttr = v: builtins.replaceStrings [ "." ] [ "_" ] v;

  buildTool = { prefix, toolManifest, pinDir, mk }:
    let
      pinFor   = v: readJSON (pinDir + "/${v}.json");
      versionedPkgs     = map (v: { name = "${prefix}-${toAttr v}";          value = mk (pinFor v); }) toolManifest.versions;
      versionedBrowsers = map (v: { name = "${prefix}-${toAttr v}-browsers"; value = mkBrowsers (pinFor v).browsers; }) toolManifest.versions;
      latestPin = pinFor toolManifest.latest;
    in
    builtins.listToAttrs (versionedPkgs ++ versionedBrowsers) // {
      "${prefix}"          = mk latestPin;
      "${prefix}-browsers" = mkBrowsers latestPin.browsers;
    };

  pins = readJSON ./pins/pin.json;
in
  (buildTool { prefix = "playwright-cli";    toolManifest = pins.cli;    pinDir = ./pins/cli;    mk = mkCli;    })
  // (buildTool { prefix = "playwright-mcp";    toolManifest = pins.mcp;    pinDir = ./pins/mcp;    mk = mkMcp;    })
  // (buildTool { prefix = "playwright-node";   toolManifest = pins.node;   pinDir = ./pins/node;   mk = mkNode;   })
  // (buildTool { prefix = "playwright-dotnet"; toolManifest = pins.dotnet; pinDir = ./pins/dotnet; mk = mkDotnet; })
  // (buildTool { prefix = "playwright-python"; toolManifest = pins.python; pinDir = ./pins/python; mk = mkPython; })
  // { default = /* playwright-cli latest */; }
```

`flake.nix` itself is the thinnest possible wrapper: inputs, outputs, the `x86_64-linux` / `aarch64-linux` / `aarch64-darwin` system loop, and `packages = import ./packages.nix { inherit pkgs; };`.

### Package derivations

All five live in `pkgs/` and are `callPackage`-d with a pin-derived argument set. None of them fetch anything at runtime.

- **`pkgs/playwright-cli.nix`** — `buildNpmPackage` from `microsoft/playwright-cli` at `rev = packageSha`. `dontNpmBuild = true`. `postFixup` calls `wrapProgram $out/bin/playwright-cli --set PLAYWRIGHT_BROWSERS_PATH ${browsers} --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1`.
- **`pkgs/playwright-mcp.nix`** — `buildNpmPackage` from `microsoft/playwright-mcp`. mcp's repo is an npm workspace (`playwright-mcp-internal`) so the wrapped bin is not auto-exposed — a `postInstall` symlinks `$out/lib/node_modules/playwright-mcp-internal/packages/playwright-mcp/cli.js` to `$out/bin/playwright-mcp` before `wrapProgram`.
- **`pkgs/playwright-node.nix`** — `stdenvNoCC.mkDerivation` that `fetchzip`s the published `playwright` and `playwright-core` tarballs straight from `registry.npmjs.org`. Installs both to `$out/lib/node_modules/`, exposes `playwright-node` (renamed from `playwright` to avoid colliding with PyPI's binary), and wraps it with `NODE_PATH` and `PLAYWRIGHT_BROWSERS_PATH`.
- **`pkgs/playwright-dotnet.nix`** — `stdenvNoCC.mkDerivation` that `fetchzip`s the `Microsoft.Playwright.<v>.nupkg` from `api.nuget.org/v3-flatcontainer`. Installs `Microsoft.Playwright.dll` and the bundled `.playwright/` helper tree, ships a `playwright-dotnet` shim that invokes the upstream `playwright.ps1` driver via `powershell`, and wraps it with `PLAYWRIGHT_BROWSERS_PATH`. Needs `powershell` and `nodejs` from nixpkgs.
- **`pkgs/playwright-python.nix`** — `buildPythonPackage` (`pyproject = true`) from `microsoft/playwright-python` at `v<version>`. A nested `driver` derivation fetches the `playwright-${driverVersion}-<arch>.zip` JS-driver tarball from `cdn.playwright.dev/builds/driver` and runs it through `autoPatchelfHook`. `postPatch` strips `auditwheel`/`setuptools-scm` from `pyproject.toml` and removes the upstream `setup.py` (we provide the driver ourselves). `postInstall` copies the driver into `site-packages/playwright/driver/`. `postFixup` wraps the `playwright` binary with `PLAYWRIGHT_BROWSERS_PATH`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`, and **`PLAYWRIGHT_NODEJS_PATH = ${lib.getExe nodejs}`** — see NixOS notes.

Each wrapper sets `PLAYWRIGHT_BROWSERS_PATH` via `wrapProgram`, not via `shellHook`: multiple tools with different browser sets must coexist in one shell without clobbering each other's env.

## Version resolution chains

### cli, mcp (npm, source-built)

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

### node (npm, tarball-installed)

```
npm:playwright@<v>           .gitHead                         →  microsoft/playwright SHA
npm:playwright-core@<v>                                       →  coreHash (sibling tarball, same version)
raw.../microsoft/playwright/<sha>/packages/playwright-core/browsers.json
```

Node installs the published `playwright` and `playwright-core` tarballs side by side. We don't compile from source, but we still resolve `playwrightSha` so the baked-in `browsers.json` matches exactly what the tarballs expect.

### dotnet (NuGet)

```
api.nuget.org/v3-flatcontainer/microsoft.playwright/index.json  →  version list
.../microsoft.playwright.<v>.nupkg                              →  packageHash
```

The `.nupkg` bundles its own `.playwright/` helper directory with a stamped `browsers.json` — we parse that file directly to pick up revisions, skipping the npm chain entirely.

### python (PyPI)

Python's `playwright` package lives in `microsoft/playwright-python` (not `microsoft/playwright`) and hardcodes a `driver_version` in `setup.py`.

```
pypi.org/pypi/playwright/json                                →  PyPI version (e.g. 1.58.0)
raw.../microsoft/playwright-python/v<pypi>/setup.py          →  driver_version = "1.58.0"
npm:playwright@<driver> .gitHead                              →  microsoft/playwright SHA
raw.../microsoft/playwright/<sha>/packages/playwright-core/browsers.json
```

Note: beta drivers (e.g. `1.57.0-beta-...`) are not tagged in `microsoft/playwright`, so we resolve the SHA via npm `playwright@<driver>.gitHead` rather than `git ls-remote refs/tags/v<driver>`.

## Update scripts (`scripts/update-<tool>.sh`)

All five share the same shape. Differences are only in steps 1–3 (resolving the package → playwright SHA chain) and in which hash emitter they call. Shared helpers live in `scripts/lib.sh`.

```sh
./scripts/update-cli.sh            # bump to latest on npm
./scripts/update-cli.sh 0.1.4      # bump to specific version
```

Steps:

1. Resolve `upstream_latest` (npm `dist-tags.latest`, PyPI `info.version`, or NuGet flatcontainer last entry). Pick `package_version` from the CLI arg, or default to `upstream_latest`. Set `is_latest=1` when they match.
2. If `pins/<tool>/<package_version>.json` already exists on disk, exit immediately (idempotent).
3. Resolve `playwright_version` (npm `dependencies.playwright`, or PyPI → setup.py `driver_version`; dotnet skips this and reads `browsers.json` from inside the `.nupkg`).
4. Resolve `playwright_sha` (npm `gitHead` for cli/mcp/node/python; n/a for dotnet).
5. Prefetch hashes by invoking the dedicated nixpkgs prefetch tools directly (no `import <nixpkgs>`, no dummy-hash `nix-build` tricks). `scripts/lib.sh` re-execs the update script inside a `nix shell` populated from the **flake's own `flake.lock`** nixpkgs revision, so the prefetch tools are byte-identical to the ones `buildNpmPackage` / `fetchzip` will later consume the hashes with:
   - cli/mcp: `nix-prefetch-github microsoft <repo> --rev <sha>` → `srcHash`; `curl` the upstream `package-lock.json` and feed it to `prefetch-npm-deps` → `npmDepsHash`.
   - node: `fetchzip` each of `playwright-<v>.tgz` and `playwright-core-<v>.tgz` → `packageHash`, `coreHash`.
   - dotnet: `fetchzip` the `.nupkg` → `packageHash`.
   - python: `nix-prefetch-github microsoft playwright-python --rev v<version>` → `srcHash`; download + unzip the driver tarball per supported system and hash with `nix hash path --type sha256 --sri` → `driverHashes`.
   - For each supported system, prefetch each per-browser CDN archive. `stripRoot = true` browsers (chromium, firefox) use `nix-prefetch-url --unpack` + `nix hash convert --to sri`. `stripRoot = false` browsers (chromium-headless-shell, webkit, ffmpeg — see `strip_root_false` in `scripts/lib.sh`) go through the curl + unzip + `nix hash path` path → `browsers.<name>.hashes.<system>`.
6. Fetch `browsers.json` from `raw.githubusercontent.com/microsoft/playwright/<sha>/packages/playwright-core/browsers.json` (or from inside the `.nupkg` for dotnet). Filter to `installByDefault: true` and the browsers we have fetchers for.
7. Assemble the new pin JSON object with a single `jq -n ...` call (top-level fields + hash fragment + `browsers` object) and pipe into `write_pin_file "$package_version"`, which pretty-prints via `jq .` and atomically writes `pins/<tool>/<version>.json`.
8. Call `update_manifest "$package_version" "$is_latest"` to append the version to `pins/pin.json`'s `.<tool>.versions` array and (when `is_latest=1`) move `.<tool>.latest`.
9. `nix build .#playwright-<tool>-<version>` to verify the specific pin.
10. Commit: `git commit -m "<tool>: add <version>"`. No tag.

The update scripts are idempotent: if `pins/<tool>/<version>.json` already exists, they exit without making a commit.

## CI: scheduled latest-only sync

`.github/workflows/sync.yml` runs on a cron (daily at 03:17 UTC) and also supports `workflow_dispatch` with a `force_push_latest_browsers` flag. It pushes commits **directly to `main`**, no PR. Permissions: `contents: write`.

The job layout:

1. **`sync-latest`** (`ubuntu-latest`) checks out `main` and runs `./scripts/update-cli.sh`, then `update-mcp.sh`, `update-node.sh`, `update-dotnet.sh`, `update-python.sh` **without arguments**. Camoufox is intentionally excluded from scheduled sync and Cachix publishing because the browser closures are too large for the current pin budget. Each Playwright update script is a no-op if the current upstream latest is already pinned; otherwise it writes a new pin file, updates the manifest, builds the tool locally, and commits. A failure stops the workflow so a human can investigate before more versions pile up.
2. The same job then calls `scripts/push-latest-browsers.sh halfwhey 1 <changed-tools>` to push and cachix-pin the x86_64-linux browser linkFarms for every tool whose pin changed this run (or all five when `force_push_latest_browsers` is set).
3. **`push-arm-browser-cache`** (`ubuntu-24.04-arm`) and **`push-darwin-browser-cache`** (`macos-26`) both checkout the updated SHA and re-run `push-latest-browsers.sh` so the aarch64-linux and aarch64-darwin closures land in cachix under the same pin names.
4. Finally the first job does `git push origin HEAD:main` with the default `GITHUB_TOKEN`.

**This workflow only tracks upstream latest — it does not backfill historical versions.** `scripts/backfill.sh` exists and can enumerate every unpinned version from the registry, but it is invoked manually (not from CI). Use it when you deliberately want to import a range of older versions.

The binary cache is `halfwhey.cachix.org`. The workflow authenticates with `CACHIX_AUTH_TOKEN` (cachix-action is invoked with `skipPush: true`; pushes are explicit via `push-latest-browsers.sh`).

Do not add Camoufox back to the sync workflow or `push-latest-browsers.sh` calls unless the Cachix pin storage budget has been raised or a separate cache policy has been chosen.

## Maintenance

Everyday operation is CI-driven. Manual bumps are also supported: run `./scripts/update-<tool>.sh [version]` locally, verify, commit, push.

To retrigger a failed sync for a specific version: delete the half-written `pins/<tool>/<version>.json` (if any) and re-run the workflow, or run `./scripts/update-<tool>.sh <version>` manually.

## NixOS notes

- `--browser=chrome` (branded Chrome) is out of scope: the resolver hardcodes `/opt/google/chrome/chrome` with no env override. Use `--browser=chromium`.
- Newer webkit revisions (2276+) link against `libhyphen.so.0`, so `lib/browsers/webkit.nix` adds `hyphen` to its `buildInputs`. Older pins that don't need it still build fine.
- Webkit revisions (2285+) additionally link against `libbacktrace.so.0`, so `lib/browsers/webkit.nix` also adds `libbacktrace` to its `buildInputs`. When CI fails with `auto-patchelf could not satisfy dependency lib<X>.so` for a webkit revision, the upstream WebKit Linux build picked up a new transitive shared lib; add the corresponding nixpkgs package to `lib/browsers/webkit.nix`'s function args and `buildInputs` and re-run the failed sync.
- **aarch64 only**: the `node` binary bundled inside the PyPI driver tarball segfaults on NixOS aarch64 even after `autoPatchelfHook`. `pkgs/playwright-python.nix` works around this by setting `PLAYWRIGHT_NODEJS_PATH` to the nixpkgs `nodejs` executable in `postFixup`, which makes playwright-python's `_driver.py` use system node instead of the bundled one.
- **Darwin**: the upstream download registry still maps `aarch64-darwin` (`mac26-arm64` host) to the `webkit-mac-15-arm64` artifact; this flake mirrors that and the cachix push job runs on `macos-26`.
- Never run `make nix` or any NixOS rebuild from within this repo. Build with `nix build` only.

## Reference

- **`pietdevries94/playwright-web-flake`** — the prior-art flake whose per-browser fetchers in `playwright-driver/` (`chromium.nix`, `firefox.nix`, `webkit.nix`, `ffmpeg.nix`, `chromium-headless-shell.nix`) we adapt into `lib/browsers/` with their license headers intact. Their flake tracks stable releases and builds `playwright-core` from source; we track per-package nightly pins from npm/PyPI/NuGet and build (or repackage) each tool's own source with `buildNpmPackage` / `fetchzip` / `buildPythonPackage`.
- **`playwright-core/src/server/registry/index.ts`** — the `${name.replace(/-/g, '_')}-${revision}` join is the constraint this whole flake works around.
- **npm registry JSON API** (`registry.npmjs.org`) — for `dependencies.playwright`, `gitHead`, and full version lists with publish times.
- **PyPI JSON API** (`pypi.org/pypi/<pkg>/json`) — for Python `playwright` version metadata.
- **NuGet v3 flatcontainer** (`api.nuget.org/v3-flatcontainer/microsoft.playwright/`) — for `Microsoft.Playwright` version index and `.nupkg` downloads.
