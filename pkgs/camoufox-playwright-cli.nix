{
  lib,
  runCommand,
  writeText,
}:
{
  camoufox,
  playwrightCli,
}:

let
  browser = camoufox.browser or (throw "camoufox-playwright-cli: camoufox package is missing browser passthru");
  browserExe = lib.getExe browser;
  config = writeText "camoufox-playwright-cli-config.json" (
    builtins.toJSON {
      browser = {
        browserName = "firefox";
        launchOptions = {
          executablePath = browserExe;
        };
      };
    }
  );
in
runCommand "camoufox-playwright-cli-${camoufox.version}"
  {
    passthru = {
      inherit
        browser
        camoufox
        config
        playwrightCli
        ;
    };

    meta = {
      description = "Playwright CLI wrapper configured to launch the Nix-packaged Camoufox browser";
      homepage = "https://github.com/daijro/camoufox";
      mainProgram = "camoufox-playwright-cli";
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/camoufox-playwright-cli"
    ln -s ${config} "$out/share/camoufox-playwright-cli/config.json"

    cat > "$out/bin/camoufox-playwright-cli" <<'WRAPPER'
    #!/bin/sh
    set -eu

    has_config=0
    has_browser=0
    wants_help=0
    command=

    for arg in "$@"; do
      case "$arg" in
        --config|--config=*)
          has_config=1
          ;;
        --browser|--browser=*)
          has_browser=1
          ;;
        --help|-h|--version)
          wants_help=1
          ;;
        -*)
          ;;
        *)
          if [ -z "$command" ]; then
            command="$arg"
          fi
          ;;
      esac
    done

    export PLAYWRIGHT_BROWSERS_PATH="${playwrightCli.browsers}"
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

    if [ "$command" = open ] && [ "$has_config" = 0 ] && [ "$has_browser" = 0 ] && [ "$wants_help" = 0 ]; then
      exec "${playwrightCli}/bin/.playwright-cli-real" --config "${config}" "$@"
    fi

    exec "${playwrightCli}/bin/.playwright-cli-real" "$@"
    WRAPPER
    chmod +x "$out/bin/camoufox-playwright-cli"
  ''
