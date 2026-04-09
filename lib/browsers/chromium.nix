# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/chromium.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` is an attrset keyed by system, not hardcoded.
#   - Only x86_64-linux and aarch64-linux are supported.
{
  stdenv,
  lib,
  fetchzip,
  makeWrapper,
  fontconfig_file,
  autoPatchelfHook,
  patchelf,
  alsa-lib,
  at-spi2-atk,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gobject-introspection,
  libGL,
  libgbm,
  libgcc,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pciutils,
  systemd,
  vulkan-loader,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxcb,
}:
{
  browserVersion,
  revision,
  hashes,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/chromium: unsupported system ${system}";

  # CDN URL structure differs by arch:
  #   x86_64-linux uses Google's chrome-for-testing (CFT) path keyed by browserVersion.
  #   aarch64-linux uses playwright's own builds keyed by revision.
  src = fetchzip {
    url =
      {
        x86_64-linux = "https://cdn.playwright.dev/builds/cft/${browserVersion}/linux64/chrome-linux64.zip";
        aarch64-linux = "https://cdn.playwright.dev/builds/chromium/${revision}/chromium-linux-arm64.zip";
      }
      .${system} or throwSystem;
    hash = hashes.${system} or throwSystem;
  };

  # Directory name playwright expects inside the browser dir, and which binary
  # inside it is launched. playwright-core/src/server/registry/index.ts:
  #   EXECUTABLE_PATHS.chromium = {
  #     'linux-x64': ['chrome-linux64', 'chrome'],
  #     'linux-arm64': ['chrome-linux', 'chrome'],
  #   }
  layoutDir =
    {
      x86_64-linux = "chrome-linux64";
      aarch64-linux = "chrome-linux";
    }
    .${system} or throwSystem;
in
stdenv.mkDerivation {
  name = "playwright-chromium-${revision}";

  inherit src;

  nativeBuildInputs = [
    autoPatchelfHook
    patchelf
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    atk
    cairo
    cups
    dbus
    expat
    glib
    gobject-introspection
    libgbm
    libgcc
    libxkbcommon
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    systemd
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxcb
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/${layoutDir}"
    cp -R . "$out/${layoutDir}"

    wrapProgram "$out/${layoutDir}/chrome" \
      --set-default SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
      --set-default FONTCONFIG_FILE ${fontconfig_file}

    runHook postInstall
  '';

  appendRunpaths = lib.makeLibraryPath [
    libGL
    vulkan-loader
    pciutils
  ];

  postFixup = ''
    # Replace the bundled vulkan-loader with the one we already add to RPATH.
    if [ -e "$out/${layoutDir}/libvulkan.so.1" ]; then
      rm "$out/${layoutDir}/libvulkan.so.1"
      ln -s -t "$out/${layoutDir}" "${lib.getLib vulkan-loader}/lib/libvulkan.so.1"
    fi
  '';
}
