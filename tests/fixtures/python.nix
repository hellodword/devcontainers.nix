{ self }:
{
  image = self.images.python3;
  expectedNodes = [
    "runtime/python"
    "runtime/nodejs"
    "language/python"
    "toolset/editor-support"
    "toolset/docker-client"
    "toolset/agents"
    "toolset/nix-index"
  ];
}
