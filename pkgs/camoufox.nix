{
  lib,
  stdenv,
  fetchzip,
  wrapGAppsHook3,
  autoPatchelfHook,
  patchelfUnstable,
  alsa-lib,
  curl,
  dbus-glib,
  gtk3,
  libxtst,
  libva,
  pciutils,
  pipewire,
  adwaita-icon-theme,
}:
{
  version,
  tag,
  sources,
}:

let
  binaryName = "camoufox";
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "camoufox: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "camoufox";
  inherit version;

  src = fetchzip {
    url = source.url or "https://github.com/daijro/camoufox/releases/download/${tag}/camoufox-${version}-${source.suffix}.zip";
    stripRoot = false;
    hash = source.hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    wrapGAppsHook3
    autoPatchelfHook
    patchelfUnstable
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    gtk3
    adwaita-icon-theme
    alsa-lib
    dbus-glib
    libxtst
  ];

  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    curl
    libva.out
    pciutils
  ];

  appendRunpaths = lib.optionals stdenv.hostPlatform.isLinux [
    "${pipewire}/lib"
  ];

  # Firefox relrhack needs newer patchelf's no-clobber behavior.
  patchelfFlags = lib.optionals stdenv.hostPlatform.isLinux [ "--no-clobber-old-sections" ];

  installPhase = ''
    runHook preInstall

    installDir="$out/lib/camoufox-${version}"
    mkdir -p "$installDir" "$out/bin"
    cp -R . "$installDir/"
    chmod +x "$installDir/camoufox" "$installDir/camoufox-bin" "$installDir/v4l2test"
    ln -s "$installDir/${binaryName}" "$out/bin/${binaryName}"

    runHook postInstall
  '';

  meta = {
    description = "Custom Firefox-based browser for real browser fingerprint spoofing";
    homepage = "https://github.com/daijro/camoufox";
    license = lib.licenses.mpl20;
    platforms = builtins.attrNames sources;
    mainProgram = binaryName;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
