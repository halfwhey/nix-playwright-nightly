# buildPythonPackage wrapper for PyPI playwright (microsoft/playwright-python),
# bundled with the official JS driver from the platform-specific PyPI wheel and
# the revision-matched browsers from this flake's Python pin.
#
# Older pins without driverUrls retain the legacy standalone driver-archive
# path. Each source ships its own Node binary, which we replace with nixpkgs'.
{
  lib,
  stdenv,
  python3Packages,
  fetchFromGitHub,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  nodejs,
}:
{
  version,
  driverVersion ? version,
  srcHash,
  driverUrls ? null,
  driverHashes,
  browsers,
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-python: unsupported system ${system}";
  driverSourceIsWheel = driverUrls != null;
  driverZipName =
    {
      x86_64-linux = "linux";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "mac-arm64";
    }
    .${system} or throwSystem;

  # Pre-built JS driver tarball: ships node + playwright-core JS code.
  # Layout (matches what playwright-python's _driver.py expects):
  #   ./node             -- bundled node binary (we replace with nixpkgs nodejs)
  #   ./package/cli.js   -- playwright-core entry point
  #   ./LICENSE
  driver = stdenv.mkDerivation {
    pname = "playwright-driver";
    version = driverVersion;

    src = fetchzip {
      url =
        if driverSourceIsWheel then
          driverUrls.${system} or throwSystem
        else
          "https://cdn.playwright.dev/builds/driver/${lib.optionalString (lib.hasInfix "-" driverVersion) "next/"}playwright-${driverVersion}-${driverZipName}.zip";
      stripRoot = false;
      hash = driverHashes.${system} or throwSystem;
    };

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      ${if driverSourceIsWheel then "cp -R playwright/driver/. $out/" else "cp -R . $out/"}
      # Replace the bundled node with nixpkgs nodejs. The bundled aarch64
      # node segfaults on NixOS after autoPatchelfHook (likely a glibc or
      # stack-guard mismatch), and even on x86_64 the nixpkgs binary is the
      # only one we can count on. playwright-python's _driver.py looks for
      # ./driver/node next to the package, so swapping this symlink fixes
      # both CLI callers and library callers (`from playwright.sync_api
      # import sync_playwright`) without needing PLAYWRIGHT_NODEJS_PATH.
      rm -f $out/node
      ln -s ${lib.getExe nodejs} $out/node
      runHook postInstall
    '';
  };
in
python3Packages.buildPythonPackage {
  pname = "playwright";
  inherit version;
  pyproject = true;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-python";
    rev = "v${version}";
    hash = srcHash;
  };

  postPatch = ''
    # Setup.py would download the driver from CDN at build time; we've already
    # fetched and patched it via the `driver` derivation above. Stub it out and
    # relax the build deps.
    sed -i -E \
      -e 's/, "auditwheel==[0-9]+(\.[0-9]+)*"//g' \
      -e 's/"setuptools-scm==[0-9]+(\.[0-9]+)*"/"setuptools-scm"/g' \
      -e 's/"setuptools==[0-9]+(\.[0-9]+)*"/"setuptools"/g' \
      -e 's/"wheel==[0-9]+(\.[0-9]+)*"/"wheel"/g' \
      pyproject.toml
    rm setup.py
  '';

  nativeBuildInputs = [ makeWrapper ];

  build-system = with python3Packages; [
    setuptools
    setuptools-scm
  ];

  pythonRelaxDeps = [
    "greenlet"
    "pyee"
  ];

  dependencies = with python3Packages; [
    greenlet
    pyee
  ];

  doCheck = false;
  pythonImportsCheck = [ "playwright" ];

  postInstall = ''
    # Embed the pre-fetched driver into the installed package so the python
    # _driver.py finds ./driver/package/cli.js next to its own files.
    mkdir -p $out/${python3Packages.python.sitePackages}/playwright/driver
    cp -R ${driver}/. $out/${python3Packages.python.sitePackages}/playwright/driver/

    # Bake PLAYWRIGHT_BROWSERS_PATH and PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD into
    # the package's __init__.py. `wrapProgram` only wraps the `playwright`
    # CLI; library consumers (`from playwright.sync_api import ...`) never
    # go through that wrapper, so without this injection they'd look for
    # browsers under ~/.cache/ms-playwright. `setdefault` preserves any
    # value the user has already set in their own environment.
    init=$out/${python3Packages.python.sitePackages}/playwright/__init__.py
    {
      echo "import os as _nix_os"
      echo "_nix_os.environ.setdefault('PLAYWRIGHT_BROWSERS_PATH', '${browsers}')"
      echo "_nix_os.environ.setdefault('PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD', '1')"
      echo "del _nix_os"
      cat $init
    } > $init.new && mv $init.new $init
  '';

  postFixup = ''
    wrapProgram $out/bin/playwright \
      --set PLAYWRIGHT_BROWSERS_PATH ${browsers} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1
  '';

  passthru = {
    inherit driver;
  };

  meta = {
    description = "playwright ${version} (PyPI) bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright-python";
    mainProgram = "playwright";
  };
}
