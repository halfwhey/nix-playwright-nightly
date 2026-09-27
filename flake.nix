{
  description = "Playwright tools (cli, dotnet, mcp, node, python) bundled with revision-matched browsers";

  nixConfig = {
    extra-substituters = [ "https://halfwhey.cachix.org" ];
    extra-trusted-public-keys = [
      "halfwhey.cachix.org-1:6PtY2HXdJg8gVVe/uyWGqeWXg1cjfQEIi514Gsk4EeI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    # ARM only: aarch64 Linux plus Apple Silicon macOS. x86_64-linux was
    # dropped on 2026-09-27; older pins may still carry its hashes.
    flake-utils.lib.eachSystem
      [
        "aarch64-linux"
        "aarch64-darwin"
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
