# buildNpmPackage wrapper for @playwright/mcp, fetched from
# microsoft/playwright-mcp at the commit SHA recorded in the pin file
# (not a version tag — pre-release alphas on npm are often published
# without a corresponding upstream tag) and bundled with the
# revision-matched browsers from this flake's mcp pin.
#
# microsoft/playwright-mcp v0.0.65+ is an npm workspace; the buildNpmPackage
# default install doesn't expose the inner @playwright/mcp bin at
# $out/bin, so we link it manually.
{
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
}:
{
  version,
  packageSha,
  srcHash,
  npmDepsHash,
  browsers,
}:
buildNpmPackage {
  pname = "playwright-mcp";
  inherit version;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-mcp";
    rev = packageSha;
    hash = srcHash;
  };

  inherit npmDepsHash;
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    mkdir -p $out/bin
    ln -s $out/lib/node_modules/playwright-mcp-internal/packages/playwright-mcp/cli.js \
      $out/bin/playwright-mcp
  '';

  postFixup = ''
    wrapProgram $out/bin/playwright-mcp \
      --set PLAYWRIGHT_BROWSERS_PATH ${browsers} \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1
  '';

  meta = {
    description = "playwright-mcp ${version} (MCP server) bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright-mcp";
    mainProgram = "playwright-mcp";
  };
}
