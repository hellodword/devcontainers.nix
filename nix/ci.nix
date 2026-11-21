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
  };

  vmChecks = {
    inherit (checks) vm-containers vm-editor;
    vm-containers-driver = checks.vm-containers.driver;
    vm-editor-driver = checks.vm-editor.driver;
  };

  jobs = baseProducts // lib.optionalAttrs (!cacheOnly) vmChecks;

  cachePolicy = cache.mkPolicy {
    flakeOutPath = toString flake.outPath;
    candidates =
      images.foundation.storeDeps
      ++ images.toolchainsUsrPackages
      ++ images.agents.allPackages
      ++ images.editor.allPackages
      ++ (devShell.nativeBuildInputs or [ ])
      ++ (devShell.buildInputs or [ ]);
    extraRestricted = images.agents.restrictedPackages ++ images.editor.restrictedPackages;
    extraExcluded = [
      images.dev
      images.agent
      images.oci
      pkgs.vscode
      pkgs.vscode.vscodeServer
    ];
    bundles = [
      images.dev.drvPath
      images.agent.drvPath
      images.oci.drvPath
    ]
    ++ lib.optionals (!cacheOnly) [
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
      jobs =
        builtins.attrNames baseProducts
        ++ lib.optionals (!cacheOnly) [
          "vm-containers-driver"
          "vm-editor-driver"
        ];
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
