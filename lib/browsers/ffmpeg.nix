# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/ffmpeg.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` is an attrset keyed by system, not hardcoded.
#   - Supports x86_64-linux, aarch64-linux, and aarch64-darwin.
{
  stdenv,
  fetchzip,
}:
{
  revision,
  hashes,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/ffmpeg: unsupported system ${system}";
  archSuffix =
    {
      x86_64-linux = "linux";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "mac-arm64";
    }
    .${system} or throwSystem;
in
fetchzip {
  url = "https://cdn.playwright.dev/builds/ffmpeg/${revision}/ffmpeg-${archSuffix}.zip";
  stripRoot = false;
  hash = hashes.${system} or throwSystem;
}
