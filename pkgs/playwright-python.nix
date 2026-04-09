# buildPythonPackage wrapper for PyPI playwright (microsoft/playwright-python),
# bundled with the official pre-built JS driver tarball and the revision-matched
# browsers from this flake's python pin.
#
# Driver tarball comes from cdn.playwright.dev/builds/driver. Each tarball ships
# its own bundled node binary, which we autoPatchelfHook for NixOS.
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
  srcHash,
  driverHashes,
  browsers,
}:
let
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "playwright-python: unsupported system ${system}";
  driverZipName =
    {
      x86_64-linux = "linux";
      aarch64-linux = "linux-arm64";
    }
    .${system} or throwSystem;

  # Pre-built JS driver tarball: ships node + playwright-core JS code.
  # Layout (matches what playwright-python's _driver.py expects):
  #   ./node             -- bundled node binary
  #   ./package/cli.js   -- playwright-core entry point
  #   ./LICENSE
  driver = stdenv.mkDerivation {
    pname = "playwright-driver";
    inherit version;

    src = fetchzip {
      url = "https://cdn.playwright.dev/builds/driver/playwright-${version}-${driverZipName}.zip";
      stripRoot = false;
      hash = driverHashes.${system} or throwSystem;
    };

    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R . $out/
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
    substituteInPlace pyproject.toml \
      --replace-fail ', "auditwheel==6.2.0"' "" \
      --replace-fail "setuptools-scm==8.3.1" "setuptools-scm" \
      --replace-fail "setuptools==80.9.0" "setuptools" \
      --replace-fail "wheel==0.45.1" "wheel"
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
  '';

  postFixup = ''
    # The bundled `driver/node` aarch64 binary segfaults on NixOS even after
    # autoPatchelfHook (likely a glibc/stack-guard mismatch). Force the bundled
    # JS driver to use the system nodejs via PLAYWRIGHT_NODEJS_PATH, which
    # _driver.py honours.
    wrapProgram $out/bin/playwright \
      --set PLAYWRIGHT_BROWSERS_PATH ${browsers} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --set PLAYWRIGHT_NODEJS_PATH ${lib.getExe nodejs}
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
