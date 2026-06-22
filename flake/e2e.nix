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
  canaryImages = [
    "nix-latest"
    "flutter-latest"
  ];
  canarySessions = [
    "x11-xfce"
    "wayland-kde"
  ];
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
    ) canarySessions
  ) canaryImages
)
