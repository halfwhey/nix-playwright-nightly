# Adapted from pietdevries94/playwright-web-flake
# https://github.com/pietdevries94/playwright-web-flake/blob/main/playwright-driver/webkit.nix
# Licensed under the MIT License (same as upstream).
#
# Changes from upstream:
#   - `hashes` is an attrset keyed by system, not hardcoded.
#   - Supports x86_64-linux, aarch64-linux, and aarch64-darwin.
{
  lib,
  stdenv,
  fetchzip,
  fetchFromGitHub,
  fetchpatch,
  makeWrapper,
  autoPatchelfHook,
  patchelfUnstable,
  libjxl,
  brotli,
  at-spi2-atk,
  cairo,
  flite,
  fontconfig,
  freetype,
  glib,
  glib-networking,
  enchant,
  gst_all_1,
  harfbuzz,
  harfbuzzFull,
  hyphen,
  icu70,
  lcms,
  libavif,
  libbacktrace,
  libdrm,
  libepoxy,
  libevent,
  libgcc,
  libgcrypt,
  libgpg-error,
  libjpeg8,
  libopus,
  libpng,
  libsoup_3,
  libtasn1,
  libvpx,
  libwebp,
  libwpe,
  libwpe-fdo,
  libxkbcommon,
  libxml2,
  libxslt,
  libgbm,
  sqlite,
  systemdLibs,
  wayland-scanner,
  woff2,
  zlib,
}:
{
  revision,
  hashes,
  ...
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-browsers/webkit: unsupported system ${system}";
  archSuffix =
    {
      x86_64-linux = "ubuntu-22.04";
      aarch64-linux = "ubuntu-22.04-arm64";
      # Upstream maps the mac26-arm64 host platform to the mac-15-arm64
      # WebKit artifact for the currently pinned revisions.
      aarch64-darwin = "mac-15-arm64";
    }
    .${system} or throwSystem;

  libvpx' = libvpx.overrideAttrs (
    finalAttrs: previousAttrs: {
      version = "1.12.0";
      src = fetchFromGitHub {
        owner = "webmproject";
        repo = finalAttrs.pname;
        rev = "v${finalAttrs.version}";
        sha256 = "sha256-9SFFE2GfYYMgxp1dpmL3STTU2ea1R5vFKA1L0pZwIvQ=";
      };
    }
  );
  libavif' = libavif.overrideAttrs (
    finalAttrs: previousAttrs: {
      version = "0.9.3";
      src = fetchFromGitHub {
        owner = "AOMediaCodec";
        repo = finalAttrs.pname;
        rev = "v${finalAttrs.version}";
        hash = "sha256-ME/mkaHhFeHajTbc7zhg9vtf/8XgkgSRu9I/mlQXnds=";
      };
      postPatch = "";
      patches = [ ];
    }
  );
  libjxl' = libjxl.overrideAttrs (
    finalAttrs: previousAttrs: {
      version = "0.8.2";
      src = fetchFromGitHub {
        owner = "libjxl";
        repo = "libjxl";
        rev = "v${finalAttrs.version}";
        hash = "sha256-I3PGgh0XqRkCFz7lUZ3Q4eU0+0GwaQcVb6t4Pru1kKo=";
        fetchSubmodules = true;
      };
      patches = [
        # Missing <atomic> include for gcc on RISCV — https://github.com/libjxl/libjxl/pull/2211
        (fetchpatch {
          url = "https://github.com/libjxl/libjxl/commit/22d12d74e7bc56b09cfb1973aa89ec8d714fa3fc.patch";
          hash = "sha256-X4fbYTMS+kHfZRbeGzSdBW5jQKw8UN44FEyFRUtw0qo=";
        })
      ];
      postPatch = ''
        # Fix multiple-definition errors by bumping to C++17.
        substituteInPlace CMakeLists.txt \
          --replace "set(CMAKE_CXX_STANDARD 11)" "set(CMAKE_CXX_STANDARD 17)"
        # Fix the build with CMake 4.
        substituteInPlace third_party/sjpeg/CMakeLists.txt \
          --replace-fail \
            'cmake_minimum_required(VERSION 2.8.7)' \
            'cmake_minimum_required(VERSION 3.5...3.10)'
      '';
      postInstall = "";
      cmakeFlags = [
        "-DJPEGXL_FORCE_SYSTEM_BROTLI=ON"
        "-DJPEGXL_FORCE_SYSTEM_HWY=ON"
        "-DJPEGXL_FORCE_SYSTEM_GTEST=ON"
      ]
      ++ lib.optionals stdenv.hostPlatform.isStatic [
        "-DJPEGXL_STATIC=ON"
      ]
      ++ lib.optionals stdenv.hostPlatform.isAarch32 [
        "-DJPEGXL_FORCE_NEON=ON"
      ];
    }
  );
in
if stdenv.hostPlatform.isDarwin then
  stdenv.mkDerivation {
    name = "playwright-webkit-${revision}";

    src = fetchzip {
      url = "https://cdn.playwright.dev/builds/webkit/${revision}/webkit-${archSuffix}.zip";
      stripRoot = false;
      hash = hashes.${system} or throwSystem;
    };

    buildPhase = ''
      cp -R . $out
    '';
  }
else
  stdenv.mkDerivation {
    name = "playwright-webkit-${revision}";

    src = fetchzip {
      url = "https://cdn.playwright.dev/builds/webkit/${revision}/webkit-${archSuffix}.zip";
      stripRoot = false;
      hash = hashes.${system} or throwSystem;
    };

    nativeBuildInputs = [
      autoPatchelfHook
      patchelfUnstable
      makeWrapper
    ];

    buildInputs = [
      at-spi2-atk
      cairo
      flite
      fontconfig.lib
      freetype
      glib
      enchant
      brotli
      libjxl'
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-base
      gst_all_1.gstreamer
      harfbuzz
      harfbuzzFull
      hyphen
      icu70
      lcms
      libavif'
      libbacktrace
      libdrm
      libepoxy
      libevent
      libgcc.lib
      libgcrypt
      libgpg-error
      libjpeg8
      libopus
      libpng
      libsoup_3
      libtasn1
      libwebp
      libwpe
      libwpe-fdo
      libvpx'
      libxml2
      libxslt
      libgbm
      sqlite
      systemdLibs
      wayland-scanner
      woff2.lib
      libxkbcommon
      zlib
    ];

    patchelfFlags = [ "--no-clobber-old-sections" ];

    buildPhase = ''
      cp -R . $out

      # Drop unused gtk minibrowser and bundled system libs.
      rm -rf $out/minibrowser-gtk
      rm -rf $out/minibrowser-wpe/sys

      wrapProgram $out/minibrowser-wpe/bin/MiniBrowser \
        --prefix GIO_EXTRA_MODULES ":" "${glib-networking}/lib/gio/modules/" \
        --prefix LD_LIBRARY_PATH ":" $out/minibrowser-wpe/lib
    '';

    preFixup = ''
      # Fix libxml2 breakage. See https://github.com/NixOS/nixpkgs/pull/396195#issuecomment-2881757108
      mkdir -p "$out/lib"
      ln -s "${lib.getLib libxml2}/lib/libxml2.so" "$out/lib/libxml2.so.2"
    '';
  }
