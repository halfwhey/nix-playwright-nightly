# nix-playwright-nightly

Nix flake packaging `@playwright/cli`, `@playwright/mcp`, Node.js `playwright`, and PyPI `playwright`, each bundled with the exact browser revisions its `playwright-core` requires. No runtime downloads, no `PLAYWRIGHT_BROWSERS_PATH` wiring needed.

Supported systems: `x86_64-linux`, `aarch64-linux`.

## Why

`@playwright/cli`, `@playwright/mcp`, Node.js `playwright`, and PyPI `playwright` release independently and regularly pin different `playwright-core` versions at the same moment. nixpkgs's `playwright-driver.browsers` almost never matches any of them. This flake builds a separate browser set per consumer and bakes the right one into each wrapper.

Refer to [pin.json](https://github.com/halfwhey/nix-playwright-nightly/blob/main/pins/pin.json) for the current version of each package.

## Usage

Add the input:

```nix
inputs.playwright.url = "github:halfwhey/nix-playwright-nightly";
```

Version segments use underscores because the Nix CLI parses dots as attribute path separators (`0.1.6` becomes `0_1_6`).

### `@playwright/cli`

```nix
playwright.packages.${system}.playwright-cli        # latest
playwright.packages.${system}.playwright-cli-0_1_6  # pinned
```

```sh
$ playwright-cli --version
$ playwright-cli open --browser=chromium https://example.com
$ playwright-cli codegen https://example.com
```

### `@playwright/mcp`

```nix
playwright.packages.${system}.playwright-mcp         # latest
playwright.packages.${system}.playwright-mcp-0_0_70  # pinned
```

Use as an MCP server:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "playwright-mcp"
    }
  }
}
```

### Node.js `playwright`

The package attribute is `playwright-node`, and the wrapped executable is also
named `playwright-node` to avoid colliding with PyPI `playwright`'s
`playwright` executable. When used as a shell package or build input, it also
adds its module tree to `NODE_PATH` so plain `node` can `require("playwright")`.

```nix
playwright.packages.${system}.playwright-node         # latest
playwright.packages.${system}.playwright-node-1_59_1  # pinned
```

```sh
$ playwright-node --version
$ node -e "const { chromium } = require('playwright'); console.log(typeof chromium)"
```

### PyPI `playwright`

```nix
playwright.packages.${system}.playwright-python          # latest
playwright.packages.${system}.playwright-python-1_58_0   # pinned
```

```sh
$ playwright --version
$ python -c "from playwright.sync_api import sync_playwright; print('ok')"
```

### Browsers only

For derivations that embed playwright and manage `PLAYWRIGHT_BROWSERS_PATH` themselves:

```nix
playwright.packages.${system}.playwright-cli-browsers              # latest
playwright.packages.${system}.playwright-mcp-0_0_70-browsers      # pinned
playwright.packages.${system}.playwright-node-1_59_1-browsers     # pinned
playwright.packages.${system}.playwright-python-1_58_0-browsers   # pinned
```

### Complete devShell example

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
            playwright.packages.${system}.playwright-cli
            playwright.packages.${system}.playwright-mcp-0_0_70
            playwright.packages.${system}.playwright-node
            playwright.packages.${system}.playwright-python-1_58_0
          ];
        };
    };
}
```

```sh
$ nix develop
$ playwright-cli open --browser=chromium https://example.com
$ playwright-mcp --version
$ playwright-node --version
$ playwright --version
```

### Other patterns

```sh
# one-off run
nix run github:halfwhey/nix-playwright-nightly#playwright-cli-0_1_5 -- open https://example.com

# list all available versions
nix flake show github:halfwhey/nix-playwright-nightly
```

```nix
# NixOS system package
environment.systemPackages = [ inputs.playwright.packages.${pkgs.system}.playwright-cli ];
```

## Binary cache

Browser closures are published to `https://halfwhey.cachix.org`. Set it up once:

```sh
cachix use halfwhey
```

Or pass it explicitly for a one-off build:

```sh
nix build \
  --option extra-substituters https://halfwhey.cachix.org \
  --option extra-trusted-public-keys \
    'halfwhey.cachix.org-1:6PtY2HXdJg8gVVe/uyWGqeWXg1cjfQEIi514Gsk4EeI=' \
  github:halfwhey/nix-playwright-nightly#playwright-cli
```

## Manual bumps

```sh
./scripts/update-cli.sh          # bump cli to latest on npm
./scripts/update-cli.sh 0.1.4    # bump cli to a specific version
./scripts/update-mcp.sh          # bump mcp to latest on npm
./scripts/update-node.sh         # bump node playwright to latest on npm
./scripts/update-python.sh       # bump python to latest on PyPI
```

Each script resolves the matching `playwright-core` version, prefetches all hashes, writes the pin file, and commits. Re-running with an already-pinned version is a no-op.

CI runs the same update flow once a day. See `.github/workflows/sync.yml`.

## Acknowledgement

- Per-browser fetchers under `lib/browsers/` are adapted from [`pietdevries94/playwright-web-flake`](https://github.com/pietdevries94/playwright-web-flake).
- Thank you Cachix for hosting my binary cache for free.
