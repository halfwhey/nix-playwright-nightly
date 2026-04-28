# buildNpmPackage wrapper for @playwright/mcp, fetched from
# microsoft/playwright-mcp at the commit SHA recorded in the pin file
# (not a version tag — pre-release alphas on npm are often published
# without a corresponding upstream tag) and bundled with the
# revision-matched browsers from this flake's mcp pin.
#
# microsoft/playwright-mcp v0.0.65..v0.0.70 was an npm workspace; the
# buildNpmPackage default install didn't expose the inner @playwright/mcp
# bin at $out/bin, so we linked it manually. From v0.0.71 the repo is a
# single @playwright/mcp package with bin.playwright-mcp set, so
# buildNpmPackage creates $out/bin/playwright-mcp itself — only fall back
# to the workspace symlink when that bin is missing.
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
    if [ ! -e $out/bin/playwright-mcp ]; then
      mkdir -p $out/bin
      ln -s $out/lib/node_modules/playwright-mcp-internal/packages/playwright-mcp/cli.js \
        $out/bin/playwright-mcp
    fi
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
