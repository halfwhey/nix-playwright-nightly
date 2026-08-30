# nix-playwright-nightly project guide

This directory is the canonical monorepo source for the standalone
`github.com/halfwhey/nix-playwright-nightly` flake. Work here, not in a
standalone projection. Preserve unrelated changes in the surrounding worktree.

## Layout

- `flake.nix` and `packages.nix` expose latest and versioned tool and browser
  packages for x86_64-linux, aarch64-linux, and aarch64-darwin.
- `pins/pin.json` selects each tool's latest version; `pins/<tool>/` contains
  generated, version-specific package and browser metadata. Do not hand-edit
  generated pins.
- `lib/` builds revision-matched browser sets, and `pkgs/` wraps the CLI, MCP,
  Node.js, .NET, Python, and Camoufox packages.
- `scripts/update-*.sh` resolve upstream releases, generate and stage pins,
  build the new version, and commit it. Re-running an existing pin is a no-op.
- `scripts/push-latest-browsers.sh` reconciles evaluated latest browser output
  paths with public Cachix pins. Matching paths are skipped; missing, stale, or
  unknown cache state is pushed and pinned. `--dry-run` reports decisions
  without building or changing Cachix; `FORCE=1` bypasses comparison.
- `.github/workflows/sync.yml` runs daily/manual upstream updates, reconciles all
  Playwright browser pins on every supported runner, then pushes generated
  commits. Follow-up architecture jobs use the synchronized commit SHA.
  `.github/workflows/ci.yml` is the manually dispatched flake/smoke-test flow.
- `docs/` contains project-local work records.

## Validation

Run focused checks first and expensive checks sequentially:

```sh
bash -n scripts/push-latest-browsers.sh
shellcheck scripts/push-latest-browsers.sh
nix flake check ./nix/projects/playwright
nix run .#repoctl -- lint
nix run .#repoctl -- check
```

Run root-relative commands from the monorepo root. `nix run .#repoctl -- check`
is the final repository gate. A cache decision can be exercised safely from
this directory with:

```sh
./scripts/push-latest-browsers.sh --dry-run halfwhey 1 cli dotnet mcp node python
```

Do not use Cachix push/pin operations or dispatch GitHub workflows as
validation; those are explicit user actions. Likewise, publication of the
standalone subtree is a user action after review.
