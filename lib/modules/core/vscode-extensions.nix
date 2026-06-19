{ ... }:
{
  config.devcontainer.vscode = {
    extensions = [
      "redhat.vscode-yaml"
      "timonwong.shellcheck"
    ];

    settings = {
      "redhat.telemetry.enabled" = false;
      "yaml.schemaStore.enable" = true;
      "yaml.format.enable" = true;
      "shellcheck.executablePath" = "/usr/local/bin/shellcheck";
      "shellcheck.disableVersionCheck" = true;
    };
  };
}
