# CI manifest consumed by nixos-config infra#ci for verification, cache publication, and input updates.
{
  flake,
  system ? "x86_64-linux",
  select ? { },
}:
let
  inherit (flake.lib.${system}) cache images pkgs;
  inherit (flake.inputs.core.lib.ci) mkManifest;
  checks = flake.checks.${system};
  devShell = flake.devShells.${system}.default;
in
mkManifest {
  build = {
    inherit (checks)
      formatting
      lint
      runtime-cache
      publish
      ;
    oci = flake.packages.${system}.oci;
    publish-cli = flake.lib.${system}.publishAppPkg;
    dev-shell = devShell;
  };
  vmGroups = [
    {
      name = "vm-containers";
      checks = {
        inherit (checks) vm-containers;
      };
    }
    {
      name = "vm-editor";
      checks = {
        inherit (checks) vm-editor;
      };
    }
  ];
  cacheConfig = cache.config;
  cachePolicy = cache.mkPolicy {
    flakeOutPath = toString flake.outPath;
    candidates =
      images.foundation.storeDeps
      ++ images.toolchainsUsrPackages
      ++ images.agents.allPackages
      ++ images.editor.allPackages
      ++ checks.vm-editor.nodes.machine.environment.systemPackages
      ++ (devShell.nativeBuildInputs or [ ])
      ++ (devShell.buildInputs or [ ]);
    extraRestricted =
      images.agents.restrictedPackages
      ++ images.editor.restrictedPackages
      ++ [
        pkgs.vscode
        pkgs.vscode.vscodeServer
        pkgs.vscode-extensions.ms-vscode-remote.remote-containers
      ];
    extraExcluded = [
      images.image
      images.oci
    ];
    bundles = [
      images.image.drvPath
      images.oci.drvPath
      checks.vm-editor.driver.drvPath
    ];
  };
  update = {
    allowedLockfiles = [ "flake.lock" ];
    ignoreOnlyInputs = [ ];
    commitTitle = "chore: update flake inputs";
    branchPrefix = "automation/flake-update";
  };
}
