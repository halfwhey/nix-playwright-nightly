{ pkgs }:
let
  mkBrowsers = pkgs.callPackage ./lib/mkBrowsers.nix { };
  readJSON = path: builtins.fromJSON (builtins.readFile path);

  mkCli = pin: pkgs.callPackage ./pkgs/playwright-cli.nix { } {
    version = pin.package;
    inherit (pin) srcHash npmDepsHash;
    browsers = mkBrowsers pin.browsers;
  };

  mkMcp = pin: pkgs.callPackage ./pkgs/playwright-mcp.nix { } {
    version = pin.package;
    inherit (pin) srcHash npmDepsHash;
    browsers = mkBrowsers pin.browsers;
  };

  mkPython = pin: pkgs.callPackage ./pkgs/playwright-python.nix { } {
    version = pin.package;
    inherit (pin) srcHash driverHashes;
    browsers = mkBrowsers pin.browsers;
  };

  # Attribute-name-safe version: nix CLI parses `.` as an attrpath separator
  # so we can't expose `playwright-cli-0.1.5` as a flat attribute name (the
  # user's `nix run .#playwright-cli-0.1.5` would try to descend into three
  # nested attrs). Replace dots with underscores for the attribute name only;
  # the pin file on disk still uses the dotted version.
  toAttr = v: builtins.replaceStrings [ "." ] [ "_" ] v;

  # Build the full attrset for one tool: versioned packages and versioned
  # browser passthroughs for every version in the manifest, plus latest
  # aliases that point at manifest.latest.
  buildTool =
    {
      prefix,
      manifestPath,
      pinDir,
      mk,
    }:
    let
      manifest = readJSON manifestPath;
      pinFor = v: readJSON (pinDir + "/${v}.json");
      versionedPkgs = map (v: {
        name = "${prefix}-${toAttr v}";
        value = mk (pinFor v);
      }) manifest.versions;
      versionedBrowsers = map (v: {
        name = "${prefix}-${toAttr v}-browsers";
        value = mkBrowsers (pinFor v).browsers;
      }) manifest.versions;
      latestPin = pinFor manifest.latest;
    in
    builtins.listToAttrs (versionedPkgs ++ versionedBrowsers)
    // {
      "${prefix}" = mk latestPin;
      "${prefix}-browsers" = mkBrowsers latestPin.browsers;
    };

  cliOutputs = buildTool {
    prefix = "playwright-cli";
    manifestPath = ./pins/cli.json;
    pinDir = ./pins/cli;
    mk = mkCli;
  };

  mcpOutputs = buildTool {
    prefix = "playwright-mcp";
    manifestPath = ./pins/mcp.json;
    pinDir = ./pins/mcp;
    mk = mkMcp;
  };

  pythonOutputs = buildTool {
    prefix = "playwright-python";
    manifestPath = ./pins/python.json;
    pinDir = ./pins/python;
    mk = mkPython;
  };
in
cliOutputs
// mcpOutputs
// pythonOutputs
// {
  default = cliOutputs."playwright-cli";
}
