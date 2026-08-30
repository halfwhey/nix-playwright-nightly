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
