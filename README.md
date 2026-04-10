# nix-playwright-nightly

Pure-Nix flake packaging `@playwright/cli`, `@playwright/mcp`, and PyPI `playwright`, each bundled with the exact browser revisions its `playwright-core` requires. No runtime downloads, no `PLAYWRIGHT_BROWSERS_PATH` wiring, no matching-flake hunting.

Supported systems: `x86_64-linux`, `aarch64-linux`.

## Why

Playwright's browser resolver looks for an exact `${name}-${revision}` directory under `PLAYWRIGHT_BROWSERS_PATH`. The revision is hardcoded per-browser in `browsers.json` inside each `playwright-core` release. If the directory was built from a different playwright revision, playwright treats the browser as missing and tries to download it.

`@playwright/cli`, `@playwright/mcp`, and PyPI `playwright` release on independent cadences and regularly pin different `playwright-core` versions at the same moment. nixpkgs's `playwright-driver.browsers` almost never matches any of them. This flake builds a separate browser set per consumer and bakes the right one into each wrapper.

Traced 2026-04-06:

| Consumer           | Latest | playwright-core pinned         | chromium | webkit |
| ------------------ | ------ | ------------------------------ | -------- | ------ |
| `@playwright/cli`  | 0.1.5  | 1.60.0-alpha-1775237291000     | 1219     | 2276   |
| `@playwright/mcp`  | 0.0.70 | 1.60.0-alpha-1774999321000     | 1217     | 2272   |
| pypi `playwright`  | 1.58.0 | 1.58.0 (separate repo)         | 1208     | 2248   |

## Usage

Pin `main` once and pick the version per tool via the package attribute name:

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
            playwright.packages.${system}.playwright-cli             # latest
            playwright.packages.${system}."playwright-mcp-0.0.70"    # pinned
            playwright.packages.${system}."playwright-python-1.58.0" # pinned
          ];
        };
    };
}
```

List available versions:


```bash 
❯ nix flake show github:halfwhey/nix-playwright-nightly
github:halfwhey/nix-playwright-nightly/e4c4cc73a33bdcb7e9dfcec629d2bbdf72d9fe4c?narHash=sha256-E7QaKOo/LIlyBufQBsoaxtJLEqtRkyLuS%2Btd/vJClAM%3D
└───packages
    ├───aarch64-linux
    │   ├───default: package 'playwright-cli-0.1.6'
    │   ├───playwright-cli: package 'playwright-cli-0.1.6'
    │   ├───playwright-cli-0_1_5: package 'playwright-cli-0.1.5'
    │   ├───playwright-cli-0_1_5-browsers: package 'playwright-browsers'
    │   ├───playwright-cli-0_1_6: package 'playwright-cli-0.1.6'
    │   ├───playwright-cli-0_1_6-browsers: package 'playwright-browsers'
    │   ├───playwright-cli-browsers: package 'playwright-browsers'
    │   ├───playwright-mcp: package 'playwright-mcp-0.0.70'
    │   ├───playwright-mcp-0_0_70: package 'playwright-mcp-0.0.70'
    │   ├───playwright-mcp-0_0_70-browsers: package 'playwright-browsers'
    │   ├───playwright-mcp-browsers: package 'playwright-browsers'
    │   ├───playwright-python: package 'python3.13-playwright-1.58.0'
    │   ├───playwright-python-1_58_0: package 'python3.13-playwright-1.58.0'
    │   ├───playwright-python-1_58_0-browsers: package 'playwright-browsers'
    │   └───playwright-python-browsers: package 'playwright-browsers'
    └───x86_64-linux
        ├───default omitted (use '--all-systems' to show)
        ├───playwright-cli omitted (use '--all-systems' to show)
        ├───playwright-cli-0_1_5 omitted (use '--all-systems' to show)
        ├───playwright-cli-0_1_5-browsers omitted (use '--all-systems' to show)
        ├───playwright-cli-0_1_6 omitted (use '--all-systems' to show)
        ├───playwright-cli-0_1_6-browsers omitted (use '--all-systems' to show)
        ├───playwright-cli-browsers omitted (use '--all-systems' to show)
        ├───playwright-mcp omitted (use '--all-systems' to show)
        ├───playwright-mcp-0_0_70 omitted (use '--all-systems' to show)
        ├───playwright-mcp-0_0_70-browsers omitted (use '--all-systems' to show)
        ├───playwright-mcp-browsers omitted (use '--all-systems' to show)
        ├───playwright-python omitted (use '--all-systems' to show)
        ├───playwright-python-1_58_0 omitted (use '--all-systems' to show)
        ├───playwright-python-1_58_0-browsers omitted (use '--all-systems' to show)
        └───playwright-python-browsers omitted (use '--all-systems' to show)
```

```sh
$ nix develop
$ playwright-cli --version    # latest cli
$ playwright-mcp --version    # 0.0.70
$ playwright --version        # 1.58.0
$ playwright-cli open --browser=chromium https://example.com
```

### Binary cache

Browser are included in the binary cache published to the public Cachix cache at

`https://halfwhey.cachix.org`.

Set it up once:

```sh
cachix use halfwhey
```

Or pass the cache and key explicitly for one-off builds:

```sh
nix build \
  --option extra-substituters https://halfwhey.cachix.org \
  --option extra-trusted-public-keys \
    'halfwhey.cachix.org-1:6PtY2HXdJg8gVVe/uyWGqeWXg1cjfQEIi514Gsk4EeI=' \
  github:halfwhey/nix-playwright-nightly#playwright-cli
```

### Versioned outputs

Every commit of `main` exposes all published versions side by side as flake attributes:

- `playwright-cli` / `playwright-mcp` / `playwright-python` alias to the current upstream latest.
- `playwright-cli-<version>` / `playwright-mcp-<version>` / `playwright-python-<version>` pin to that exact version.
- `playwright-<tool>-browsers` and `playwright-<tool>-<version>-browsers` expose the matching browser linkFarm for library users who embed playwright and set their own `PLAYWRIGHT_BROWSERS_PATH`.

Nix is lazy: referencing a single versioned attribute only evaluates that version's pin, so the per-version outputs have zero cost unless you actually realise them.

### Other patterns

- **Latest of everything** the default: pin `main` and reference `playwright-cli`, `playwright-mcp`, `playwright-python`. Main's HEAD always has the freshest aliases.
- **One-off** `nix run github:halfwhey/nix-playwright-nightly#playwright-cli-0.1.5 -- open https://example.com`
- **NixOS system package** `environment.systemPackages = [ inputs.playwright.packages.${pkgs.system}."playwright-cli-0.1.5" ];`
- **Browsers only** reference `playwright-<tool>-browsers` (latest) or `playwright-<tool>-<version>-browsers` (pinned) directly.

## What consumers do not need

- No `PLAYWRIGHT_BROWSERS_PATH` or `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` in their shell; every wrapper bakes these in.
- No `playwright install` / `bunx playwright install`.
- No `bun`, `npm`, `pip`, or `uv` on the host; every package is a pure-Nix derivation with no runtime network access.
- No separate browser flake.

## Packages

| Package                                                  | Wraps              | Release feed                          |
| -------------------------------------------------------- | ------------------ | ------------------------------------- |
| `packages.<system>.playwright-cli`                       | `@playwright/cli`  | `registry.npmjs.org/@playwright/cli`  |
| `packages.<system>."playwright-cli-<version>"`           | `@playwright/cli`  | per-version pin                       |
| `packages.<system>.playwright-mcp`                       | `@playwright/mcp`  | `registry.npmjs.org/@playwright/mcp`  |
| `packages.<system>."playwright-mcp-<version>"`           | `@playwright/mcp`  | per-version pin                       |
| `packages.<system>.playwright-python`                    | PyPI `playwright`  | `pypi.org/pypi/playwright/json`       |
| `packages.<system>."playwright-python-<version>"`        | PyPI `playwright`  | per-version pin                       |
| `packages.<system>.playwright-<tool>-browsers`           | browser linkFarm   | (passthrough, latest)                 |
| `packages.<system>."playwright-<tool>-<version>-browsers"` | browser linkFarm | (passthrough, per-version)            |

## Manual bumps

```sh
./scripts/update-cli.sh          # bump cli to latest on npm
./scripts/update-cli.sh 0.1.4    # bump cli to a specific version
./scripts/update-mcp.sh          # bump mcp to latest on npm
./scripts/update-python.sh       # bump python to latest on PyPI
```

Each script resolves the matching `playwright-core` version, prefetches every hash the pin needs, writes `pins/<tool>/<version>.json`, updates `pins/pin.json` (adding to the tool's `versions` array and moving `latest` when the version matches upstream), runs `nix build .#playwright-<tool>-<version>`, and commits the bump. Re-running with a version already present is a no-op.

CI runs the same update flow once a day against the current upstream latest for
each tool, then refreshes the public browser cache for both `x86_64-linux` and
`aarch64-linux`. See `.github/workflows/sync.yml`.

## Acknowledgement

- This flake adapts per-browser fetchers from [`pietdevries94/playwright-web-flake`](https://github.com/pietdevries94/playwright-web-flake). Adapted files under `lib/browsers/`.
- Thank you Cachix for hosting my binary cache for free.
