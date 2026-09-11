# Worklog

Project work is recorded here after implementation and verification.

## 2026-08-30 — Self-healing browser-cache push

Summary: moved the browser-cache push decision into
`push-latest-browsers.sh`, comparing each evaluated latest browser output with
its public Cachix pin. Added fail-open handling for unavailable/malformed pin
state, `FORCE=1`, a non-mutating `--dry-run`, and unconditional all-tool cache
reconciliation in every `sync.yml` runner job. Added project guidance and
updated the public cache/sync documentation.

Changed paths:

- `.github/workflows/sync.yml`
- `CLAUDE.md`
- `README.md`
- `docs/worklog.md`
- `scripts/push-latest-browsers.sh`

Checks run sequentially:

- Pass: `bash -n` and `shellcheck` on `scripts/push-latest-browsers.sh`.
- Pass: real-API `--dry-run`; cli, dotnet, mcp, node, and python were all
  reported stale on aarch64-linux without any build/push/pin.
- Pass: forced dry-run reported `force enabled -> push`.
- Pass: unreachable `CACHIX_API_URL` dry-run reported
  `cache state unknown (...) -> push`.
- Pass: `nix run nixpkgs#actionlint -- nix/projects/playwright/.github/workflows/sync.yml`.
- Pass: `nix flake check ./nix/projects/playwright`.
- Pass: `git diff --check`.
- Partial: `nix run .#repoctl -- check` passed repository formatting and Nix
  checks, then stopped at the pre-existing frozen Python dependency check
  because root `uv.lock` needs an update after the exclude-newer span changed
  from `P7D` to `P14D`. No Python or lockfile files were changed for this task.

Remaining concerns: the public Cachix pins remain stale until a maintainer runs
the sync workflow (or an equivalent authorized push). No Cachix mutation or
workflow dispatch was performed. The unrelated root `uv.lock` mismatch still
prevents the full repository check from completing.

## 2026-09-11 — Resolve npm releases without gitHead

The scheduled sync run 34577476503 failed on CLI 0.1.19 because npm omitted
`gitHead`. MCP 0.0.80 and their Playwright 1.63.0-alpha-2026-08-31 dependency
also lack that field. CLI/MCP now resolve missing source SHAs from release tags
(including annotated tags) and verify source package names, versions, and
runtime dependencies against npm. CLI, MCP, Node.js, and Python now read browser
metadata from the exact published playwright-core tarball, validating its
identity and browser manifest. No alpha tag or informational source SHA is
required for browser resolution.

Added offline regression tests to both workflows and documented the compatible
pin metadata change. Generated pins were not changed.

Validation:

- Passed live resolution of CLI 0.1.19 and MCP 0.0.80 and extraction of the
  1.63.0-alpha-2026-08-31 browser manifest.
- Passed offline regression tests for gitHead, missing gitHead, lightweight and
  annotated tags, missing/invalid SHAs, source mismatches, and invalid manifests.
- Passed ShellCheck, workflow actionlint, project flake check, repository lint,
  the full `nix run .#repoctl -- check`, and `git diff --check`.

Publication, full sync builds, Cachix mutations, and workflow dispatch were not
performed. The remote workflow needs the source changes published before it can
use this fix.

## 2026-09-12 — Include Camoufox in daily sync

Sync now updates Camoufox browser and Python wrapper pins before recording the
synchronized revision. The ARM Linux job builds and caches both `camoufox` and
`camoufox-playwright-cli`, then reconciles the Camoufox browser pin alongside
Playwright. Explicit Bash pipeline failure handling prevents a failed build
from being hidden by a successful cache command. Other runners retain only
the packages supported on their platforms.

Validation: workflow actionlint, full `repoctl check`, and scoped
`git diff --check` passed. A live Camoufox cache dry run reported the missing
ARM Linux browser pin and selected a push without modifying Cachix.

## 2026-09-12 — Add Camoufox on Apple Silicon

Camoufox browser packaging now preserves the native signed macOS application
bundle, exposes its executable and Applications entry, and retains the layout
expected by the Python wrapper. Package outputs follow the platforms available
in each browser pin, so older Linux-only pins are excluded from Darwin.

The browser updater now fills missing platform assets in existing pins while
preserving existing hashes. It generated the Apple Silicon source for
152.0.4-beta.30. Both Camoufox updaters build on Apple Silicon, and the macOS sync
job builds/caches the wrappers, reconciles the browser pin, and smoke-tests a
headless launch through the bundled Python driver.

Validation: all-system flake evaluation, ShellCheck, workflow actionlint,
missing-platform pin generation, repeat-update no-op, and the ARM Linux browser
build passed. Native Apple Silicon build and launch validation runs in GitHub
Actions; this development machine is ARM Linux.
