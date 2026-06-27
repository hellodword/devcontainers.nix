{
  pkgs,
  lib,
  compiler,
  nixpkgs,
  ...
}:

let
  checkedHelpers = builtins.filter (
    helper: helper ? checkName && helper ? checkScript && helper ? checkEnvName
  ) (builtins.attrValues compiler.runtimeHelpers);
  checkEnvExports = lib.concatMapStringsSep "\n" (
    helper: "export ${helper.checkEnvName}=${helper.package}"
  ) checkedHelpers;
  mkToolCheck =
    helper:
    pkgs.runCommand "tool-${helper.checkName}"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.python3
        ];
      }
      ''
        ${checkEnvExports}
        export DEVPKG_NIXPKGS_REF=path:${nixpkgs.outPath}
        python3 ${helper.checkScript}
        touch "$out"
      '';
  toolChecks = lib.listToAttrs (
    map (helper: lib.nameValuePair "tool-${helper.checkName}" (mkToolCheck helper)) checkedHelpers
  );
in
toolChecks
// {
  script-quality =
    pkgs.runCommand "script-quality"
      {
        nativeBuildInputs = [
          pkgs.findutils
          pkgs.python3
          pkgs.shellcheck
        ];
      }
      ''
        export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
        find ${../..}/runtime ${../..}/tests/ci ${../..}/tests/smoke -name '*.py' -print0 \
          | xargs -0 python3 -m py_compile
        find ${../..}/runtime ${../..}/tests/ci ${../..}/tests/smoke -name '*.sh' -print0 \
          | xargs -0 shellcheck
        touch "$out"
      '';
}
