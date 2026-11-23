# Static source linters and compile-time cache redistribution assertions.
{
  self,
  pkgs,
  lib,
  images,
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
  builtins.elem "vm-containers-driver" buildGroup.jobs
  && builtins.elem "vm-editor-driver" buildGroup.jobs
) "CI build group must include both VM test drivers";
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
