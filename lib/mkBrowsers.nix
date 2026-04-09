# mkBrowsers :: { browsers } -> derivation
#
# Takes a pin's `browsers` attrset and produces a single linkFarm whose
# top-level entries match the `${name}-${revision}` layout that
# playwright-core's registry expects when resolving PLAYWRIGHT_BROWSERS_PATH.
#
# Naming mirrors playwright-core/src/server/registry/index.ts (readDescriptors):
#
#   dir = browserDirectoryPrefix.replace(/-/g, '_') + '-' + revision
#
# so `chromium-headless-shell` becomes `chromium_headless_shell-<rev>`.
#
# Input shape (one per browser, all optional — missing entries are skipped):
#
#   {
#     chromium                = { revision = "1219"; browserVersion = "147.0.7727.49"; hash = "sha256-..."; };
#     chromium-headless-shell = { revision = "1219"; browserVersion = "147.0.7727.49"; hash = "sha256-..."; };
#     firefox                 = { revision = "1511"; hash = "sha256-..."; };
#     webkit                  = { revision = "2276"; hash = "sha256-..."; };
#     ffmpeg                  = { revision = "1011"; hash = "sha256-..."; };
#   }
{
  lib,
  callPackage,
  linkFarm,
  makeFontsConf,
  freefont_ttf,
}:
browsers:
let
  # Playwright's registry normalises dashes in browser names to underscores
  # when computing the on-disk directory name.
  dirPrefix = name: builtins.replaceStrings [ "-" ] [ "_" ] name;

  # Chromium needs a minimal fontconfig to avoid warnings; the actual fonts
  # don't matter for headless automation.
  fontconfig_file = makeFontsConf {
    fontDirectories = [ freefont_ttf ];
  };

  # Only chromium takes fontconfig_file; other fetchers don't accept extra args.
  fetcherOverrides = {
    chromium = { inherit fontconfig_file; };
  };

  mkEntry =
    name: spec:
    let
      fetcher = callPackage (./browsers + "/${name}.nix") (fetcherOverrides.${name} or { });
      drv = fetcher spec;
    in
    {
      name = "${dirPrefix name}-${spec.revision}";
      path = drv;
    };

  entries = lib.mapAttrsToList mkEntry browsers;
in
linkFarm "playwright-browsers" entries
