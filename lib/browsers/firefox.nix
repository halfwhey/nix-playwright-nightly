# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/firefox.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` is an attrset keyed by system, not hardcoded.
#   - Supports x86_64-linux, aarch64-linux, and aarch64-darwin.
{
  lib,
  stdenv,
  fetchzip,
  firefox-bin,
}:
{
  revision,
  hashes,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/firefox: unsupported system ${system}";
  archSuffix =
    {
      x86_64-linux = "ubuntu-22.04";
      aarch64-linux = "ubuntu-22.04-arm64";
      aarch64-darwin = "mac-arm64";
    }
    .${system} or throwSystem;
in
stdenv.mkDerivation {
  name = "playwright-firefox-${revision}";

  src = fetchzip {
    url = "https://cdn.playwright.dev/builds/firefox/${revision}/firefox-${archSuffix}.zip";
    stripRoot = !stdenv.hostPlatform.isDarwin;
    hash = hashes.${system} or throwSystem;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux firefox-bin.unwrapped.nativeBuildInputs;
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux firefox-bin.unwrapped.buildInputs;
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux firefox-bin.unwrapped.runtimeDependencies;
  appendRunpaths = lib.optionalString stdenv.hostPlatform.isLinux firefox-bin.unwrapped.appendRunpaths;
  patchelfFlags = lib.optionals stdenv.hostPlatform.isLinux firefox-bin.unwrapped.patchelfFlags;

  buildPhase = ''
    if [ "${toString stdenv.hostPlatform.isDarwin}" = 1 ]; then
      cp -R . $out
    else
      mkdir -p $out/firefox
      cp -R . $out/firefox
    fi
  '';
}
