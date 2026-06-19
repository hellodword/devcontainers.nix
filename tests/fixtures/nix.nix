{ self }:
{
  image = self.images.nix;
  expectedNodes = [
    "runtime/nix"
    "language/nix"
    "runtime/fhs-vscode"
  ];
}
