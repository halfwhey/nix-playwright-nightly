# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/chromium-headless-shell.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` is an attrset keyed by system, not hardcoded.
#   - Supports x86_64-linux, aarch64-linux, and aarch64-darwin.
{
  lib,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  patchelfUnstable,
  alsa-lib,
  at-spi2-atk,
  expat,
  glib,
  libXcomposite,
  libXdamage,
  libXfixes,
  libXrandr,
  libgbm,
  libgcc,
  libxkbcommon,
  nspr,
  nss,
}:
{
  browserVersion,
  revision,
  hashes,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/chromium-headless-shell: unsupported system ${system}";

  src = fetchzip {
    url =
      {
        x86_64-linux = "https://cdn.playwright.dev/builds/cft/${browserVersion}/linux64/chrome-headless-shell-linux64.zip";
        aarch64-linux = "https://cdn.playwright.dev/builds/chromium/${revision}/chromium-headless-shell-linux-arm64.zip";
        aarch64-darwin = "https://cdn.playwright.dev/builds/cft/${browserVersion}/mac-arm64/chrome-headless-shell-mac-arm64.zip";
      }
      .${system} or throwSystem;
    stripRoot = false;
    hash = hashes.${system} or throwSystem;
  };
in
stdenv.mkDerivation {
  name = "playwright-chromium-headless-shell-${revision}";

  inherit src;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    patchelfUnstable
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    expat
    glib
    libXcomposite
    libXdamage
    libXfixes
    libXrandr
    libgbm
    libgcc.lib
    libxkbcommon
    nspr
    nss
  ];

  # Layout notes (playwright-core/src/server/registry/index.ts):
  #   linux-x64:   chrome-headless-shell-linux64/chrome-headless-shell
  #   linux-arm64: chrome-linux/headless_shell
  #   mac-arm64:   chrome-headless-shell-mac-arm64/chrome-headless-shell
  # Both zips already contain the expected top-level directory (stripRoot=false),
  # so a straight copy is all that's needed.
  buildPhase = ''
    cp -R . $out
  '';
}
