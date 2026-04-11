{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  powershell,
  nodejs,
}:
{
  version,
  packageHash,
  browsers,
  ...
}:
let
  package = fetchzip {
    url = "https://api.nuget.org/v3-flatcontainer/microsoft.playwright/${version}/microsoft.playwright.${version}.nupkg";
    stripRoot = false;
    extension = "zip";
    hash = packageHash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "playwright-dotnet";
  inherit version;
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    root="$out/share/playwright-dotnet"
    mkdir -p "$root/.playwright" "$out/bin"

    cp ${package}/lib/netstandard2.0/Microsoft.Playwright.dll "$root/"
    cp ${package}/lib/netstandard2.0/Microsoft.Playwright.xml "$root/"
    cp ${package}/build/playwright.ps1 "$root/"
    cp -R ${package}/.playwright/. "$root/.playwright/"

    chmod +x "$root/.playwright/node/linux-x64/node"
    chmod +x "$root/.playwright/node/linux-arm64/node"
    chmod +x "$root/.playwright/node/darwin-x64/node"
    chmod +x "$root/.playwright/node/darwin-arm64/node"

    makeWrapper ${lib.getExe powershell} "$out/bin/playwright-dotnet" \
      --set PLAYWRIGHT_DRIVER_SEARCH_PATH "$root" \
      --set PLAYWRIGHT_NODEJS_PATH ${lib.getExe nodejs} \
      --set PLAYWRIGHT_BROWSERS_PATH ${browsers} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --add-flags "-NoLogo" \
      --add-flags "-NoProfile" \
      --add-flags "-File" \
      --add-flags "$root/playwright.ps1"

    runHook postInstall
  '';

  meta = {
    description = "Microsoft.Playwright ${version} (.NET) bundled with revision-matched browsers";
    homepage = "https://playwright.dev/dotnet/";
    mainProgram = "playwright-dotnet";
  };
}
