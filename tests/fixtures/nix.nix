{ self }:
{
  image = self.images."nix-latest";
  expectedNodes = [
    "runtime/nix"
    "language/nix"
    "runtime/fhs-vscode"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
