# Package the Node.js `playwright` library directly from the microsoft/playwright
# monorepo source tree. The published `playwright` package depends only on the
# sibling `playwright-core` package from the same repo, so we can install both
# package directories directly without going through npm.
{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  nodejs,
}:
{
  version,
  packageHash,
  coreHash,
  browsers,
  ...
}:
let
  playwrightPackage = fetchzip {
    url = "https://registry.npmjs.org/playwright/-/playwright-${version}.tgz";
    hash = packageHash;
  };

  playwrightCorePackage = fetchzip {
    url = "https://registry.npmjs.org/playwright-core/-/playwright-core-${version}.tgz";
    hash = coreHash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "playwright-node";
  inherit version;
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/playwright"
    mkdir -p "$out/lib/node_modules/playwright-core"
    cp -R ${playwrightPackage}/. "$out/lib/node_modules/playwright/"
    cp -R ${playwrightCorePackage}/. "$out/lib/node_modules/playwright-core/"

    for entry in index.js index.mjs; do
      tmp="$out/lib/node_modules/playwright/$entry.nix"
      cat > "$tmp" <<EOF
    if (!process.env.PLAYWRIGHT_BROWSERS_PATH) process.env.PLAYWRIGHT_BROWSERS_PATH = '${browsers}';
    if (!process.env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD) process.env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = '1';
    EOF
      cat "$out/lib/node_modules/playwright/$entry" >> "$tmp"
      mv "$tmp" "$out/lib/node_modules/playwright/$entry"
    done

    mkdir -p "$out/bin"
    makeWrapper ${lib.getExe nodejs} "$out/bin/playwright-node" \
      --set PLAYWRIGHT_BROWSERS_PATH ${browsers} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --prefix NODE_PATH : "$out/lib/node_modules" \
      --add-flags "$out/lib/node_modules/playwright/cli.js"

    mkdir -p "$out/nix-support"
    cat > "$out/nix-support/setup-hook" <<EOF
    addToSearchPath NODE_PATH "$out/lib/node_modules"
    EOF

    runHook postInstall
  '';

  meta = {
    description = "playwright ${version} (Node.js) bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright";
    mainProgram = "playwright-node";
  };
}
