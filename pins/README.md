Pin data for each tool lives here. Every file is machine-managed by `./update-cli.sh`, `./update-mcp.sh`, and `./update-python.sh` at the repo root. Do not hand-edit; any manual change will be lost on the next sync run.

Layout: `pins/<tool>.json` is the manifest, with shape `{ "latest": "<v>", "versions": ["<v>", ...] }`. Per-version pin data lives in `pins/<tool>/<version>.json`. The manifest is authoritative for what versions exist and which one is latest; `packages.nix` reads it to enumerate every versioned output.
