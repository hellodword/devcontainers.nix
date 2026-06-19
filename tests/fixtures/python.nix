{ self }:
{
  image = self.images.python;
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "language/python"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
