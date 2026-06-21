{
  pkgs,
  lib,
  targets,
  images,
}:

let
  vscodeGui = import ../tests/e2e/vscode-gui.nix {
    inherit pkgs lib;
  };
in
lib.listToAttrs (
  lib.concatMap (
    imageName:
    map (
      session:
      lib.nameValuePair "e2e-vscode-${imageName}-${session}" (
        vscodeGui.mkVscodeGuiTest {
          inherit imageName session;
          image = images.${imageName};
        }
      )
    ) vscodeGui.sessionNames
  ) targets.imageNames
)
