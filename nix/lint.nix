# Static source linters, cache-layout contract checks, and compile-time cache redistribution assertions.
{
  self,
  pkgs,
  lib,
  images,
  cacheLayout,
}:
let
  ciManifest = import ./ci.nix { flake = self; };
  excludedSet = ciManifest.cache.excludedPaths;
  expectedExcluded =
    (map toString images.agents.restrictedPackages)
    ++ (map toString images.editor.restrictedPackages)
    ++ [
      (toString pkgs.vscode)
      (toString pkgs.vscode.vscodeServer)
    ];
  missingExcluded = builtins.filter (p: !(builtins.elem p excludedSet)) expectedExcluded;
  buildGroup = builtins.head (builtins.filter (g: g.name == "build") ciManifest.groups);
  buildJobNames = map (
    item: if builtins.isAttrs item then item.job or item.name else item
  ) buildGroup.jobs;

  mounts = cacheLayout.mounts or [ ];
  mountIds = map (m: m.id) mounts;
  mountTargets = map (m: m.target) mounts;
  envMismatches = builtins.filter (
    m: m.env != null && (images.fullEnv.${m.env} or null) != m.target
  ) mounts;

  source = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../.github/workflows
      ../runtime
      ../scripts
      ../tests
    ];
  };
in
assert lib.assertMsg (
  missingExcluded == [ ]
) "Restricted packages missing from cache.excludedPaths: ${builtins.toJSON missingExcluded}";
assert lib.assertMsg (
  builtins.elem "vm-containers-driver" buildJobNames && builtins.elem "vm-editor-driver" buildJobNames
) "CI build group must include both VM test drivers";
assert lib.assertMsg (
  (cacheLayout.version or null) == 1 && mounts != [ ]
) "data/cache-layout.json must declare version = 1 with a non-empty mounts list";
assert lib.assertMsg (
  builtins.length mountIds == builtins.length (lib.unique mountIds)
  && builtins.length mountTargets == builtins.length (lib.unique mountTargets)
) "data/cache-layout.json contains duplicate id or target entries";
assert lib.assertMsg (
  envMismatches == [ ]
) "data/cache-layout.json env mismatch against image Env: ${builtins.toJSON envMismatches}";
pkgs.runCommand "devcontainers-lint"
  {
    nativeBuildInputs = [
      pkgs.actionlint
      pkgs.ruff
      pkgs.shellcheck
    ];
  }
  ''
    cd ${source}
    actionlint .github/workflows/*.yml
    ruff check --no-cache scripts/*.py tests/*.py runtime/*/*.py
    shellcheck --shell=bash scripts/*.sh runtime/devcontainer-gui-env/main.sh
    touch "$out"
  ''
