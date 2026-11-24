# CI manifest consumed by nixos-config infra#ci for verification, cache publication, and input updates.
{
  flake,
  system ? "x86_64-linux",
  select ? { },
}:
let
  inherit (flake.lib.${system}) cache images pkgs;
  inherit (pkgs) lib;
  checks = flake.checks.${system};
  devShell = flake.devShells.${system}.default;

  baseProducts = {
    inherit (checks) formatting lint;
    oci = flake.packages.${system}.oci;
    dev-shell = devShell;
  };

  vmDrivers = {
    vm-containers-driver = checks.vm-containers.driver;
    vm-editor-driver = checks.vm-editor.driver;
  };

  vmChecks = {
    inherit (checks) vm-containers vm-editor;
  };

  jobs = baseProducts // vmDrivers // vmChecks;

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
      images.dev
      images.agent
      images.oci
    ];
    bundles = [
      images.dev.drvPath
      images.agent.drvPath
      images.oci.drvPath
      checks.vm-editor.driver.drvPath
    ];
  };
in
{
  inherit jobs;

  groups = [
    {
      name = "private";
      jobs = [ ];
      required = true;
      vm = null;
      kvm = false;
      maxJobs = 1;
    }
    {
      name = "build";
      jobs = builtins.attrNames baseProducts ++ [
        {
          job = "vm-containers-driver";
          prepares = "vm-containers";
        }
        {
          job = "vm-editor-driver";
          prepares = "vm-editor";
        }
      ];
      required = true;
      vm = null;
      kvm = false;
      maxJobs = 1;
    }
    {
      name = "vm-containers";
      jobs = [ "vm-containers" ];
      required = true;
      vm = "nixos";
      kvm = true;
      maxJobs = 1;
    }
    {
      name = "vm-editor";
      jobs = [ "vm-editor" ];
      required = true;
      vm = "nixos";
      kvm = true;
      maxJobs = 1;
    }
  ];

  cache = {
    registry = cache.identity.registry or "ghcr.io";
    inherit (cache.identity) repository publicKey;
    mode = "incremental";
    targetUri = cache.ci.uri;
    readSubstituters = cache.ci.settings.substituters;
    trustedPublicKeys = cache.ci.settings.trusted-public-keys;
    inherit (cachePolicy)
      excludedPaths
      excludedDerivations
      bundles
      privateBuilds
      ;
  };

  update = {
    allowedLockfiles = [ "flake.lock" ];
    ignoreOnlyInputs = [ ];
    commitTitle = "chore: update flake inputs";
    branchPrefix = "automation/flake-update";
  };
}
