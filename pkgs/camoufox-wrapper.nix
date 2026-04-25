{
  lib,
  python3Packages,
  fetchurl,
  makeWrapper,
  perl,
  browser,
  pypi ? "camoufox",
  version,
  url ? null,
  hash ? null,
  src ? null,
  playwrightPackage ? python3Packages.playwright,
}:

let
  source =
    if src != null then
      src
    else
      fetchurl {
        inherit url hash;
      };
  browserRoot = "${browser}/lib/camoufox-${browser.version}";
  pythonDeps = with python3Packages; [
    browserforge
    click
    inquirer
    language-tags
    lxml
    numpy
    orjson
    platformdirs
    playwrightPackage
    pysocks
    pyyaml
    requests
    rich
    rich-click
    screeninfo
    tqdm
    typing-extensions
    ua-parser
  ];
  pythonPath = python3Packages.makePythonPath pythonDeps;
in
python3Packages.buildPythonPackage {
  pname = pypi;
  inherit version;
  pyproject = true;

  src = source;

  build-system = with python3Packages; [
    poetry-core
  ];

  nativeBuildInputs = [
    makeWrapper
    perl
  ];

  dependencies = pythonDeps;

  postPatch = ''
        substituteInPlace camoufox/pkgman.py \
          --replace-fail 'LOCAL_DATA: Path = Path(os.path.abspath(__file__)).parent' 'LOCAL_DATA: Path = Path(os.path.abspath(__file__)).parent
    NIX_BROWSER_PATH = os.getenv("CAMOUFOX_BROWSER_PATH", "${browserRoot}")
    NIX_BROWSER_VERSION = os.getenv("CAMOUFOX_BROWSER_VERSION", "${browser.version}")'

        perl -0pi -e 's/(def installed_verstr\(\) -> str:\n    """[\s\S]*?"""\n)/$1    if NIX_BROWSER_VERSION:\n        return NIX_BROWSER_VERSION\n/s' camoufox/pkgman.py
        perl -0pi -e 's/(def camoufox_path\(download_if_missing: bool = True\) -> Path:\n    """[\s\S]*?"""\n)/$1    if NIX_BROWSER_PATH:\n        return Path(NIX_BROWSER_PATH)\n\n/s' camoufox/pkgman.py

    substituteInPlace camoufox/__main__.py \
      --replace '        self._pkg("Camoufox", "camoufox")' '        self._pkg("Camoufox", "${pypi}")' \
      --replace '        self._row("Install path", str(INSTALL_DIR), style="cyan")' '        self._row("Install path", NIX_BROWSER_PATH or str(INSTALL_DIR), style="cyan")' \
      --replace '    click.echo(INSTALL_DIR)' '    click.echo(NIX_BROWSER_PATH or INSTALL_DIR)' \
      --replace '    rprint(INSTALL_DIR, fg="green")' '    rprint(NIX_BROWSER_PATH or INSTALL_DIR, fg="green")'

    substituteInPlace camoufox/addons.py \
      --replace 'return get_path(os.path.join("addons", addon_name))' 'return os.path.join(os.getenv("CAMOUFOX_ADDONS_PATH", os.path.join(os.getenv("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "camoufox", "addons")), addon_name)' \
      --replace 'return str(ADDONS_DIR / addon_name)' 'return os.path.join(os.getenv("CAMOUFOX_ADDONS_PATH", str(ADDONS_DIR)), addon_name)'

    substituteInPlace camoufox/server.py \
      --replace 'config = launch_options(**kwargs)' 'config = {key: value for key, value in launch_options(**kwargs).items() if value is not None}' \
      --replace 'cwd=Path(nodejs).parent / "package",' 'cwd=Path(compute_driver_executable()[1]).parent,'

    perl -0pi -e 's/from \.pkgman import INSTALL_DIR,/from .pkgman import NIX_BROWSER_PATH, NIX_BROWSER_VERSION, INSTALL_DIR,/' camoufox/__main__.py
        perl -0pi -e 's/from \.pkgman import \(\n    INSTALL_DIR,/from .pkgman import (\n    INSTALL_DIR,\n    NIX_BROWSER_PATH,\n    NIX_BROWSER_VERSION,/' camoufox/__main__.py
        perl -0pi -e 's/        if active_v:\n            self\._row\("Current browser", f"v\{active_v\.version\.full_string\}"\)\n        else:\n            self\._row\("Current browser", "Not installed", style="dim"\)/        if NIX_BROWSER_VERSION:\n            self._row("Current browser", f"v{NIX_BROWSER_VERSION} (Nix)")\n        elif active_v:\n            self._row("Current browser", f"v{active_v.version.full_string}")\n        else:\n            self._row("Current browser", "Not installed", style="dim")/' camoufox/__main__.py
        perl -0pi -e 's/        if active_v:\n            self\._row\("Installed", "Yes", style="green"\)\n        else:\n            self\._row\("Installed", "No", style="red"\)/        if NIX_BROWSER_PATH or active_v:\n            self._row("Installed", "Yes", style="green")\n        else:\n            self._row("Installed", "No", style="red")/' camoufox/__main__.py
  '';

  doCheck = false;
  pythonImportsCheck = [ "camoufox" ];

  postFixup = ''
    wrapProgram "$out/bin/camoufox" \
      --set CAMOUFOX_BROWSER_PATH "${browserRoot}" \
      --set CAMOUFOX_BROWSER_VERSION "${browser.version}"
    makeWrapper "${python3Packages.python.interpreter}" "$out/bin/python" \
      --prefix PYTHONPATH : "$out/${python3Packages.python.sitePackages}:${pythonPath}" \
      --set CAMOUFOX_BROWSER_PATH "${browserRoot}" \
      --set CAMOUFOX_BROWSER_VERSION "${browser.version}"
    ln -s python "$out/bin/python3"
  '';

  passthru = {
    inherit browser;
  };

  meta = {
    description = "Camoufox Python wrapper bundled with the Nix-packaged Camoufox browser";
    homepage = "https://github.com/daijro/camoufox";
    license = lib.licenses.mit;
    mainProgram = "camoufox";
  };
}
