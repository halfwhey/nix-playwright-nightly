{ pkgs }:
let
  mkBrowsers = pkgs.callPackage ./lib/mkBrowsers.nix { };
  readJSON = path: builtins.fromJSON (builtins.readFile path);

  mkCli = pin: pkgs.callPackage ./pkgs/playwright-cli.nix { } {
    version = pin.package;
    inherit (pin) packageSha srcHash npmDepsHash;
    browsers = mkBrowsers pin.browsers;
  };

  mkMcp = pin: pkgs.callPackage ./pkgs/playwright-mcp.nix { } {
    version = pin.package;
    inherit (pin) packageSha srcHash npmDepsHash;
    browsers = mkBrowsers pin.browsers;
  };

  mkNode = pin: pkgs.callPackage ./pkgs/playwright-node.nix { } {
    version = pin.package;
    inherit (pin) packageHash coreHash;
    browsers = mkBrowsers pin.browsers;
  };

  mkDotnet = pin: pkgs.callPackage ./pkgs/playwright-dotnet.nix { } {
    version = pin.package;
    inherit (pin) packageHash;
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
  # aliases that point at toolManifest.latest.
  buildTool =
    {
      prefix,
      toolManifest,
      pinDir,
      mk,
    }:
    let
      pinFor = v: readJSON (pinDir + "/${v}.json");
      versionedPkgs = map (v: {
        name = "${prefix}-${toAttr v}";
        value = mk (pinFor v);
      }) toolManifest.versions;
      versionedBrowsers = map (v: {
        name = "${prefix}-${toAttr v}-browsers";
        value = mkBrowsers (pinFor v).browsers;
      }) toolManifest.versions;
      latestPin = pinFor toolManifest.latest;
    in
    builtins.listToAttrs (versionedPkgs ++ versionedBrowsers)
    // {
      "${prefix}" = mk latestPin;
      "${prefix}-browsers" = mkBrowsers latestPin.browsers;
    };

  pins = readJSON ./pins/pin.json;

  cliOutputs = buildTool {
    prefix = "playwright-cli";
    toolManifest = pins.cli;
    pinDir = ./pins/cli;
    mk = mkCli;
  };

  mcpOutputs = buildTool {
    prefix = "playwright-mcp";
    toolManifest = pins.mcp;
    pinDir = ./pins/mcp;
    mk = mkMcp;
  };

  nodeOutputs = buildTool {
    prefix = "playwright-node";
    toolManifest = pins.node;
    pinDir = ./pins/node;
    mk = mkNode;
  };

  dotnetOutputs = buildTool {
    prefix = "playwright-dotnet";
    toolManifest = pins.dotnet;
    pinDir = ./pins/dotnet;
    mk = mkDotnet;
  };

  pythonOutputs = buildTool {
    prefix = "playwright-python";
    toolManifest = pins.python;
    pinDir = ./pins/python;
    mk = mkPython;
  };
in
cliOutputs
// mcpOutputs
// nodeOutputs
// dotnetOutputs
// pythonOutputs
// {
  default = cliOutputs."playwright-cli";
}
