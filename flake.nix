{
  description = "Playwright tools (cli, mcp, python) bundled with revision-matched browsers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    # Linux only. CDN URL patterns, patchelfHooks, and prefetched hashes in
    # each pin file assume Linux (ubuntu-22.04 archives) on x86_64 or aarch64.
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          packages = import ./packages.nix { inherit pkgs; };
        }
      );
}
