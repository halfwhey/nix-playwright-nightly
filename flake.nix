{
  description = "Playwright tools (cli, mcp, python) bundled with revision-matched browsers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  nixConfig = {
    download-buffer-size = 100000000;
    extra-substituters = [
      "https://nix-community.cachix.org?priority=20"
      "https://halfwhey.cachix.org?priority=20"
      "https://cache.nixos.org?priority=30"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "halfwhey.cachix.org-1:6PtY2HXdJg8gVVe/uyWGqeWXg1cjfQEIi514Gsk4EeI="
    ];
  }; # 100mb

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
