{ ... }:
{
  config.devcontainer.layers.bucketDefinitions."editor-support-tools" = {
    order = 10600;
    owner = "toolsets/editor-support";
    purpose = "Reusable editor language support tools for data and markup formats.";
  };

  config.devcontainer.profiles."toolset/editor-support" = {
    kind = "toolset";
    group = "editor-support-tools";
    packages = [ ];
    priority = 82;
    stability = "medium";
    sharing = "global";
    securityClass = "trusted";
    composition.role = "bundle";
    includes = [
      "language/yaml"
      "language/xml"
      "language/toml"
      "language/jinja"
      "language/protobuf"
      "toolset/editor-support/smoke"
    ];
  };

  config.devcontainer.profiles."toolset/editor-support/smoke" = {
    kind = "toolset";
    group = "editor-support-tools";
    packages = [ ];
    priority = 82;
    stability = "medium";
    sharing = "global";
    securityClass = "trusted";
    tests.cases."editor-support.tools" = {
      tags = [
        "smoke"
        "tooling"
        "editor-support"
      ];
      scripts = [
        {
          shell = "bash";
          interactive = false;
          command = ''
            set -e
            yaml-language-server --version
            minijinja-cli --version
            protoc --version
            protols --version
            buf --version
            protolint version
            grpcurl -version
            api-linter --version
          '';
        }
      ];
    };
  };
}
