# buildNpmPackage wrapper for @playwright/cli, fetched from
# microsoft/playwright-cli at the matching tag and bundled with the
# revision-matched browsers from this flake's cli pin.
{
  buildNpmPackage,
  fetchFromGitHub,
}:
{
  version,
  srcHash,
  npmDepsHash,
  browsers,
}:
buildNpmPackage {
  pname = "playwright-cli";
  inherit version;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-cli";
    rev = "v${version}";
    hash = srcHash;
  };

  inherit npmDepsHash;
  dontNpmBuild = true;

  # Hand-rolled wrapper instead of wrapProgram because we need to conditionally
  # inject `--browser chromium`. Playwright's default browser channel is
  # branded `chrome` (hardcoded to `/opt/google/chrome/chrome`, no env override
  # per playwright-core/lib/tools/mcp/config.js:validateBrowserConfig) which is
  # a dead end on NixOS. We only inject when the user hasn't already passed
  # `--browser` themselves, because minimist wraps duplicate flag values in an
  # array which breaks downstream callers.
  postFixup = ''
    mv $out/bin/playwright-cli $out/bin/.playwright-cli-real
    cat > $out/bin/playwright-cli <<WRAPPER
    #!/bin/sh
    export PLAYWRIGHT_BROWSERS_PATH="${browsers}"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    for _arg in "\$@"; do
      case "\$_arg" in
        --browser|--browser=*)
          exec "$out/bin/.playwright-cli-real" "\$@"
          ;;
      esac
    done
    exec "$out/bin/.playwright-cli-real" --browser chromium "\$@"
    WRAPPER
    chmod +x $out/bin/playwright-cli
  '';

  meta = {
    description = "playwright-cli ${version} bundled with revision-matched browsers";
    homepage = "https://github.com/microsoft/playwright-cli";
    mainProgram = "playwright-cli";
  };
}
