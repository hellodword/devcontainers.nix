{
  inputs,
  nixpkgs,
  system,
}:
import inputs.nixpkgs {
  inherit system;
  config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
    oraclejdk.accept_license = true;

    allowUnsupportedSystem = true;
  };

  overlays = [
    inputs.nix-vscode-extensions.overlays.default
    (prev: final: { inherit (inputs.nix2container.packages.${system}) nix2container; })
    inputs.rust-overlay.overlays.default
    inputs.nix-index-database.overlays.nix-index
    inputs.llm-agents.overlays.default
  ]
  ++ (nixpkgs.lib.optionals (nixpkgs.rev == "e643668fd71b949c53f8626614b21ff71a07379d") [
    (final: prev: {
    })
  ])
  ++ (nixpkgs.lib.optionals (nixpkgs.rev == "2fb006b87f04c4d3bdf08cfdbc7fab9c13d94a15") [
    (final: prev: {
      pkgsCross = prev.pkgsCross // {
        mingwW64 = prev.pkgsCross.mingwW64 // {
          openssl = prev.pkgsCross.mingwW64.openssl.overrideAttrs (old: {
            patches = old.patches ++ [
              (prev.fetchpatch {
                url = "https://github.com/openssl/openssl/commit/af3a3f8205968f9e652efa7adf2a359f4eb9d9cc.patch";
                hash = "sha256-vOihzJnkPApLm3PblqJE7Rbm6x+TS+T6ZD33kO/7gw0=";
              })
            ];
          });
        };
      };
    })
  ]);
}
