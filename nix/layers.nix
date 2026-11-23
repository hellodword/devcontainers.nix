# Pure /nix/store OCI layers shared across :latest and :agent plus :latest-only extension layers.
{
  pkgs,
  nix2container,
  foundation,
  toolchainsStoreDeps,
  agents,
  editor,
  runtime,
}:
let
  mkStorePermsFile =
    name: deps:
    pkgs.runCommand "devcontainer-store-perms-${name}.json"
      {
        __structuredAttrs = true;
        exportReferencesGraph.graph = deps;
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq '[.graph[].path | {
          path: .,
          regex: ".*",
          mode: "",
          uid: 1000,
          gid: 1000,
          uname: "vscode",
          gname: "vscode"
        }]' .attrs.json > "$out"
      '';

  mkStoreLayer =
    {
      name,
      deps,
      priorLayers ? [ ],
    }:
    (nix2container.buildLayer {
      inherit deps;
      layers = priorLayers;
      maxLayers = 1;
      permsFile = mkStorePermsFile name deps;
      metadata.created_by = "devcontainers.nix store layer ${name}";
    })
    // {
      # Flatten prior layers explicitly so buildImage never expands transitive duplicates.
      nestedLayers = [ ];
    };

  layer1Foundation = mkStoreLayer {
    name = "foundation";
    deps = foundation.storeDeps;
  };

  layer2Toolchains = mkStoreLayer {
    name = "toolchains";
    deps = toolchainsStoreDeps;
    priorLayers = [ layer1Foundation ];
  };

  layer3AgentsOss = mkStoreLayer {
    name = "agents-oss";
    deps = agents.ossPackages;
    priorLayers = [
      layer1Foundation
      layer2Toolchains
    ];
  };

  layer4AgentsRestricted = mkStoreLayer {
    name = "agents-restricted";
    deps = agents.restrictedPackages;
    priorLayers = [
      layer1Foundation
      layer2Toolchains
      layer3AgentsOss
    ];
  };

  sharedLayers = [
    layer1Foundation
    layer2Toolchains
    layer3AgentsOss
    layer4AgentsRestricted
  ];

  layer5ExtensionsOss = mkStoreLayer {
    name = "vscode-extensions-oss";
    deps = editor.ossPackages;
    priorLayers = sharedLayers;
  };

  layer6ExtensionsRestricted = mkStoreLayer {
    name = "vscode-extensions-restricted";
    deps = editor.restrictedPackages ++ runtime.editorHelpers;
    priorLayers = sharedLayers ++ [ layer5ExtensionsOss ];
  };

  devLayers = sharedLayers ++ [
    layer5ExtensionsOss
    layer6ExtensionsRestricted
  ];
in
{
  inherit
    mkStoreLayer
    sharedLayers
    devLayers
    ;
}
