{ pkgs, ... }:
{
  config.devcontainer = {
    packages = [ pkgs.bashInteractive ];

    layers.buckets = [
      "00-base-runtime"
      "01-fhs-vscode-runtime"
      "02-fonts-runtime"
      "02-foundation-tools"
      "03-source-control-tools"
      "04-fetch-archive-tools"
      "05-search-navigation-tools"
      "06-inspect-debug-tools"
      "07-workflow-format-tools"
      "08-data-network-tools"
      "09-docker-client-tools"
      "10-nix-runtime"
      "11-nix-language"
      "12-nix-index-tools"
      "13-agent-tools"
      "14-shell-runtime"
      "20-c-env"
      "30-python-runtime"
      "31-python-language"
      "40-nodejs-runtime"
      "41-nodejs-language"
      "50-go-language"
      "51-rust-language"
      "60-flutter-language"
      "61-android-sdk"
      "62-browser-gui-gpu"
      "70-runtime-libraries"
      "71-build-libraries"
      "80-vscode-extensions-base"
      "81-vscode-extensions-nix"
      "82-vscode-extensions-python"
      "83-vscode-extensions-nodejs"
      "84-vscode-extensions-go"
      "85-vscode-extensions-rust"
      "86-vscode-extensions-flutter"
      "90-lifecycle-runtime"
      "95-dynamic-package-runtime"
      "99-fallback"
    ];

    graph.nodes."runtime/base" = {
      kind = "runtime";
      group = "00-base-runtime";
      paths = [ pkgs.bashInteractive ];
      stability = "very-stable";
      sharing = "global";
      priority = 100;
      securityClass = "trusted";
    };

    metadata.snippets = [
      {
        init = true;
        hostRequirements = {
          cpus = 2;
          memory = "4gb";
        };
      }
    ];
  };
}
