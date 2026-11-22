# CI manifest consumed by nixos-config infra#ci for verification, cache publication, and input updates.
{
  flake,
  system ? "x86_64-linux",
  select ? { },
}:
let
  cacheOnly = select.cacheOnly or false;
  pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;
  checks = flake.checks.${system};
  devShell = flake.devShells.${system}.default;
  inherit (flake.lib.${system}) cache images;

  baseProducts = {
    inherit (checks) formatting;
    oci = flake.packages.${system}.oci;
    dev-shell = devShell;
    vm-containers-driver = checks.vm-containers.driver;
    vm-editor-driver = checks.vm-editor.driver;
  };

  vmChecks = {
    inherit (checks) vm-containers vm-editor;
  };

  jobs = baseProducts // lib.optionalAttrs (!cacheOnly) vmChecks;

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
      checks.vm-containers.nodes.machine.system.build.vm.drvPath
      checks.vm-editor.nodes.machine.system.build.vm.drvPath
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
      jobs = builtins.attrNames baseProducts;
      required = true;
      vm = null;
      kvm = false;
      maxJobs = 1;
    }
  ]
  ++ lib.optionals (!cacheOnly) [
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
    mode = "end-of-phase";
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
