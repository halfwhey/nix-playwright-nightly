# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/firefox.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` is an attrset keyed by system, not hardcoded.
#   - Only x86_64-linux and aarch64-linux are supported.
{
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
    }
    .${system} or throwSystem;
in
stdenv.mkDerivation {
  name = "playwright-firefox-${revision}";

  src = fetchzip {
    url = "https://cdn.playwright.dev/builds/firefox/${revision}/firefox-${archSuffix}.zip";
    hash = hashes.${system} or throwSystem;
  };

  inherit (firefox-bin.unwrapped)
    nativeBuildInputs
    buildInputs
    runtimeDependencies
    appendRunpaths
    patchelfFlags
    ;

  buildPhase = ''
    mkdir -p $out/firefox
    cp -R . $out/firefox
  '';
}
