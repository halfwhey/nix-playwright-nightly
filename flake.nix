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
    # Linux plus Apple Silicon macOS. Darwin browser archives are currently
    # pinned against the GitHub Actions macOS 15 arm64 runner image.
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
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
