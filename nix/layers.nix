# Pure /nix/store OCI layers shared across :latest and :agent plus :latest-only extension layers.
{
  nix2container,
  foundation,
  toolchainsStoreDeps,
  agents,
  editor,
}:
let
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
    deps = editor.restrictedPackages;
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
